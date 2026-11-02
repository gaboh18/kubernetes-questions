"""Regression cases for the 16-task mock; no cluster/network side effects."""
from contextlib import redirect_stdout
from copy import deepcopy
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "tests"))
sys.path.insert(0, str(ROOT / "secon_version"))
import exam_mode as exam
import test_simulator


def spec(uid=30000):
    return {'containers': [{'name': 'app', 'image': 'busybox:1.37', 'securityContext': {
        'runAsUser': uid, 'readOnlyRootFilesystem': True, 'privileged': False,
        'allowPrivilegeEscalation': False}}]}


def ready_pod(name='probe', namespace='exam-allowed', app='api'):
    return {'metadata': {'name': name, 'namespace': namespace, 'labels': {'app': app}},
            'spec': spec(), 'status': {'podIP': '10.1.2.3', 'phase': 'Running',
                'conditions': [{'type': 'Ready', 'status': 'True'}]}}


class ExamGradingTests(unittest.TestCase):
    def test_weights_and_automatic_ceiling(self):
        self.assertEqual(len(exam.TITLES), 16)
        self.assertEqual(sum(exam.WEIGHTS), 100)
        self.assertEqual(sum(exam.WEIGHTS[q - 1] for q in exam.LIVE) + 3, 47)

    def test_hardening_rejects_init_container_escape(self):
        s = spec(); self.assertTrue(exam.secure_containers(s, 30000))
        s['initContainers'] = [{'name': 'init', 'securityContext': {'privileged': True}}]
        self.assertFalse(exam.secure_containers(s, 30000))

    def test_pod_uid_inheritance_and_container_override(self):
        s = spec(); s['securityContext'] = {'runAsUser': 30000}
        del s['containers'][0]['securityContext']['runAsUser']
        self.assertTrue(exam.secure_containers(s, 30000))
        s['containers'][0]['securityContext']['runAsUser'] = 0
        self.assertFalse(exam.secure_containers(s, 30000))

    def test_restricted_requires_all_constraints(self):
        s = spec(65535); c = s['containers'][0]['securityContext']
        c.update(runAsNonRoot=True, capabilities={'drop': ['ALL']}, seccompProfile={'type': 'RuntimeDefault'})
        self.assertTrue(exam.secure_containers(s, restricted=True))
        for key in ('runAsNonRoot', 'capabilities', 'seccompProfile', 'allowPrivilegeEscalation'):
            bad = deepcopy(s); del bad['containers'][0]['securityContext'][key]
            self.assertFalse(exam.secure_containers(bad, restricted=True), key)

    def test_final_stage_nobody_is_not_comment_or_previous_stage(self):
        self.assertTrue(exam.check_build('FROM busybox\nUSER nobody\n', spec(65535)))
        for text in ('FROM busybox\n# USER nobody', 'FROM busybox\nUSER nobody\nUSER root', 'FROM busybox\nUSER nobody\nFROM busybox'):
            self.assertFalse(exam.check_build(text, spec(65535)))

    def test_running_root_mount_must_really_be_readonly(self):
        d = {'spec': {'template': {'spec': spec()}}}
        p = ready_pod()
        with patch.object(exam, 'running_deployment', return_value=d), patch.object(exam, 'pods', return_value=[p]), patch.object(exam, 'exec_text', side_effect=['30000', 'ro,relatime']):
            self.assertTrue(exam.check_hardened('x', 'ns', 30000))
        with patch.object(exam, 'running_deployment', return_value=d), patch.object(exam, 'pods', return_value=[p]), patch.object(exam, 'exec_text', side_effect=['30000', 'rw,relatime']):
            self.assertFalse(exam.check_hardened('x', 'ns', 30000))

    def test_network_needs_positive_and_both_negative_sources(self):
        policy = {'spec': {'podSelector': {}, 'policyTypes': ['Ingress']}}
        with patch.object(exam.core, 'get', return_value=policy), patch.object(exam, 'network_probe', side_effect=[True, False, False, True]):
            self.assertTrue(exam.check_network())
        for results in ([False], [True, True], [True, False, True], [True, False, False, False]):
            with patch.object(exam.core, 'get', return_value=policy), patch.object(exam, 'network_probe', side_effect=results):
                self.assertFalse(exam.check_network())

    def test_failed_exec_is_not_denied_network_traffic(self):
        with patch.object(exam.core, 'get', return_value=ready_pod()), patch.object(exam, 'pods', return_value=[ready_pod()]), patch.object(exam, 'exec_text', side_effect=exam.core.EvidenceError('unavailable')):
            with self.assertRaises(exam.core.EvidenceError):
                exam.network_probe('exam-denied')
        with patch.object(exam.core, 'get', return_value={}), patch.object(exam, 'pods', return_value=[]):
            with self.assertRaises(exam.core.EvidenceError):
                exam.network_probe('exam-denied')

    def test_tls_secret_without_original_mount_does_not_pass(self):
        d = {'spec': {'template': {'spec': {'containers': [{'name': 'app'}]}}}}
        with patch.object(exam.core, 'get', return_value={}), patch.object(exam.core, 'check_tls', return_value=True), patch.object(exam, 'running_deployment', return_value=d):
            self.assertFalse(exam.check_tls())

    def test_token_requires_readonly_mount_and_both_automount_settings(self):
        sa = {'automountServiceAccountToken': False}
        p = ready_pod(); p['spec'].update(serviceAccountName='app-sa', automountServiceAccountToken=False,
            volumes=[{'name': 'token', 'projected': {'sources': [{'serviceAccountToken': {'path': 'token', 'audience': 'cks-lab', 'expirationSeconds': 3600}}]}}])
        p['spec']['containers'][0]['volumeMounts'] = [{'name': 'token', 'mountPath': '/var/run/secrets/tokens', 'readOnly': True}]
        with patch.object(exam.core, 'get', side_effect=[sa, p]):
            self.assertTrue(exam.check_token())
        p['spec']['containers'][0]['volumeMounts'][0]['readOnly'] = False
        with patch.object(exam.core, 'get', side_effect=[sa, p]):
            self.assertFalse(exam.check_token())

    def test_spdx_package_investigation_rejects_filename_only(self):
        with self.assertRaises(ValueError): exam.package_names('{}')
        doc = {'spdxVersion': 'SPDX-2.3', 'SPDXID': 'SPDXRef-DOCUMENT', 'dataLicense': 'CC0-1.0', 'documentNamespace': 'https://example.test/doc', 'packages': [{'name': 'libcrypto3'}]}
        self.assertEqual(exam.package_names(json.dumps(doc)), {'libcrypto3'})

    def test_supply_requires_correct_analysis_both_reports_and_survivor(self):
        expected = {'removed': 'cobalt', 'candidates': {'amber': 'busybox:1.37', 'cobalt': 'alpine:3.19.1'}}
        with tempfile.TemporaryDirectory() as tmp, patch.object(exam, 'FILES', Path(tmp)):
            f = Path(tmp)
            (f / 'findings.json').write_text(json.dumps({'container': 'cobalt', 'image': 'alpine:3.19.1', 'package': 'libcrypto3'}))
            for name, package in [('amber', 'busybox'), ('cobalt', 'libcrypto3')]:
                (f / f'{name}.spdx').write_text(json.dumps({'spdxVersion': 'SPDX-2.3', 'SPDXID': 'SPDXRef-DOCUMENT', 'dataLicense': 'CC0-1.0', 'documentNamespace': 'https://example.test/' + name, 'packages': [{'name': package}]}))
            d = {'spec': {'template': {'spec': {'containers': [{'name': 'amber', 'image': 'busybox:1.37'}]}}}}
            with patch.object(exam, 'running_deployment', return_value=d): self.assertTrue(exam.check_supply(expected))
            with patch.object(exam, 'running_deployment', return_value=None): self.assertFalse(exam.check_supply(expected))
            (f / 'findings.json').write_text('{}')
            self.assertFalse(exam.check_supply(expected))

    def test_runtime_containment_must_preserve_other_services(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(exam, 'FILES', Path(tmp)):
            f = Path(tmp)
            (f / 'incident.json').write_text(json.dumps({'namespace': 'exam-runtime', 'pod': 'ledger-pod', 'deployment': 'ledger'}))
            (f / 'runtime-events.jsonl').write_text(json.dumps({'output_fields': {'fd.name': '/dev/mem', 'k8s.pod.name': 'ledger-pod'}}))
            def get(kind, name, ns):
                return {'spec': {'replicas': 0 if name == 'ledger' else 1}, 'status': {'replicas': 0 if name == 'ledger' else 1}}
            with patch.object(exam.core, 'get', side_effect=get), patch.object(exam, 'running_deployment', return_value={'healthy': True}):
                self.assertTrue(exam.check_runtime({'culprit': 'ledger'}))
            with patch.object(exam.core, 'get', side_effect=get), patch.object(exam, 'running_deployment', return_value=None):
                self.assertFalse(exam.check_runtime({'culprit': 'ledger'}))

    def test_perfect_automatic_results_cannot_claim_full_exam_score(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(exam, 'STATE', Path(tmp)):
            state = Path(tmp); (state / 'setup-complete').touch(); (state / 'exam-expected.json').write_text('{}')
            output = io.StringIO()
            with patch.object(exam, 'check_owner'), patch.object(exam, 'check_tls', return_value=True), patch.object(exam, 'check_hardened', return_value=True), patch.object(exam, 'check_build', return_value=True), patch.object(exam, 'check_runtime', return_value=True), patch.object(exam, 'check_network', return_value=True), patch.object(exam, 'check_token', return_value=True), patch.object(exam, 'check_supply', return_value=True), patch.object(exam.core, 'get', return_value={'spec': {'template': {'spec': {}}}, 'metadata': {'labels': {'pod-security.kubernetes.io/enforce': 'restricted'}}}), patch.object(Path, 'read_text', return_value='{}'), redirect_stdout(output):
                self.assertEqual(exam.score_exam(), 0)
            self.assertIn('47/100', output.getvalue())
            self.assertEqual(output.getvalue().count('MANUAL'), 8)

    def test_setup_has_intentionally_broken_workloads_and_working_network_baseline(self):
        with tempfile.TemporaryDirectory() as tmp:
            state, files = Path(tmp), Path(tmp) / 'exam'
            objects, commands = [], []
            runtime = {'items': [ready_pod(name + '-pod', 'exam-runtime', name) for name in ('orders', 'ledger', 'reporting')]}
            with patch.object(exam, 'STATE', state), patch.object(exam, 'FILES', files), patch.object(exam, 'check_owner'), patch.object(exam, 'apply', side_effect=objects.append), patch.object(exam.core, 'command', side_effect=lambda args, *a, **kw: commands.append(args) or ''), patch.object(exam.core, 'get', return_value=runtime), patch.object(exam, 'network_probe', return_value=True) as probe:
                exam.setup()
            deployments = {o['metadata']['name']: o for o in objects if o['kind'] == 'Deployment'}
            tls = deployments['certificate-reader']['spec']['template']['spec']
            self.assertEqual(tls['volumes'][0]['secret']['secretName'], 'site-tls')
            self.assertTrue(deployments['locked-app']['spec']['template']['spec']['containers'][0]['securityContext']['privileged'])
            self.assertEqual(probe.call_count, 3)
            self.assertEqual(len((files / 'runtime-events.jsonl').read_text().splitlines()), 3)
            self.assertEqual(len(json.loads((state / 'exam-expected.json').read_text())['candidates']), 2)
            self.assertFalse(any(o['kind'] == 'Secret' for o in objects))
            waits = [' '.join(a) for a in commands if 'wait' in a]
            self.assertFalse(any('-n exam-tls ' in a or '-n exam-restricted ' in a for a in waits))


class ExamLifecycleTests(unittest.TestCase):
    setUp = test_simulator.LifecycleTests.setUp
    run_lab = test_simulator.LifecycleTests.run_lab
    def test_exam_start_requests_two_nodes_and_no_timer_on_failed_baseline(self):
        import shutil
        (self.root / 'secon_version').mkdir()
        shutil.copy2(ROOT / 'secon_version' / 'exam_mode.py', self.root / 'secon_version' / 'exam_mode.py')
        result = self.run_lab('start', '--exam')
        self.assertNotEqual(result.returncode, 0)  # Fake cluster has no Ready probe endpoints.
        self.assertIn('--nodes=2', self.log.read_text())
        self.assertEqual((self.state / 'mode').read_text().strip(), 'exam')
        self.assertFalse((self.state / 'deadline').exists())

    def test_worker_ssh_rejects_non_lab_node(self):
        (self.state / 'cluster-uid').write_text('owned')
        self.assertNotEqual(self.run_lab('ssh', '--node', 'production').returncode, 0)
        self.assertNotIn('production', self.log.read_text())
        self.assertEqual(self.run_lab('ssh', '--node', 'cks-lab-m02', 'hostname').returncode, 0)
        self.assertIn('ssh --node=cks-lab-m02 -- hostname', self.log.read_text())


if __name__ == '__main__':
    unittest.main()
