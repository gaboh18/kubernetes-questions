"""Read-only grading of the four component-copy exercises.

These checks validate complete YAML objects and their required settings. They
do not activate configuration or claim that a live component enforces a copy.
"""
from dataclasses import dataclass
from pathlib import PurePosixPath
import posixpath

from vendor import yaml

STAGED = '/opt/cks-lab/'
API_SOURCE = '/etc/kubernetes/manifests/kube-apiserver.yaml'
ETCD_SOURCE = '/etc/kubernetes/manifests/etcd.yaml'
CONFIG_TASKS = {1, 6, 15, 16}
API_TASK_FLAGS = {
    'anonymous-auth', 'authorization-mode', 'enable-admission-plugins',
    'disable-admission-plugins', 'admission-control-config-file', 'runtime-config',
    'audit-policy-file', 'audit-log-path', 'audit-log-maxbackup',
    'audit-log-maxage', 'audit-log-maxsize',
}


class ConfigurationError(ValueError):
    pass


class StrictLoader(yaml.SafeLoader):
    def construct_mapping(self, node, deep=False):
        self.flatten_mapping(node)
        keys = set()
        for key_node, _ in node.value:
            key = self.construct_object(key_node, deep=deep)
            try:
                if key in keys:
                    raise ConfigurationError('duplicate YAML mapping key')
                keys.add(key)
            except TypeError as error:
                raise ConfigurationError('unsupported YAML mapping key') from error
        return super().construct_mapping(node, deep=deep)


def parse_yaml(text):
    if len(text) > 1024 * 1024:
        raise ConfigurationError('configuration exceeds the supported size')
    try:
        result = yaml.load(text, Loader=StrictLoader)
    except (yaml.YAMLError, RecursionError) as error:
        # Parser diagnostics may echo input; report no configuration contents.
        raise ConfigurationError('invalid YAML syntax or unsupported YAML structure') from error
    if not isinstance(result, dict):
        raise ConfigurationError('expected one YAML mapping document')
    return result


@dataclass
class ConfigurationResult:
    checks: list

    @property
    def passed(self):
        return bool(self.checks) and all(passed for _, passed in self.checks)


def container_and_flags(document, name):
    if document.get('kind') != 'Pod' or document.get('apiVersion') != 'v1':
        raise ConfigurationError('expected a v1 Pod manifest')
    containers = document.get('spec', {}).get('containers', [])
    matches = [c for c in containers if isinstance(c, dict) and c.get('name') == name]
    if len(matches) != 1:
        raise ConfigurationError('expected one ' + name + ' container')
    container = matches[0]
    command, args = container.get('command', []), container.get('args', [])
    if not isinstance(command, list) or not isinstance(args, list) or not command:
        raise ConfigurationError('expected a component command list')
    if not all(isinstance(arg, str) for arg in command + args) or PurePosixPath(command[0]).name != name:
        raise ConfigurationError('unexpected component executable or argument type')
    tokens, flags, index = command[1:] + args, {}, 0
    while index < len(tokens):
        token = tokens[index]
        if not token.startswith('--'):
            raise ConfigurationError('unexpected positional component argument')
        key, separator, value = token[2:].partition('=')
        if key in flags:
            raise ConfigurationError('duplicate component argument: ' + key)
        if not separator:
            if index + 1 < len(tokens) and not tokens[index + 1].startswith('--'):
                index += 1
                value = tokens[index]
            else:
                value = 'true'
        flags[key] = value
        index += 1
    return container, flags


def original_settings_preserved(document, original, name, allowed):
    container, flags = container_and_flags(document, name)
    source, source_flags = container_and_flags(original, name)
    if any(flags.get(key) != value for key, value in source_flags.items() if key not in allowed):
        return False
    # Keep original image, probes, security settings, component volume mounts,
    # host paths and Pod settings. New task-specific mounts/volumes are allowed.
    for key, value in source.items():
        if key not in ('command', 'args', 'volumeMounts') and container.get(key) != value:
            return False
    if any(m not in container.get('volumeMounts', []) for m in source.get('volumeMounts', [])):
        return False
    spec, original_spec = document['spec'], original['spec']
    if any(v not in spec.get('volumes', []) for v in original_spec.get('volumes', [])):
        return False
    return all(spec.get(key) == value for key, value in original_spec.items() if key not in ('containers', 'volumes')) and len(spec['containers']) == len(original_spec['containers'])


def field(document, *path):
    for key in path:
        if not isinstance(document, dict):
            return None
        document = document.get(key)
    return document


def plugins(flags, key):
    return {p.strip() for p in flags.get(key, '').split(',') if p.strip()}


def mounted(document, container, target, host_target, read_only):
    volumes = {v.get('name'): v for v in document['spec'].get('volumes', []) if isinstance(v, dict)}
    for mount in container.get('volumeMounts', []):
        if not isinstance(mount, dict) or mount.get('readOnly', False) is not read_only:
            continue
        destination = mount.get('mountPath', '')
        volume = volumes.get(mount.get('name'), {})
        host = volume.get('hostPath', {})
        if not isinstance(destination, str) or not destination.startswith('/') or not isinstance(host, dict):
            continue
        host_path = host.get('path', '')
        if not isinstance(host_path, str) or not host_path.startswith('/'):
            continue
        if target != destination and not target.startswith(destination.rstrip('/') + '/'):
            continue
        suffix = target[len(destination):].lstrip('/')
        subpath = mount.get('subPath', '')
        if not isinstance(subpath, str) or subpath.startswith('/') or mount.get('subPathExpr'):
            continue
        actual = posixpath.normpath(posixpath.join(host_path, subpath, suffix))
        if actual == host_target:
            return True
    return False


class ConfigGrader:
    """Cache only within one invocation; every score command rereads node files."""
    def __init__(self, read_file):
        self.read_file = read_file
        self.documents = {}

    def document(self, path):
        if path not in self.documents:
            try:
                self.documents[path] = parse_yaml(self.read_file(path))
            except ConfigurationError as error:
                raise ConfigurationError(path + ': ' + str(error)) from error
        return self.documents[path]

    def grade(self, task):
        if task == 1:
            return self.task_one()
        api = self.document(STAGED + 'exam/kube-apiserver.yaml')
        source = self.document(API_SOURCE)
        container, flags = container_and_flags(api, 'kube-apiserver')
        source_flags = container_and_flags(source, 'kube-apiserver')[1]
        preserved = original_settings_preserved(api, source, 'kube-apiserver', API_TASK_FLAGS)
        if task == 6:
            policy = self.document(STAGED + 'audit/audit-policy.yaml')
            rules = policy.get('rules', [])
            unrestricted = lambda r: not any(r.get(k) for k in ('users', 'userGroups', 'verbs', 'resources', 'namespaces', 'nonResourceURLs'))
            policy_ok = (policy.get('apiVersion') == 'audit.k8s.io/v1' and policy.get('kind') == 'Policy'
                         and isinstance(rules, list) and bool(rules) and all(isinstance(r, dict) and r.get('level') == 'Metadata' for r in rules)
                         and any(unrestricted(r) for r in rules)
                         and not set(policy.get('omitStages', [])).issuperset({'RequestReceived', 'ResponseStarted', 'ResponseComplete', 'Panic'}))
            checks = [('Metadata coverage for every request; no request/response bodies', policy_ok),
                      ('Audit policy flag points to the supplied policy', flags.get('audit-policy-file') == STAGED + 'audit/audit-policy.yaml'),
                      ('Audit log path is /var/log/k8s/audit.log', flags.get('audit-log-path') == '/var/log/k8s/audit.log')]
            checks += [(label, flags.get(key) == value) for label, key, value in (
                ('Maximum backup files: 2', 'audit-log-maxbackup', '2'),
                ('Maximum age: 7 days', 'audit-log-maxage', '7'),
                ('Maximum size: 10 MiB', 'audit-log-maxsize', '10'))]
            checks.append(('Read-only policy mount and writable log mount map to the correct host paths',
                           mounted(api, container, STAGED + 'audit/audit-policy.yaml', STAGED + 'audit/audit-policy.yaml', True)
                           and mounted(api, container, '/var/log/k8s/audit.log', '/var/log/k8s/audit.log', False)))
        elif task == 15:
            admission = self.document(STAGED + 'image-config/admission-configuration.yaml')
            entries = admission.get('plugins', [])
            matches = [p for p in entries if isinstance(p, dict) and p.get('name') == 'ImagePolicyWebhook'] if isinstance(entries, list) else []
            image_policy = field(matches[0], 'configuration', 'imagePolicy') if len(matches) == 1 else None
            valid = admission.get('apiVersion') == 'apiserver.config.k8s.io/v1' and admission.get('kind') == 'AdmissionConfiguration'
            config_path, backend_path = STAGED + 'image-config/admission-configuration.yaml', STAGED + 'image-config/webhook-kubeconfig.yaml'
            backend = self.document(backend_path)
            backend_valid = backend.get('kind') == 'Config' and backend.get('apiVersion') == 'v1'
            checks = [('ImagePolicyWebhook is enabled', 'ImagePolicyWebhook' in plugins(flags, 'enable-admission-plugins')),
                      ('ImagePolicyWebhook is not explicitly disabled', 'ImagePolicyWebhook' not in plugins(flags, 'disable-admission-plugins')),
                      ('Valid admission configuration has defaultAllow: false', valid and field(image_policy, 'defaultAllow') is False),
                      ('Admission configuration flag points to the supplied file', flags.get('admission-control-config-file') == config_path),
                      ('Admission configuration is mounted read-only', mounted(api, container, config_path, config_path, True)),
                      ('Referenced webhook kubeconfig exists and is mounted read-only', backend_valid and field(image_policy, 'kubeConfigFile') == backend_path and mounted(api, container, backend_path, backend_path, True))]
        elif task == 16:
            original_plugins = plugins(source_flags, 'enable-admission-plugins') - {'NodeRestriction', 'ImagePolicyWebhook'}
            checks = [('Anonymous API authentication is disabled', flags.get('anonymous-auth') == 'false'),
                      ('Authorization modes are Node,RBAC', flags.get('authorization-mode') == 'Node,RBAC'),
                      ('NodeRestriction is enabled', 'NodeRestriction' in plugins(flags, 'enable-admission-plugins')),
                      ('NodeRestriction is not explicitly disabled', 'NodeRestriction' not in plugins(flags, 'disable-admission-plugins')),
                      ('Other existing admission plugins are preserved', original_plugins.issubset(plugins(flags, 'enable-admission-plugins')))]
        else:
            raise ConfigurationError('unsupported configuration task')
        checks.append(('Original API server settings, certificates and mounts are preserved', preserved))
        return ConfigurationResult(checks)

    def task_one(self):
        kubelet = self.document(STAGED + 'exam/kubelet-config.yaml')
        etcd = self.document(STAGED + 'exam/etcd.yaml')
        original = self.document(ETCD_SOURCE)
        _, flags = container_and_flags(etcd, 'etcd')
        _, source = container_and_flags(original, 'etcd')
        valid_kubelet = kubelet.get('kind') == 'KubeletConfiguration' and kubelet.get('apiVersion') == 'kubelet.config.k8s.io/v1beta1'
        peers = {key: value for key, value in source.items() if key.startswith('peer-')}
        preserved = original_settings_preserved(etcd, original, 'etcd', {'client-cert-auth', 'trusted-ca-file', *peers})
        checks = [('Kubelet anonymous authentication is disabled', valid_kubelet and field(kubelet, 'authentication', 'anonymous', 'enabled') is False),
                  ('Kubelet webhook authentication is enabled', valid_kubelet and field(kubelet, 'authentication', 'webhook', 'enabled') is True),
                  ('Kubelet authorization is Webhook', valid_kubelet and field(kubelet, 'authorization', 'mode') == 'Webhook'),
                  ('etcd requires client certificates', flags.get('client-cert-auth') == 'true'),
                  ('etcd client trust uses the original CA', bool(source.get('trusted-ca-file')) and flags.get('trusted-ca-file') == source['trusted-ca-file']),
                  ('Existing etcd peer TLS settings are preserved', bool(peers) and all(flags.get(key) == value for key, value in peers.items())),
                  ('Existing etcd certificate/key, data paths and mounts are preserved', preserved)]
        return ConfigurationResult(checks)
