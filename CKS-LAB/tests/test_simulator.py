"""Offline regression tests: no real cluster, daemon, network or host changes."""
import base64
from copy import deepcopy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('score', ROOT / 'score.py')
score = importlib.util.module_from_spec(spec)
spec.loader.exec_module(score)


def pod(containers=None):
    return {'spec': {'containers': containers or [{'name': 'good-app'}]},
            'status': {'phase': 'Running', 'conditions': [{'type': 'Ready', 'status': 'True'}]}}


class GradingTests(unittest.TestCase):
    def test_network_cannot_pass_by_name_or_with_additive_allow(self):
        p = {'metadata': {'name': 'default-deny-all'}, 'spec': {'podSelector': {}, 'policyTypes': ['Ingress', 'Egress']}}
        self.assertTrue(score.check_network({'items': [p]}))
        self.assertFalse(score.check_network({'items': [{'metadata': p['metadata']}]}))
        for rules in ('ingress', 'egress'):
            bad = deepcopy(p); bad['spec'][rules] = [{}]
            self.assertFalse(score.check_network({'items': [bad]}))
            self.assertFalse(score.check_network({'items': [p, {'spec': {rules: [{}]}}]}))

    def test_missing_or_unready_pod_never_counts_as_removal(self):
        self.assertFalse(score.check_multi({}))
        p = pod(); self.assertTrue(score.check_multi(p))
        p['spec']['containers'].append({'name': 'vulnerable-app'})
        self.assertFalse(score.check_multi(p))
        p = pod(); p['status']['conditions'] = []
        self.assertFalse(score.check_multi(p))

    def test_dockerfile_comments_and_root_override(self):
        good = 'FROM alpine\nRUN adduser -S appuser -u 1000\nUSER appuser\n'
        self.assertTrue(score.check_dockerfile(good))
        for bad in ('FROM alpine\n# USER appuser', good + 'USER root\n', good + 'FROM alpine\n', 'USER appuser'):
            self.assertFalse(score.check_dockerfile(bad))

    def test_token_requires_sa_and_actual_mount(self):
        sa = {'automountServiceAccountToken': False}
        p = pod([{'name': 'nginx', 'volumeMounts': [{'name': 'tokens', 'mountPath': '/var/run/secrets/tokens'}]}])
        p['spec'].update(serviceAccountName='db-sa', volumes=[{'name': 'tokens', 'projected': {'sources': [{'serviceAccountToken': {'path': 'token', 'audience': 'api', 'expirationSeconds': 7200}}]}}])
        self.assertTrue(score.check_token(sa, p))
        self.assertFalse(score.check_token({}, p))
        p['spec']['containers'][0]['volumeMounts'] = []
        self.assertFalse(score.check_token(sa, p))

    def test_rbac_rejects_secret_and_wildcard_permissions(self):
        role = {'rules': [{'apiGroups': [''], 'resources': ['pods'], 'verbs': ['get', 'list']}]}
        binding = {'roleRef': {'apiGroup': 'rbac.authorization.k8s.io', 'kind': 'Role', 'name': 'auditor'}, 'subjects': [{'kind': 'ServiceAccount', 'name': 'auditor', 'namespace': 'rbac'}]}
        self.assertTrue(score.check_rbac(role, binding))
        for field, value in [('resources', ['pods', 'secrets']), ('verbs', ['*'])]:
            bad = deepcopy(role); bad['rules'][0][field] = value
            self.assertFalse(score.check_rbac(bad, binding))
        with patch.object(score, 'get', side_effect=[role, binding]), patch.object(score.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, 'yes\n', '')):
            self.assertFalse(score.rbac_evidence())

    def test_reports_reject_empty_files_and_wrong_target(self):
        self.assertFalse(score.check_sbom(''))
        self.assertFalse(score.check_sbom('{}'))
        bom = {'spdxVersion': 'SPDX-2.3', 'SPDXID': 'SPDXRef-DOCUMENT', 'dataLicense': 'CC0-1.0', 'name': 'nginx', 'documentNamespace': 'https://example.test/bom', 'packages': [{'name': 'nginx'}]}
        self.assertTrue(score.check_sbom(json.dumps(bom)))
        report = {'SchemaVersion': 2, 'ArtifactName': 'httpd:2.4.49', 'ArtifactType': 'container_image', 'Results': [{'Target': 'httpd', 'Type': 'debian', 'Vulnerabilities': [{'VulnerabilityID': 'CVE-example', 'Severity': 'CRITICAL'}]}]}
        self.assertTrue(score.check_trivy(report))
        for bad in ({}, dict(report, ArtifactName='nginx'), dict(report, Results=[])):
            self.assertFalse(score.check_trivy(bad))
        report['Results'][0]['Vulnerabilities'][0]['Severity'] = 'HIGH'
        self.assertFalse(score.check_trivy(report))

    def test_readonly_requires_running_pod(self):
        p = pod([{'securityContext': {'readOnlyRootFilesystem': True}}])
        self.assertTrue(score.check_immutable(p))
        p['status']['phase'] = 'Pending'
        self.assertFalse(score.check_immutable(p))

    def test_image_requires_rollout(self):
        d = {'metadata': {'generation': 2}, 'spec': {'replicas': 1, 'template': {'spec': {'containers': [{'name': 'httpd', 'image': 'httpd:2.4.58'}]}}}, 'status': {'observedGeneration': 2, 'updatedReplicas': 1, 'availableReplicas': 1, 'replicas': 1}}
        self.assertTrue(score.check_image(d))
        d['status']['observedGeneration'] = 1
        self.assertFalse(score.check_image(d))

    def test_command_failure_is_not_negative_evidence(self):
        with patch.object(score.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'connection refused')):
            with self.assertRaises(score.EvidenceError):
                score.command(['minikube', 'ssh'])

    def test_tls_type_and_matching_pair(self):
        self.assertFalse(score.check_tls({'type': 'Opaque'}))
        with tempfile.TemporaryDirectory() as tmp:
            cert, key, wrong = (Path(tmp) / n for n in ('cert', 'key', 'wrong'))
            subprocess.run(['openssl', 'req', '-x509', '-nodes', '-newkey', 'rsa:2048', '-days', '1', '-subj', '/CN=test', '-keyout', str(key), '-out', str(cert)], check=True, capture_output=True)
            subprocess.run(['openssl', 'genpkey', '-algorithm', 'RSA', '-pkeyopt', 'rsa_keygen_bits:2048', '-out', str(wrong)], check=True, capture_output=True)
            s = {'type': 'kubernetes.io/tls', 'data': {n: base64.b64encode(p.read_bytes()).decode() for n, p in [('tls.crt', cert), ('tls.key', key)]}}
            self.assertTrue(score.check_tls(s))
            s['data']['tls.key'] = base64.b64encode(wrong.read_bytes()).decode()
            self.assertFalse(score.check_tls(s))


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for name in ('k8s-sim.sh', 'exam-setup.sh', 'exam-cleanup.sh', 'lab-common.sh', 'score.py', 'attempt_archive.py', 'editor-setup.sh', 'node-client-setup.sh'):
            shutil.copy2(ROOT / name, self.root / name)
        self.state = self.root / '.cks-state'; self.state.mkdir()
        bindir = self.root / 'bin'; bindir.mkdir()
        self.log = self.root / 'calls'
        mock = bindir / 'minikube'
        mock.write_text("""#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ['TEST_LOG'], 'a') as log:
    log.write(' '.join(args) + '\\n')
args = [a for a in args if a != '--context=cks-lab']
if args[0] == 'profile':
    print(os.environ['PROFILES']); sys.exit(0)
assert args[:2] == ['-p', 'cks-lab'], args
if args[2:6] == ['kubectl', '--', 'config', 'current-context']:
    print(os.environ.get('CURRENT_CONTEXT', '')); sys.exit(0)
if args[2:5] == ['kubectl', '--', 'get'] and any('jsonpath' in a for a in args):
    print(os.environ.get('ACTUAL_UID', 'owned'), end=''); sys.exit(0)
if args[2:6] == ['kubectl', '--', 'get', 'namespace'] and args[6] == 'kube-system':
    print(json.dumps({'metadata': {'uid': 'owned'}})); sys.exit(0)
if args[2:6] == ['kubectl', '--', 'get', 'node']:
    print(os.environ.get('NODE_JSON', json.dumps({'status': {'nodeInfo': {'kubeletVersion': 'v1.35.0'}, 'addresses': [{'type': 'InternalIP', 'address': '192.0.2.10'}]}}))); sys.exit(0)
if args[2:5] == ['kubectl', '--', 'get']:
    print(json.dumps({'kind': 'List', 'items': []}) if ',' in args[5] else '{}'); sys.exit(0)
if args[2] == 'delete' and os.environ.get('FAIL_DELETE') == '1':
    sys.exit(1)
if args[2] == 'ssh' and 'tar -C /opt' in args[-1]:
    if os.environ.get('FAIL_NODE_ARCHIVE') == '1': sys.exit(1)
    import base64, io, tarfile
    data = io.BytesIO()
    with tarfile.open(fileobj=data, mode='w:gz') as archive:
        member = tarfile.TarInfo('cks-lab/node-answer.txt')
        payload = b'node answer'
        member.size = len(payload)
        archive.addfile(member, io.BytesIO(payload))
    sys.stdout.buffer.write(base64.encodebytes(data.getvalue()).replace(b'\\n', b'\\r\\n')); sys.exit(0)
if args[2] == 'ssh' and 'config view --minify' in args[-1]:
    print('kubernetes https://control-plane.minikube.internal:8443'); sys.exit(0)
if args[2] == 'ssh':
    if os.environ.get('FAIL_SETUP') == '1' or args[-1].startswith('cat ') or 'fixture-marker;' in args[-1]:
        sys.exit(1)
    sys.exit(0)
if args[2:5] == ['kubectl', '--', 'apply']:
    sys.stdin.read()
sys.exit(0)
""")
        mock.chmod(0o755)
        kubectl = bindir / 'kubectl'
        kubectl.write_text('#!/bin/bash\nexec minikube -p cks-lab kubectl -- "$@"\n')
        kubectl.chmod(0o755)
        self.env = dict(os.environ, PATH=str(bindir) + os.pathsep + os.environ['PATH'], TEST_LOG=str(self.log), PROFILES='{"valid":[],"invalid":[]}')

    def run_lab(self, *args):
        return subprocess.run(['bash', str(self.root / 'k8s-sim.sh'), *args], cwd='/', env=self.env, capture_output=True, text=True)

    def test_cleanup_without_ownership_never_calls_minikube(self):
        self.assertNotEqual(self.run_lab('cleanup').returncode, 0)
        self.assertFalse(self.log.exists())

    def test_cleanup_uid_mismatch_never_deletes(self):
        (self.state / 'cluster-uid').write_text('owned')
        self.env['ACTUAL_UID'] = 'other'
        self.assertNotEqual(self.run_lab('cleanup').returncode, 0)
        self.assertNotIn(' delete', self.log.read_text())

    def test_cleanup_only_deletes_owned_profile_and_retains_files(self):
        (self.state / 'cluster-uid').write_text('owned')
        (self.state / 'deadline').write_text('1')
        jump = self.state / 'jumpbox'; jump.mkdir(); (jump / 'answer').write_text('keep')
        result = self.run_lab('cleanup')
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.log.read_text().splitlines()
        self.assertTrue(all(s.startswith('-p cks-lab ') for s in lines))
        self.assertIn('-p cks-lab delete', lines)
        self.assertTrue((jump / 'answer').exists())
        self.assertFalse((self.state / 'deadline').exists())

    def test_existing_profile_start_refused(self):
        self.env['PROFILES'] = '{"valid":[{"Name":"cks-lab"}],"invalid":[]}'
        self.assertNotEqual(self.run_lab('start').returncode, 0)
        self.assertEqual(self.log.read_text().splitlines(), ['profile list -o json'])


    def test_node_clients_use_internal_api_and_owned_nodes(self):
        (self.state / 'cluster-uid').write_text('owned')
        (self.state / 'mode').write_text('exam')
        result = subprocess.run(['bash', str(self.root / 'node-client-setup.sh')], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.log.read_text()
        self.assertIn("--server='https://192.0.2.10:8443'", calls)
        self.assertIn('-p cks-lab cp cks-lab:/opt/cks-lab/client/config cks-lab-m02:/opt/cks-lab/client/config', calls)
        self.assertIn('chmod 600 /opt/cks-lab/client/config', calls)
        self.assertNotIn('insecure-skip-tls-verify', calls)

    def test_invalid_node_address_prevents_client_changes(self):
        (self.state / 'cluster-uid').write_text('owned')
        self.env['NODE_JSON'] = json.dumps({'status': {'nodeInfo': {'kubeletVersion': 'v1.35.0'}, 'addresses': [{'type': 'InternalIP', 'address': 'bad-address'}]}})
        result = subprocess.run(['bash', str(self.root / 'node-client-setup.sh')], env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(' ssh ', self.log.read_text())
        self.assertNotIn(' cp ', self.log.read_text())

    def test_start_uses_isolated_driver_and_preserves_context(self):
        result = self.run_lab('start')
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.log.read_text()
        self.assertIn('-p cks-lab start --kubernetes-version=v1.35.0 --cni=calico --driver=docker --container-runtime=containerd --keep-context', calls)
        self.assertTrue((self.state / 'setup-complete').exists())
        self.assertTrue((self.state / 'deadline').exists())
        self.assertNotIn('--all --purge', calls)

    def test_empty_or_previous_lab_context_is_selected_after_successful_setup(self):
        for current in ('', 'cks-lab'):
            with self.subTest(context=current):
                self.env['CURRENT_CONTEXT'] = current
                # A different simulated previous attempt for each iteration.
                self.env['PROFILES'] = '{"valid":[],"invalid":[]}'
                self.log.unlink(missing_ok=True)
                result = self.run_lab('start')
                self.assertEqual(result.returncode, 0, result.stderr)
                calls = self.log.read_text()
                self.assertIn('config use-context cks-lab', calls)
                self.assertGreater(calls.index('config use-context cks-lab'), calls.index('fixture-marker'))

    def test_unrelated_context_is_preserved(self):
        self.env['CURRENT_CONTEXT'] = 'other-cluster'
        result = self.run_lab('start')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('config use-context', self.log.read_text())

    def test_setup_failure_never_starts_timer(self):
        self.env['FAIL_SETUP'] = '1'
        result = self.run_lab('start')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.state / 'deadline').exists())
        self.assertFalse((self.state / 'setup-complete').exists())
        self.assertTrue((self.state / 'cluster-uid').exists())
        self.assertNotIn('config use-context', self.log.read_text())

    def test_saved_answers_are_archived_automatically(self):
        jump = self.state / 'jumpbox'; jump.mkdir(); (jump / 'answer').write_text('keep')
        result = self.run_lab('start')
        self.assertEqual(result.returncode, 0, result.stderr)
        backups = list((self.state / 'archives').iterdir())
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / 'jumpbox' / 'answer').read_text(), 'keep')
        self.assertFalse((jump / 'answer').exists())
        self.assertTrue((jump / 'Dockerfile').exists())

    def previous_attempt(self):
        (self.state / 'cluster-uid').write_text('owned')
        (self.state / 'deadline').write_text('1')
        (self.state / 'setup-complete').touch()
        jump = self.state / 'jumpbox'; jump.mkdir(); (jump / 'answer').write_text('keep')
        self.env['PROFILES'] = '{"valid":[{"Name":"cks-lab"}],"invalid":[]}'
        return jump

    def test_owned_previous_cluster_is_backed_up_then_replaced(self):
        import tarfile
        self.previous_attempt()
        result = self.run_lab('start')
        self.assertEqual(result.returncode, 0, result.stderr)
        backup = next((self.state / 'archives').iterdir())
        self.assertEqual((backup / 'jumpbox' / 'answer').read_text(), 'keep')
        self.assertEqual((backup / 'deadline').read_text(), '1')
        self.assertEqual(json.loads((backup / 'cluster-resources.json').read_text())['items'], [])
        with tarfile.open(backup / 'node-files.tar.gz') as archive:
            self.assertEqual(archive.extractfile('cks-lab/node-answer.txt').read(), b'node answer')
        calls = self.log.read_text()
        self.assertLess(calls.index('tar -C /opt'), calls.index('-p cks-lab delete'))
        self.assertLess(calls.index('-p cks-lab delete'), calls.index('-p cks-lab start'))
        self.assertGreater(int((self.state / 'deadline').read_text()), 1)

    def test_failed_node_backup_preserves_active_attempt(self):
        jump = self.previous_attempt()
        self.env['FAIL_NODE_ARCHIVE'] = '1'
        self.assertNotEqual(self.run_lab('start').returncode, 0)
        self.assertEqual((jump / 'answer').read_text(), 'keep')
        self.assertEqual((self.state / 'deadline').read_text(), '1')
        self.assertNotIn('-p cks-lab delete', self.log.read_text())
        self.assertNotIn('-p cks-lab start', self.log.read_text())

    def test_failed_deletion_preserves_current_answers_and_timer(self):
        jump = self.previous_attempt()
        self.env['FAIL_DELETE'] = '1'
        self.assertNotEqual(self.run_lab('start').returncode, 0)
        self.assertEqual((jump / 'answer').read_text(), 'keep')
        self.assertEqual((self.state / 'deadline').read_text(), '1')
        self.assertNotIn('-p cks-lab start', self.log.read_text())

    def test_restart_refuses_wrong_cluster_owner(self):
        jump = self.previous_attempt()
        self.env['ACTUAL_UID'] = 'other'
        self.assertNotEqual(self.run_lab('start').returncode, 0)
        self.assertEqual((jump / 'answer').read_text(), 'keep')
        self.assertFalse((self.state / 'archives').exists())
        self.assertNotIn('-p cks-lab delete', self.log.read_text())

    def test_invalid_start_does_not_archive_or_delete(self):
        jump = self.previous_attempt()
        self.env['CKS_KUBERNETES_VERSION'] = 'invalid'
        self.assertNotEqual(self.run_lab('start').returncode, 0)
        self.assertEqual((jump / 'answer').read_text(), 'keep')
        self.assertFalse((self.state / 'archives').exists())
        self.assertFalse(self.log.exists())

    def test_unmodified_baseline_has_zero_configuration_points(self):
        (self.state / 'cluster-uid').write_text('owned')
        (self.state / 'setup-complete').touch()
        result = self.run_lab('score')
        self.assertIn('Configuration checks: 0/55', result.stdout)
        self.assertIn('11 manual', result.stdout)
        self.assertNotIn('auto-pass', result.stdout.lower().replace('no architecture auto-pass.', ''))

    def test_wrapper_forces_context_and_rejects_overrides(self):
        (self.state / 'cluster-uid').write_text('owned')
        self.assertEqual(self.run_lab('kubectl', 'get', 'pods').returncode, 0)
        self.assertIn('kubectl -- --context=cks-lab get pods', self.log.read_text())
        for option in ('--context=production', '--server=https://example.test', '--kubeconfig=other'):
            self.assertNotEqual(self.run_lab('kubectl', 'get', 'pods', option).returncode, 0)
        self.assertNotEqual(self.run_lab('kubectl', 'config', 'use-context', 'production').returncode, 0)
        self.assertNotIn('production', self.log.read_text())

    def test_timer_expiration_without_process(self):
        (self.state / 'deadline').write_text('1')
        self.assertEqual(self.run_lab('time').stdout.strip(), 'EXPIRED')
        self.assertFalse(self.log.exists())

    def test_unreadable_profiles_fail_closed(self):
        for invalid in ('bad-json', '{}', 'null', '{"valid":null,"invalid":[]}'):
            self.env['PROFILES'] = invalid
            self.assertNotEqual(self.run_lab('start').returncode, 0)
        self.assertNotIn(' start', self.log.read_text())

    def test_second_mock_score_forwards_task_selection(self):
        (self.state / 'cluster-uid').write_text('owned')
        (self.state / 'mode').write_text('exam')
        folder = self.root / 'secon_version'; folder.mkdir()
        (folder / 'exam_mode.py').write_text('import sys; print(repr(sys.argv[1:]))')
        result = self.run_lab('score', '--task', '1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("['score', '--task', '1']", result.stdout)

    def test_score_refuses_incomplete_setup(self):
        (self.state / 'cluster-uid').write_text('owned')
        self.assertNotEqual(self.run_lab('score').returncode, 0)


if __name__ == '__main__':
    unittest.main()
