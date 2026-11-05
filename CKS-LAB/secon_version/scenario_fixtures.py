"""Deliberately faulty *copies* of Minikube component configuration.

Only the kubeadm-style scalar/argument lines we explicitly recognize are
rewritten. Unknown or ambiguous source layouts fail closed, before upload.
No YAML package is required, and no live component file is ever written.
"""
import re


class FixtureError(ValueError):
    pass


def scalar(text, path, replacement=None):
    stack, matches = [], []
    lines = text.splitlines()
    for index, line in enumerate(lines):
        match = re.fullmatch(r'( *)([A-Za-z][A-Za-z0-9_]*):(?:[ \t]+([^#]*?))?[ \t]*(?:#.*)?', line)
        if not match:
            continue
        indent, key, value = match.groups()
        while stack and stack[-1][0] >= len(indent):
            stack.pop()
        current = tuple(item[1] for item in stack) + (key,)
        if current == tuple(path):
            matches.append((index, indent, key, (value or '').strip()))
        if not value or not value.strip():
            stack.append((len(indent), key))
    if len(matches) != 1:
        raise FixtureError('Unrecognized or ambiguous scalar: ' + '.'.join(path))
    index, indent, key, value = matches[0]
    if replacement is None:
        return value
    lines[index] = f'{indent}{key}: {replacement}'
    return '\n'.join(lines) + '\n'


def flag(text, name, replacement=None, binary=None):
    pattern = re.compile(r'^( *- +)--' + re.escape(name) + r'(?:=(.*))?$')
    lines = text.splitlines()
    matches = [(i, pattern.fullmatch(line)) for i, line in enumerate(lines) if pattern.fullmatch(line)]
    if len(matches) > 1:
        raise FixtureError('Duplicate component argument: ' + name)
    if not matches and re.search(r'--' + re.escape(name) + r'(?:[=\s\"\x27]|$)', text):
        raise FixtureError('Unrecognized component argument layout: ' + name)
    if replacement is None:
        return matches[0][1].group(2) if matches else None
    if matches:
        index, match = matches[0]
        lines[index] = f'{match.group(1)}--{name}={replacement}'
    else:
        anchors = [(i, re.fullmatch(r'( *- +)' + re.escape(binary or ''), line))
                   for i, line in enumerate(lines) if re.fullmatch(r'( *- +)' + re.escape(binary or ''), line)]
        if len(anchors) != 1:
            raise FixtureError('Cannot locate component command: ' + str(binary))
        index, match = anchors[0]
        lines.insert(index + 1, f'{match.group(1)}--{name}={replacement}')
    return '\n'.join(lines) + '\n'


def component_fixtures(kubelet, etcd, api):
    """Return five text fixtures, requiring every assigned repair to be wrong."""
    for path, value in [
        (('authentication', 'anonymous', 'enabled'), 'true'),
        (('authentication', 'webhook', 'enabled'), 'false'),
        (('authorization', 'mode'), 'AlwaysAllow'),
    ]:
        kubelet = scalar(kubelet, path, value)
    # Minikube uses the same etcd CA for client and peer connections. Keep the
    # correct peer setting as inspectable evidence for repairing client trust.
    ca = flag(etcd, 'trusted-ca-file')
    if not ca or not ca.startswith('/') or flag(etcd, 'peer-trusted-ca-file') != ca:
        raise FixtureError('Expected matching absolute client/peer etcd CA paths.')
    etcd = flag(etcd, 'client-cert-auth', 'false', 'etcd')
    etcd = flag(etcd, 'trusted-ca-file', '/opt/cks-lab/exam/incorrect-ca.crt', 'etcd')
    api = flag(api, 'anonymous-auth', 'true', 'kube-apiserver')
    api = flag(api, 'authorization-mode', 'AlwaysAllow', 'kube-apiserver')
    plugins = [p for p in (flag(api, 'enable-admission-plugins') or '').split(',')
               if p and p not in ('NodeRestriction', 'ImagePolicyWebhook')]
    api = flag(api, 'enable-admission-plugins', ','.join(plugins) or 'NamespaceLifecycle', 'kube-apiserver')
    disabled = set(filter(None, (flag(api, 'disable-admission-plugins') or '').split(',')))
    disabled.update(('NodeRestriction', 'ImagePolicyWebhook'))
    api = flag(api, 'disable-admission-plugins', ','.join(sorted(disabled)), 'kube-apiserver')
    for name, value in {
        'audit-policy-file': '/opt/cks-lab/audit/incorrect-policy.yaml',
        'audit-log-path': '/tmp/incorrect-audit.log',
        'audit-log-maxbackup': '0', 'audit-log-maxage': '0', 'audit-log-maxsize': '0',
        'admission-control-config-file': '/opt/cks-lab/image-config/incorrect-config.yaml',
    }.items():
        api = flag(api, name, value, 'kube-apiserver')
    # An audit-enabled custom source requires mount surgery we cannot safely
    # infer. Refuse it rather than hand the candidate a partly solved fixture.
    if re.search(r'mountPath:.*(?:/opt/cks-lab/audit|/var/log/k8s|/opt/cks-lab/image-config)', api):
        raise FixtureError('Source already contains task-specific mounts; use a standard lab profile.')
    audit = ('apiVersion: audit.k8s.io/v1\nkind: Policy\nrules:\n'
             '- level: RequestResponse\n  verbs: ["create"]\n  resources:\n'
             '  - group: ""\n    resources: ["pods", "secrets"]\n- level: None\n')
    admission = ('apiVersion: apiserver.config.k8s.io/v1\nkind: AdmissionConfiguration\nplugins:\n'
                 '- name: ImagePolicyWebhook\n  configuration:\n    imagePolicy:\n'
                 '      kubeConfigFile: /opt/cks-lab/image-config/webhook-kubeconfig.yaml\n'
                 '      defaultAllow: true\n')
    result = {'exam/kubelet-config.yaml': kubelet, 'exam/etcd.yaml': etcd,
              'exam/kube-apiserver.yaml': api, 'audit/audit-policy.yaml': audit,
              'image-config/admission-configuration.yaml': admission}
    verify_component_faults(result)
    return result


def verify_component_faults(fixtures):
    kubelet, etcd, api = (fixtures['exam/' + name] for name in
                          ('kubelet-config.yaml', 'etcd.yaml', 'kube-apiserver.yaml'))
    checks = {
        '01.anonymous-authentication': scalar(kubelet, ('authentication', 'anonymous', 'enabled')) == 'true',
        '01.webhook-authentication': scalar(kubelet, ('authentication', 'webhook', 'enabled')) == 'false',
        '01.webhook-authorization': scalar(kubelet, ('authorization', 'mode')) == 'AlwaysAllow',
        '01.etcd-client-certificate': flag(etcd, 'client-cert-auth') == 'false',
        '01.etcd-client-ca': flag(etcd, 'trusted-ca-file') != flag(etcd, 'peer-trusted-ca-file'),
        '06.audit-coverage': 'verbs: ["create"]' in fixtures['audit/audit-policy.yaml'] and fixtures['audit/audit-policy.yaml'].endswith('- level: None\n'),
        '06.secret-bodies': 'level: RequestResponse' in fixtures['audit/audit-policy.yaml'] and '"secrets"' in fixtures['audit/audit-policy.yaml'],
        '06.audit-mounts': not re.search(r'mountPath:.*(?:/opt/cks-lab/audit|/var/log/k8s)', api),
        '15.failure-policy': 'defaultAllow: true' in fixtures['image-config/admission-configuration.yaml'],
        '15.admission-config-path': flag(api, 'admission-control-config-file') != '/opt/cks-lab/image-config/admission-configuration.yaml',
        '15.plugin-disabled': 'ImagePolicyWebhook' in (flag(api, 'disable-admission-plugins') or '').split(','),
        '15.file-mounts': not re.search(r'mountPath:.*\/opt/cks-lab/image-config', api),
        '16.anonymous-authentication': flag(api, 'anonymous-auth') == 'true',
        '16.authorization': flag(api, 'authorization-mode') == 'AlwaysAllow',
        '16.node-restriction-disabled': 'NodeRestriction' in (flag(api, 'disable-admission-plugins') or '').split(','),
    }
    for name, value in {'audit-policy-file': '/opt/cks-lab/audit/audit-policy.yaml',
                        'audit-log-path': '/var/log/k8s/audit.log',
                        'audit-log-maxbackup': '2', 'audit-log-maxage': '7', 'audit-log-maxsize': '10'}.items():
        checks['06.' + name] = flag(api, name) != value
    for plugin, task in [('ImagePolicyWebhook', '15'), ('NodeRestriction', '16')]:
        checks[task + '.plugin-not-enabled'] = plugin not in (flag(api, 'enable-admission-plugins') or '').split(',')
    failed = [name for name, broken in checks.items() if not broken]
    if failed:
        raise FixtureError('Starting configuration already satisfies assigned repairs: ' + ', '.join(failed))
    return checks


def insecure_container(uid=0):
    return {'runAsUser': uid, 'readOnlyRootFilesystem': False,
            'privileged': True, 'allowPrivilegeEscalation': True}


def verify_workload_faults(objects):
    by_name = {(o['kind'], o['metadata']['namespace'], o['metadata']['name']): o
               for o in objects if 'namespace' in o.get('metadata', {})}
    checks = {}
    for task, ns, name in [('03', 'exam-build', 'build-app'), ('05', 'exam-immutable', 'immutable-app')]:
        c = by_name['Deployment', ns, name]['spec']['template']['spec']['containers'][0]
        sc = c['securityContext']
        for field, value in insecure_container().items():
            checks[f'{task}.{field}'] = sc.get(field) == value
    sa = by_name['ServiceAccount', 'exam-tokens', 'app-sa']
    pod = by_name['Pod', 'exam-tokens', 'token-client']['spec']
    checks['09.serviceaccount-automount'] = sa.get('automountServiceAccountToken') is True
    checks['09.pod-automount'] = pod.get('automountServiceAccountToken') is True
    token = pod['volumes'][0]['projected']['sources'][0]['serviceAccountToken']
    mount = pod['containers'][0]['volumeMounts'][0]
    for field, correct in [('path', 'token'), ('audience', 'cks-lab'), ('expirationSeconds', 3600)]:
        checks['09.' + field] = token.get(field) != correct
    checks['09.mount-path'] = mount.get('mountPath') != '/var/run/secrets/tokens'
    # Kubernetes omits false for this non-pointer API field when it serializes
    # the stored Pod. Absence still means the required true value is unfinished.
    checks['09.read-only-mount'] = mount.get('readOnly', False) is False
    restricted = by_name['Deployment', 'exam-restricted', 'locked-app']['spec']['template']['spec']
    psc, csc = restricted['securityContext'], restricted['containers'][0]['securityContext']
    checks.update({
        '12.non-root': psc.get('runAsNonRoot') is False,
        '12.uid': psc.get('runAsUser') == 0,
        '12.seccomp': psc.get('seccompProfile', {}).get('type') == 'Unconfined',
        '12.privileged': csc.get('privileged') is True,
        '12.escalation': csc.get('allowPrivilegeEscalation') is True,
        '12.capability-drop': 'ALL' not in csc.get('capabilities', {}).get('drop', []),
        '12.capability-add': 'SYS_ADMIN' in csc.get('capabilities', {}).get('add', []),
    })
    failed = [name for name, broken in checks.items() if not broken]
    if failed:
        raise FixtureError('Starting workload already satisfies assigned repairs: ' + ', '.join(failed))
    return checks
