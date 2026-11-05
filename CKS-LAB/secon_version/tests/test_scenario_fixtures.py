"""Regression checks for unsolved starting states; no real cluster changes."""
from copy import deepcopy
import base64
import json
from pathlib import Path
import shlex
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT), str(ROOT / 'secon_version')]
import exam_mode as exam
import scenario_fixtures as fixtures


def component_sources():
    kubelet = '''apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: /var/lib/minikube/certs/ca.crt
authorization:
  mode: Webhook
  webhook:
    cacheAuthorizedTTL: 5m0s
readOnlyPort: 0
'''
    etcd = '''apiVersion: v1
kind: Pod
spec:
  containers:
  - command:
    - etcd
    - --client-cert-auth=true
    - --trusted-ca-file=/var/lib/minikube/certs/etcd/ca.crt
    - --peer-trusted-ca-file=/var/lib/minikube/certs/etcd/ca.crt
    - --peer-client-cert-auth=true
    - --cert-file=/var/lib/minikube/certs/etcd/server.crt
    - --key-file=/var/lib/minikube/certs/etcd/server.key
    - --data-dir=/var/lib/minikube/etcd
    name: etcd
'''
    api = '''apiVersion: v1
kind: Pod
spec:
  containers:
  - command:
    - kube-apiserver
    - --anonymous-auth=false
    - --authorization-mode=Node,RBAC
    - --enable-admission-plugins=NodeRestriction,AlwaysPullImages
    - --disable-admission-plugins=EventRateLimit
    - --secure-port=8443
    name: kube-apiserver
    volumeMounts:
    - name: certificates
      mountPath: /var/lib/minikube/certs
      readOnly: true
  volumes:
  - name: certificates
    hostPath:
      path: /var/lib/minikube/certs
'''
    return kubelet, etcd, api


def workload_sources():
    objects = []
    for name, ns in [('build-app', 'exam-build'), ('immutable-app', 'exam-immutable')]:
        objects.append(exam.deployment(name, ns, [{'name': 'app', 'image': 'busybox:1.37',
            'command': ['sleep', '86400'], 'securityContext': fixtures.insecure_container()}]))
    objects.append({'apiVersion': 'v1', 'kind': 'ServiceAccount', 'metadata': {'name': 'app-sa', 'namespace': 'exam-tokens'}, 'automountServiceAccountToken': True})
    objects.append({'apiVersion': 'v1', 'kind': 'Pod', 'metadata': {'name': 'token-client', 'namespace': 'exam-tokens'},
        'spec': {'serviceAccountName': 'app-sa', 'automountServiceAccountToken': True,
            'containers': [{'name': 'app', 'volumeMounts': [{'name': 'legacy-token', 'mountPath': '/var/run/secrets/legacy', 'readOnly': False}]}],
            'volumes': [{'name': 'legacy-token', 'projected': {'sources': [{'serviceAccountToken': {'path': 'old-token', 'audience': 'legacy-api', 'expirationSeconds': 600}}]}}]}})
    objects.append(exam.deployment('locked-app', 'exam-restricted', spec={
        'securityContext': {'runAsUser': 0, 'runAsNonRoot': False, 'seccompProfile': {'type': 'Unconfined'}},
        'containers': [{'name': 'app', 'securityContext': {'privileged': True, 'allowPrivilegeEscalation': True, 'capabilities': {'add': ['SYS_ADMIN']}}}]}))
    return objects


class ComponentFixtureTests(unittest.TestCase):
    def test_all_five_task_one_repairs_start_wrong(self):
        result = fixtures.component_fixtures(*component_sources())
        checks = fixtures.verify_component_faults(result)
        self.assertEqual(len([name for name in checks if name.startswith('01.')]), 5)
        self.assertTrue(all(checks.values()))

    def test_task_six_has_incomplete_coverage_secret_bodies_wrong_retention_and_missing_mounts(self):
        result = fixtures.component_fixtures(*component_sources())
        policy = result['audit/audit-policy.yaml']
        self.assertIn('level: RequestResponse', policy)
        self.assertIn('"secrets"', policy)
        self.assertTrue(policy.endswith('- level: None\n'))
        api = result['exam/kube-apiserver.yaml']
        for name in ('audit-log-maxbackup', 'audit-log-maxage', 'audit-log-maxsize'):
            self.assertEqual(fixtures.flag(api, name), '0')
        self.assertNotIn('mountPath: /var/log/k8s', api)

    def test_plugins_are_actually_disabled_and_unrelated_settings_preserved(self):
        source = component_sources()
        result = fixtures.component_fixtures(*source)
        api = result['exam/kube-apiserver.yaml']
        self.assertEqual(fixtures.flag(api, 'enable-admission-plugins'), 'AlwaysPullImages')
        self.assertEqual(set(fixtures.flag(api, 'disable-admission-plugins').split(',')), {'EventRateLimit', 'ImagePolicyWebhook', 'NodeRestriction'})
        self.assertEqual(fixtures.flag(api, 'secure-port'), '8443')
        self.assertIn('mountPath: /var/lib/minikube/certs', api)
        self.assertIn('clientCAFile: /var/lib/minikube/certs/ca.crt', result['exam/kubelet-config.yaml'])
        for name in ('peer-trusted-ca-file', 'peer-client-cert-auth', 'cert-file', 'key-file', 'data-dir'):
            self.assertEqual(fixtures.flag(source[1], name), fixtures.flag(result['exam/etcd.yaml'], name))

    def test_duplicate_scalar_or_command_is_rejected(self):
        kubelet, etcd, api = component_sources()
        with self.assertRaises(fixtures.FixtureError):
            fixtures.component_fixtures(kubelet.replace('    enabled: false', '    enabled: false\n    enabled: true'), etcd, api)
        with self.assertRaises(fixtures.FixtureError):
            fixtures.component_fixtures(kubelet, etcd, api.replace('    - --anonymous-auth=false', '    - --anonymous-auth=false\n    - --anonymous-auth=true'))

    def test_unknown_layout_or_ca_relationship_fails_closed(self):
        kubelet, etcd, api = component_sources()
        for bad_kubelet, bad_etcd, bad_api in [
            (kubelet.replace('  anonymous:\n    enabled: false', '  anonymous: {enabled: false}'), etcd, api),
            (kubelet, etcd.replace('--peer-trusted-ca-file=/var/lib/minikube/certs/etcd/ca.crt', '--peer-trusted-ca-file=/other/ca.crt'), api),
            (kubelet, etcd, api.replace('- --authorization-mode=Node,RBAC', '- "--authorization-mode=Node,RBAC"')),
        ]:
            with self.subTest(source=bad_kubelet[:20]), self.assertRaises(fixtures.FixtureError):
                fixtures.component_fixtures(bad_kubelet, bad_etcd, bad_api)

    def test_a_single_pre_solved_field_fails_the_audit(self):
        result = fixtures.component_fixtures(*component_sources())
        result['exam/kubelet-config.yaml'] = fixtures.scalar(result['exam/kubelet-config.yaml'], ('authentication', 'anonymous', 'enabled'), 'false')
        with self.assertRaisesRegex(fixtures.FixtureError, '01.anonymous-authentication'):
            fixtures.verify_component_faults(result)

    def test_upload_round_trip_writes_only_staging_paths(self):
        sources = dict(zip(('/var/lib/kubelet/config.yaml', '/etc/kubernetes/manifests/etcd.yaml', '/etc/kubernetes/manifests/kube-apiserver.yaml'), component_sources()))
        writes, calls = {}, []
        def command(args, *a, **kw):
            self.assertEqual(args[:4], ['minikube', '-p', 'cks-lab', 'ssh'])
            remote = args[-1]; calls.append(remote)
            if remote.startswith('sudo cat '):
                return sources[remote.removeprefix('sudo cat ')]
            if remote.startswith('cat '):
                return writes[remote.removeprefix('cat ')].replace('\n', '\r\n')
            for entry in remote.split('; '):
                if entry.startswith('printf %s '):
                    tokens = shlex.split(entry)
                    target = tokens[-1]
                    self.assertTrue(target.startswith(('/opt/cks-lab/exam/', '/opt/cks-lab/audit/', '/opt/cks-lab/image-config/')))
                    writes[target] = base64.b64decode(tokens[2]).decode()
            return ''
        with patch.object(exam.core, 'command', side_effect=command):
            self.assertTrue(all(exam.prepare_component_fixtures().values()))
        self.assertEqual(len(writes), 5)
        self.assertFalse(any('/etc/kubernetes/manifests' in key for key in writes))

    def test_failed_round_trip_aborts_initialization(self):
        sources = iter(component_sources())
        def command(args, *a, **kw):
            if args[-1].startswith('sudo cat '):
                return next(sources)
            return ''
        with patch.object(exam.core, 'command', side_effect=command), self.assertRaisesRegex(exam.core.EvidenceError, 'verification failed'):
            exam.prepare_component_fixtures()


class WorkloadFixtureTests(unittest.TestCase):
    def test_every_hardening_token_and_restricted_repair_starts_wrong(self):
        checks = fixtures.verify_workload_faults(workload_sources())
        self.assertEqual(len(checks), 22)
        self.assertTrue(all(checks.values()))

    def test_a_single_pre_solved_workload_field_fails_the_audit(self):
        for field, value in [('runAsUser', 65535), ('readOnlyRootFilesystem', True), ('privileged', False), ('allowPrivilegeEscalation', False)]:
            objects = workload_sources()
            objects[0]['spec']['template']['spec']['containers'][0]['securityContext'][field] = value
            with self.subTest(field=field), self.assertRaisesRegex(fixtures.FixtureError, field):
                fixtures.verify_workload_faults(objects)

    def test_api_omitted_false_mount_value_is_still_an_unfinished_repair(self):
        objects = workload_sources()
        del objects[3]['spec']['containers'][0]['volumeMounts'][0]['readOnly']
        self.assertTrue(all(fixtures.verify_workload_faults(objects).values()))
        objects[3]['spec']['containers'][0]['volumeMounts'][0]['readOnly'] = True
        with self.assertRaisesRegex(fixtures.FixtureError, '09.read-only-mount'):
            fixtures.verify_workload_faults(objects)

    def test_correct_projection_or_namespace_privilege_is_not_preinstalled(self):
        objects = workload_sources()
        objects[3]['spec']['automountServiceAccountToken'] = False
        with self.assertRaisesRegex(fixtures.FixtureError, '09.pod-automount'):
            fixtures.verify_workload_faults(objects)
        objects = workload_sources()
        objects[4]['spec']['template']['spec']['securityContext']['seccompProfile']['type'] = 'RuntimeDefault'
        with self.assertRaisesRegex(fixtures.FixtureError, '12.seccomp'):
            fixtures.verify_workload_faults(objects)

    def test_starting_state_is_read_from_the_cluster_not_just_templates(self):
        objects = workload_sources()
        by_key = {(o['kind'], o['metadata']['namespace'], o['metadata']['name']): o for o in objects}
        kind_names = {'deployment': 'Deployment', 'serviceaccount': 'ServiceAccount', 'pod': 'Pod'}
        def get(kind, name=None, namespace=None):
            if kind in ('secrets', 'networkpolicies'):
                return {'items': []}
            if name == 'inventory':
                return exam.deployment('inventory', 'exam-supply', [{'name': 'amber'}, {'name': 'cobalt'}])
            if namespace == 'exam-runtime':
                return {'spec': {'replicas': 1}}
            return by_key[kind_names[kind], namespace, name]
        with tempfile.TemporaryDirectory() as folder, patch.object(exam, 'FILES', Path(folder)), patch.object(exam.core, 'get', side_effect=get):
            (Path(folder) / 'Dockerfile').write_text('FROM busybox:1.37\nUSER root\n')
            (Path(folder) / 'falco_rules.local.yaml').write_text('# Add a rule\n')
            self.assertTrue(all(exam.verify_starting_workloads().values()))
            objects[0]['spec']['template']['spec']['containers'][0]['securityContext']['privileged'] = False
            with self.assertRaises(fixtures.FixtureError):
                exam.verify_starting_workloads()


if __name__ == '__main__':
    unittest.main()
