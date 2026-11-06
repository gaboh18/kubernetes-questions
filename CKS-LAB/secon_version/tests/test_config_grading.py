"""Configuration grading and repeatable scoring without a cluster or writes."""
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
sys.path[:0] = [str(ROOT), str(ROOT / 'secon_version'), str(Path(__file__).resolve().parent)]
import exam_mode as exam
from config_grading import ConfigGrader, ConfigurationError, ConfigurationResult, API_SOURCE, ETCD_SOURCE, STAGED, parse_yaml
from scenario_fixtures import component_fixtures, flag, scalar
from test_scenario_fixtures import component_sources
from vendor import yaml


def files():
    sources = component_sources()
    result = {STAGED + name: text for name, text in component_fixtures(*sources).items()}
    result[ETCD_SOURCE], result[API_SOURCE] = sources[1:]
    result[STAGED + 'image-config/webhook-kubeconfig.yaml'] = 'apiVersion: v1\nkind: Config\nclusters: []\n'
    return result


def solve_one(documents):
    name = STAGED + 'exam/kubelet-config.yaml'
    for path, value in [(('authentication', 'anonymous', 'enabled'), 'false'),
                        (('authentication', 'webhook', 'enabled'), 'true'),
                        (('authorization', 'mode'), 'Webhook')]:
        documents[name] = scalar(documents[name], path, value)
    documents[STAGED + 'exam/etcd.yaml'] = documents[ETCD_SOURCE]


def update_api(documents, settings, enable=(), undisable=()):
    key = STAGED + 'exam/kube-apiserver.yaml'
    text = documents[key]
    for name, value in settings.items():
        text = flag(text, name, value, 'kube-apiserver')
    enabled = set(filter(None, (flag(text, 'enable-admission-plugins') or '').split(','))) | set(enable)
    disabled = set(filter(None, (flag(text, 'disable-admission-plugins') or '').split(','))) - set(undisable)
    text = flag(text, 'enable-admission-plugins', ','.join(sorted(enabled)), 'kube-apiserver')
    text = flag(text, 'disable-admission-plugins', ','.join(sorted(disabled)), 'kube-apiserver')
    documents[key] = text


def mount(documents, name, path, read_only):
    key = STAGED + 'exam/kube-apiserver.yaml'
    obj = parse_yaml(documents[key])
    obj['spec']['containers'][0]['volumeMounts'].append({'name': name, 'mountPath': path, 'readOnly': read_only})
    obj['spec']['volumes'].append({'name': name, 'hostPath': {'path': path, 'type': 'Directory' if read_only else 'DirectoryOrCreate'}})
    documents[key] = yaml.safe_dump(obj, sort_keys=False)


def solve_six(documents):
    documents[STAGED + 'audit/audit-policy.yaml'] = 'apiVersion: audit.k8s.io/v1\nkind: Policy\nrules:\n- level: Metadata\n'
    update_api(documents, {'audit-policy-file': STAGED + 'audit/audit-policy.yaml',
        'audit-log-path': '/var/log/k8s/audit.log', 'audit-log-maxbackup': '2',
        'audit-log-maxage': '7', 'audit-log-maxsize': '10'})
    mount(documents, 'audit-policy', STAGED + 'audit', True)
    mount(documents, 'audit-log', '/var/log/k8s', False)


def solve_fifteen(documents):
    key = STAGED + 'image-config/admission-configuration.yaml'
    documents[key] = documents[key].replace('defaultAllow: true', 'defaultAllow: false')
    update_api(documents, {'admission-control-config-file': key}, enable=('ImagePolicyWebhook',), undisable=('ImagePolicyWebhook',))
    mount(documents, 'admission', STAGED + 'image-config', True)


def solve_sixteen(documents):
    update_api(documents, {'anonymous-auth': 'false', 'authorization-mode': 'Node,RBAC'},
               enable=('NodeRestriction',), undisable=('NodeRestriction',))


class ConfigGradingTests(unittest.TestCase):
    def test_every_unmodified_configuration_task_fails(self):
        documents = files()
        grader = ConfigGrader(documents.__getitem__)
        for task in (1, 6, 15, 16):
            with self.subTest(task=task):
                self.assertFalse(grader.grade(task).passed)

    def test_task_one_passes_only_after_all_five_repairs(self):
        documents = files()
        solve_one(documents)
        self.assertTrue(ConfigGrader(documents.__getitem__).grade(1).passed)
        variants = [
            ('exam/kubelet-config.yaml', lambda s: scalar(s, ('authentication', 'anonymous', 'enabled'), 'true')),
            ('exam/kubelet-config.yaml', lambda s: scalar(s, ('authentication', 'webhook', 'enabled'), 'false')),
            ('exam/kubelet-config.yaml', lambda s: scalar(s, ('authorization', 'mode'), 'AlwaysAllow')),
            ('exam/etcd.yaml', lambda s: flag(s, 'client-cert-auth', 'false', 'etcd')),
            ('exam/etcd.yaml', lambda s: flag(s, 'trusted-ca-file', '/wrong/ca.crt', 'etcd')),
        ]
        for path, change in variants:
            modified = dict(documents)
            modified[STAGED + path] = change(modified[STAGED + path])
            with self.subTest(path=path):
                self.assertFalse(ConfigGrader(modified.__getitem__).grade(1).passed)

    def test_matching_but_forged_ca_and_broken_peer_tls_do_not_pass(self):
        documents = files(); solve_one(documents)
        key = STAGED + 'exam/etcd.yaml'
        for name in ('trusted-ca-file', 'peer-trusted-ca-file'):
            documents[key] = flag(documents[key], name, '/arbitrary/ca.crt', 'etcd')
        self.assertFalse(ConfigGrader(documents.__getitem__).grade(1).passed)
        documents = files(); solve_one(documents)
        documents[key] = flag(documents[key], 'peer-client-cert-auth', 'false', 'etcd')
        self.assertFalse(ConfigGrader(documents.__getitem__).grade(1).passed)

    def test_changed_etcd_data_or_key_path_is_rejected(self):
        for name in ('data-dir', 'key-file', 'cert-file'):
            documents = files(); solve_one(documents)
            key = STAGED + 'exam/etcd.yaml'
            documents[key] = flag(documents[key], name, '/wrong/path', 'etcd')
            with self.subTest(flag=name):
                self.assertFalse(ConfigGrader(documents.__getitem__).grade(1).passed)

    def test_yaml_parser_accepts_flow_style_and_comments_but_not_string_booleans(self):
        documents = files(); solve_one(documents)
        key = STAGED + 'exam/kubelet-config.yaml'
        documents[key] = '''apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
authentication: {anonymous: {enabled: false}, webhook: {enabled: true}}
authorization: {mode: Webhook} # corrected
'''
        self.assertTrue(ConfigGrader(documents.__getitem__).grade(1).passed)
        documents[key] = documents[key].replace('enabled: false', 'enabled: "false"')
        self.assertFalse(ConfigGrader(documents.__getitem__).grade(1).passed)

    def test_invalid_yaml_duplicate_keys_and_duplicate_flags_are_errors(self):
        for text in ('authentication: [', 'enabled: false\nenabled: true\n', '!!python/object:example {}'):
            with self.subTest(text=text), self.assertRaises(ConfigurationError):
                parse_yaml(text)
        documents = files(); solve_one(documents)
        key = STAGED + 'exam/etcd.yaml'
        documents[key] = documents[key].replace('    - --client-cert-auth=true', '    - --client-cert-auth=true\n    - --client-cert-auth=false')
        with self.assertRaisesRegex(ConfigurationError, 'duplicate component argument'):
            ConfigGrader(documents.__getitem__).grade(1)

    def test_all_three_api_configuration_tasks_can_be_completed_in_one_manifest(self):
        documents = files()
        for solve in (solve_six, solve_fifteen, solve_sixteen):
            solve(documents)
        grader = ConfigGrader(documents.__getitem__)
        for task in (6, 15, 16):
            with self.subTest(task=task):
                self.assertTrue(grader.grade(task).passed, grader.grade(task).checks)

    def test_audit_policy_must_cover_all_requests_without_bodies(self):
        for rules in ('- level: RequestResponse\n', '- level: Metadata\n  verbs: ["get"]\n', '- level: None\n- level: Metadata\n'):
            documents = files(); solve_six(documents)
            documents[STAGED + 'audit/audit-policy.yaml'] = 'apiVersion: audit.k8s.io/v1\nkind: Policy\nrules:\n' + rules
            with self.subTest(rules=rules):
                self.assertFalse(ConfigGrader(documents.__getitem__).grade(6).passed)

    def test_mount_flag_or_hostpath_errors_do_not_pass(self):
        for field in ('mountPath', 'readOnly', 'hostPath'):
            documents = files(); solve_six(documents)
            key = STAGED + 'exam/kube-apiserver.yaml'
            obj = parse_yaml(documents[key])
            if field == 'hostPath':
                obj['spec']['volumes'][-1]['hostPath']['path'] = '/wrong/logs'
            else:
                obj['spec']['containers'][0]['volumeMounts'][-1][field] = '/wrong/logs' if field == 'mountPath' else True
            documents[key] = yaml.safe_dump(obj, sort_keys=False)
            with self.subTest(field=field):
                self.assertFalse(ConfigGrader(documents.__getitem__).grade(6).passed)

    def test_original_component_prerequisites_cannot_be_deleted_to_pass(self):
        documents = files(); solve_six(documents)
        key = STAGED + 'exam/kube-apiserver.yaml'
        obj = parse_yaml(documents[key])
        obj['spec']['volumes'] = [v for v in obj['spec']['volumes'] if v['name'] != 'certificates']
        documents[key] = yaml.safe_dump(obj, sort_keys=False)
        self.assertFalse(ConfigGrader(documents.__getitem__).grade(6).passed)

    def test_fail_open_or_explicitly_disabled_plugin_never_passes(self):
        for task, solve, plugin in ((15, solve_fifteen, 'ImagePolicyWebhook'), (16, solve_sixteen, 'NodeRestriction')):
            documents = files(); solve(documents)
            update_api(documents, {'disable-admission-plugins': plugin})
            with self.subTest(task=task):
                self.assertFalse(ConfigGrader(documents.__getitem__).grade(task).passed)
        documents = files(); solve_fifteen(documents)
        key = STAGED + 'image-config/admission-configuration.yaml'
        documents[key] = documents[key].replace('defaultAllow: false', 'defaultAllow: true')
        self.assertFalse(ConfigGrader(documents.__getitem__).grade(15).passed)

    def test_new_grader_rereads_a_new_answer_instead_of_reusing_old_results(self):
        documents = files()
        self.assertFalse(ConfigGrader(documents.__getitem__).grade(1).passed)
        solve_one(documents)
        self.assertTrue(ConfigGrader(documents.__getitem__).grade(1).passed)


class ScoreOutputTests(unittest.TestCase):
    def score(self, documents):
        with tempfile.TemporaryDirectory() as folder, patch.object(exam, 'STATE', Path(folder)):
            (Path(folder) / 'setup-complete').touch()
            (Path(folder) / 'exam-expected.json').write_text('{}')
            def read(args, *a, **kw):
                self.assertEqual(args[:4], ['minikube', '-p', 'cks-lab', 'ssh'])
                path = args[-1].removeprefix('sudo cat ')
                return documents[path]
            output = io.StringIO()
            with patch.object(exam, 'check_owner'), patch.object(exam.core, 'command', side_effect=read), redirect_stdout(output):
                status = exam.score_exam(1)
            return status, output.getvalue()

    def test_selected_task_shows_each_failure_and_then_a_seven_point_pass(self):
        documents = files()
        status, output = self.score(documents)
        self.assertEqual(status, 0)
        self.assertIn('FAIL CONFIG', output)
        self.assertIn('Task 01 practice points: 0/7', output)
        self.assertIn('FAIL  Kubelet anonymous authentication', output)
        self.assertNotIn('02.', output)
        solve_one(documents)
        status, output = self.score(documents)
        self.assertEqual(status, 0)
        self.assertIn('PASS CONFIG', output)
        self.assertIn('Task 01 practice points: 7/7', output)
        self.assertIn('do not verify live component behavior', output)

    def test_invalid_yaml_is_an_error_not_an_incorrect_answer(self):
        documents = files()
        documents[STAGED + 'exam/kubelet-config.yaml'] = '['
        status, output = self.score(documents)
        self.assertEqual(status, 1)
        self.assertIn('ERROR (no credit)', output)
        self.assertNotIn('PASS CONFIG', output)


if __name__ == '__main__':
    unittest.main()
