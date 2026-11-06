#!/usr/bin/env python3
"""A 16-task practice mock. Live, replay, and external tasks are explicit."""
import base64
import json
from pathlib import Path
import secrets
import shlex
import subprocess
import sys

# Shared runtime stays in the original simulator directory.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import score as core
from config_grading import ConfigGrader, ConfigurationError, CONFIG_TASKS
from scenario_fixtures import component_fixtures, insecure_container, verify_component_faults, verify_workload_faults

ROOT, STATE = core.ROOT, core.STATE
FILES = core.JUMPBOX / 'exam'
K = core.KUBECTL
WEIGHTS = [7, 5, 7, 7, 6, 7, 7, 6, 6, 7, 7, 6, 5, 6, 6, 5]
LIVE = {2, 3, 5, 7, 9, 11, 12}
TITLES = [
    'Kubelet and etcd hardening', 'Restore workload with TLS Secret',
    'Dockerfile and Deployment security', 'Runtime investigation and Falco rule',
    'Immutable workload', 'Audit policy and retention', 'Namespace ingress isolation',
    'HTTPS Ingress', 'Explicit ServiceAccount token', 'Worker patch upgrade',
    'SBOM package investigation', 'Repair a Restricted workload', 'Docker daemon access',
    'Cilium mutual authentication', 'Fail-closed image admission', 'API authentication and authorization',
]


def apply(obj):
    core.command(K + ['apply', '-f', '-'], json.dumps(obj))


def deployment(name, namespace, containers=None, spec=None):
    return {'apiVersion': 'apps/v1', 'kind': 'Deployment',
            'metadata': {'name': name, 'namespace': namespace},
            'spec': {'replicas': 1, 'selector': {'matchLabels': {'app': name}},
                     'template': {'metadata': {'labels': {'app': name}}, 'spec': spec or {
                         'containers': containers or [{'name': 'app', 'image': 'busybox:1.37', 'command': ['sleep', '86400']}]}}}}


def check_owner():
    uid = (STATE / 'cluster-uid').read_text().strip()
    if not uid or core.get('namespace', 'kube-system').get('metadata', {}).get('uid') != uid:
        raise core.EvidenceError('cluster ownership mismatch')


def prepare_component_fixtures():
    sources = [core.command(core.PREFIX + ['ssh', '--', 'sudo cat ' + path]) for path in (
        '/var/lib/kubelet/config.yaml', '/etc/kubernetes/manifests/etcd.yaml',
        '/etc/kubernetes/manifests/kube-apiserver.yaml')]
    fixtures = component_fixtures(*sources)
    # Only these fixed staging paths are writable. No active manifest appears
    # on the destination side of any command.
    commands = ['set -eu', 'mkdir -p /opt/cks-lab/exam /opt/cks-lab/audit /opt/cks-lab/image-config']
    for relative, content in fixtures.items():
        encoded = base64.b64encode(content.encode()).decode()
        commands.append('printf %s ' + shlex.quote(encoded) + ' | base64 --decode > ' +
                        shlex.quote('/opt/cks-lab/' + relative))
    core.command(core.PREFIX + ['ssh', '--', '; '.join(commands)])
    uploaded = {relative: core.command(core.PREFIX + ['ssh', '--', 'cat /opt/cks-lab/' + relative])
                .replace('\r\n', '\n') for relative in fixtures}
    if uploaded != fixtures:
        raise core.EvidenceError('staged component fixture verification failed')
    return verify_component_faults(uploaded)


def verify_starting_workloads():
    objects = [core.get('deployment', name, ns) for ns, name in (
        ('exam-build', 'build-app'), ('exam-immutable', 'immutable-app'),
        ('exam-restricted', 'locked-app'))]
    objects.extend([core.get('serviceaccount', 'app-sa', 'exam-tokens'),
                    core.get('pod', 'token-client', 'exam-tokens')])
    checks = verify_workload_faults(objects)
    # Creation/incident tasks must start unfinished too. Data and healthy test
    # endpoints are prerequisites, not repairs performed on the candidate's behalf.
    secrets_list = core.get('secrets', namespace='exam-tls').get('items', [])
    checks['02.missing-secret'] = not any(o['metadata']['name'] == 'site-tls' for o in secrets_list)
    checks['07.no-allow-or-deny-policy'] = not core.get('networkpolicies', namespace='exam-backend').get('items')
    checks['11.both-containers-present'] = len(core.get('deployment', 'inventory', 'exam-supply')['spec']['template']['spec']['containers']) == 2
    for name in ('orders', 'ledger', 'reporting'):
        checks['04.' + name + '-not-contained'] = core.get('deployment', name, 'exam-runtime')['spec'].get('replicas', 1) == 1
    checks['03.root-image-user'] = 'USER root' in (FILES / 'Dockerfile').read_text()
    checks['04.no-completed-rule'] = (FILES / 'falco_rules.local.yaml').read_text().strip().startswith('#')
    for name in ('incident.json', 'findings.json', 'amber.spdx', 'cobalt.spdx'):
        checks['output-missing.' + name] = not (FILES / name).exists()
    if not all(checks.values()):
        raise core.EvidenceError('starting workload audit failed: ' + ', '.join(k for k, value in checks.items() if not value))
    return checks


def setup():
    check_owner()
    FILES.mkdir(parents=True, exist_ok=False)
    component_checks = prepare_component_fixtures()
    namespaces = ['exam-tls', 'exam-build', 'exam-runtime', 'exam-immutable', 'exam-backend',
                  'exam-allowed', 'exam-denied', 'exam-tokens', 'exam-supply', 'exam-restricted',
                  'exam-ingress', 'exam-mesh']
    for ns in namespaces:
        apply({'apiVersion': 'v1', 'kind': 'Namespace', 'metadata': {'name': ns}})
    (FILES / 'Dockerfile').write_text('FROM busybox:1.37\nUSER root\nCMD ["sleep", "86400"]\n')
    apply(deployment('certificate-reader', 'exam-tls', spec={
        'containers': [{'name': 'app', 'image': 'busybox:1.37', 'command': ['sleep', '86400'],
                        'volumeMounts': [{'name': 'tls', 'mountPath': '/tls', 'readOnly': True}]}],
        'volumes': [{'name': 'tls', 'secret': {'secretName': 'site-tls'}}]}))
    for name, namespace in [('build-app', 'exam-build'), ('immutable-app', 'exam-immutable')]:
        apply(deployment(name, namespace, [{'name': 'app', 'image': 'busybox:1.37',
            'command': ['sleep', '86400'], 'securityContext': insecure_container()}]))
    for name in ('orders', 'ledger', 'reporting'):
        apply(deployment(name, 'exam-runtime'))
    # Native HTTP server makes allowed/denied network behavior testable.
    server = [{'name': 'http', 'image': 'busybox:1.37', 'command': ['sh', '-c',
               'mkdir -p /tmp/www; echo cks-network-ok > /tmp/www/index.html; exec httpd -f -p 8080 -h /tmp/www'],
               'ports': [{'containerPort': 8080}], 'readinessProbe': {'tcpSocket': {'port': 8080}}}]
    apply(deployment('api', 'exam-backend', server))
    apply(deployment('web', 'exam-ingress', server))
    apply({'apiVersion': 'v1', 'kind': 'Service', 'metadata': {'name': 'web', 'namespace': 'exam-ingress'},
           'spec': {'selector': {'app': 'web'}, 'ports': [{'port': 80, 'targetPort': 8080}]}})
    for ns in ('exam-allowed', 'exam-denied', 'exam-backend'):
        apply({'apiVersion': 'v1', 'kind': 'Pod', 'metadata': {'name': 'probe', 'namespace': ns},
               'spec': {'containers': [{'name': 'probe', 'image': 'busybox:1.37', 'command': ['sleep', '86400']}]}})
    apply({'apiVersion': 'v1', 'kind': 'ServiceAccount', 'metadata': {'name': 'app-sa', 'namespace': 'exam-tokens'},
           'automountServiceAccountToken': True})
    apply({'apiVersion': 'v1', 'kind': 'Pod', 'metadata': {'name': 'token-client', 'namespace': 'exam-tokens'},
           'spec': {'serviceAccountName': 'app-sa', 'automountServiceAccountToken': True,
                    'containers': [{'name': 'app', 'image': 'busybox:1.37', 'command': ['sleep', '86400'],
                        'volumeMounts': [{'name': 'legacy-token', 'mountPath': '/var/run/secrets/legacy', 'readOnly': False}]}],
                    'volumes': [{'name': 'legacy-token', 'projected': {'sources': [{'serviceAccountToken': {
                        'path': 'old-token', 'audience': 'legacy-api', 'expirationSeconds': 600}}]}}]}})
    # Random container/image assignment requires investigation, not a known name.
    images = ['alpine:3.19.1', 'busybox:1.37']
    if secrets.randbelow(2):
        images.reverse()
    candidates = dict(zip(('amber', 'cobalt'), images))
    apply(deployment('inventory', 'exam-supply', [{'name': n, 'image': image, 'command': ['sleep', '86400']}
                                                for n, image in candidates.items()]))
    # Deployment creation succeeds; admission rejects its Pod until repaired.
    core.command(K + ['label', 'namespace', 'exam-restricted', 'pod-security.kubernetes.io/enforce=restricted',
                      'pod-security.kubernetes.io/enforce-version=v1.35', '--overwrite'])
    apply(deployment('locked-app', 'exam-restricted', spec={
        'securityContext': {'runAsNonRoot': False, 'runAsUser': 0, 'seccompProfile': {'type': 'Unconfined'}},
        'containers': [{'name': 'app', 'image': 'busybox:1.37', 'command': ['sleep', '86400'],
                        'securityContext': {'privileged': True, 'allowPrivilegeEscalation': True,
                                            'capabilities': {'add': ['SYS_ADMIN']}}}]}))
    healthy = [('exam-build', 'build-app'), ('exam-immutable', 'immutable-app'),
               ('exam-runtime', 'orders'), ('exam-runtime', 'ledger'), ('exam-runtime', 'reporting'),
               ('exam-backend', 'api'), ('exam-ingress', 'web'), ('exam-supply', 'inventory')]
    for ns, name in healthy:
        core.command(K + ['rollout', 'status', f'deployment/{name}', '-n', ns, '--timeout=180s'], timeout_seconds=200)
    for ns in ('exam-allowed', 'exam-denied', 'exam-backend'):
        core.command(K + ['wait', '--for=condition=Ready', 'pod/probe', '-n', ns, '--timeout=180s'], timeout_seconds=200)
    core.command(K + ['wait', '--for=condition=Ready', 'pod/token-client', '-n', 'exam-tokens', '--timeout=180s'], timeout_seconds=200)
    # Record a *working* network baseline before the candidate adds policies.
    if not network_probe('exam-allowed') or not network_probe('exam-denied') or not network_probe('exam-backend'):
        raise core.EvidenceError('network baseline failed; mock is not ready')
    culprit = secrets.choice(['orders', 'ledger', 'reporting'])
    events = []
    for name in ('orders', 'ledger', 'reporting'):
        p = pods(name, 'exam-runtime')[0]
        events.append({'time': '2026-10-31T12:00:00Z', 'priority': 'Warning' if name == culprit else 'Notice',
                       'rule': 'Memory device opened' if name == culprit else 'Application file opened',
                       'output_fields': {'fd.name': '/dev/mem' if name == culprit else '/etc/hosts',
                                         'evt.type': 'openat', 'k8s.ns.name': 'exam-runtime',
                                         'k8s.pod.name': p['metadata']['name']}})
    secrets.SystemRandom().shuffle(events)
    (FILES / 'runtime-events.jsonl').write_text(''.join(json.dumps(e) + '\n' for e in events))
    (FILES / 'falco_rules.local.yaml').write_text('# Add your custom Falco rule here.\n')
    expected = {'culprit': culprit, 'candidates': candidates,
                'removed': next(n for n, image in candidates.items() if image.startswith('alpine:'))}
    workload_checks = verify_starting_workloads()
    expected['scenario_revision'] = 2
    expected['starting_faults'] = {**component_checks, **workload_checks}
    (STATE / 'exam-expected.json').write_text(json.dumps(expected))
    print(f'Local starting-state audit passed: {len(expected["starting_faults"])} intentionally unfinished checks. External prerequisites remain separate.')


def pods(name, ns):
    return [p for p in core.get('pods', namespace=ns).get('items', []) if p.get('metadata', {}).get('labels', {}).get('app') == name and not p.get('metadata', {}).get('deletionTimestamp')]


def running_deployment(name, ns):
    d = core.get('deployment', name, ns)
    count = d.get('spec', {}).get('replicas', 1)
    s = d.get('status', {})
    return (d if count > 0 and s.get('observedGeneration', 0) >= d.get('metadata', {}).get('generation', 1)
            and s.get('updatedReplicas', 0) == count and s.get('availableReplicas', 0) == count
            and s.get('replicas', 0) == count else None)


def secure_containers(spec, uid=None, restricted=False):
    groups = [spec.get(k, []) for k in ('containers', 'initContainers', 'ephemeralContainers')]
    if not groups[0]:
        return False
    podsc = spec.get('securityContext', {})
    for c in sum(groups, []):
        sc = c.get('securityContext', {})
        if sc.get('privileged', False) is not False or sc.get('allowPrivilegeEscalation') is not False:
            return False
        if uid is not None and (sc.get('runAsUser', podsc.get('runAsUser')) != uid or sc.get('readOnlyRootFilesystem') is not True):
            return False
        if restricted:
            if sc.get('runAsNonRoot', podsc.get('runAsNonRoot')) is not True or sc.get('runAsUser', podsc.get('runAsUser')) == 0:
                return False
            if sc.get('seccompProfile', podsc.get('seccompProfile', {})).get('type') not in ('RuntimeDefault', 'Localhost'):
                return False
            caps = sc.get('capabilities', {})
            if 'ALL' not in caps.get('drop', []) or set(caps.get('add', [])) - {'NET_BIND_SERVICE'}:
                return False
    return not any(spec.get(k, False) for k in ('hostNetwork', 'hostPID', 'hostIPC'))


def check_build(text, spec):
    lines = [s.strip() for s in text.splitlines() if s.strip() and not s.lstrip().startswith('#')]
    stages = [i for i, s in enumerate(lines) if s.upper().startswith('FROM ')]
    if not stages:
        return False
    users = [s.split(None, 1)[1] for s in lines[stages[-1]:] if s.upper().startswith('USER ')]
    return bool(users and users[-1] == 'nobody' and secure_containers(spec, uid=65535))


def exec_text(name, ns, args):
    return core.command(K + ['exec', '-n', ns, name, '--'] + args).strip()


def network_probe(ns):
    clients = core.get('pod', 'probe', ns)
    targets = pods('api', 'exam-backend')
    if not core.ready(clients) or len(targets) != 1 or not core.ready(targets[0]):
        raise core.EvidenceError('network probe endpoints are not Ready')
    ip = targets[0].get('status', {}).get('podIP')
    if not ip:
        raise core.EvidenceError('missing network target IP')
    # A denied wget is represented by controlled output; failed kubectl exec is
    # an EvidenceError, not a successful isolation result.
    script = ('out=$(wget -q -T 3 -O- "$1"); code=$?; '
              'if [ "$code" -eq 0 ]; then printf "ALLOWED:%s" "$out"; '
              'elif [ "$code" -eq 1 ]; then printf BLOCKED; else exit "$code"; fi')
    answer = exec_text('probe', ns, ['sh', '-c', script, 'probe', f'http://{ip}:8080'])
    if answer == 'BLOCKED':
        return False
    if answer != 'ALLOWED:cks-network-ok':
        raise core.EvidenceError('unexpected network response')
    return True


def check_network():
    p = core.get('networkpolicy', 'default-deny-ingress', 'exam-backend').get('spec', {})
    if p.get('podSelector') != {} or 'Ingress' not in p.get('policyTypes', []) or p.get('ingress'):
        return False
    return (network_probe('exam-allowed') and not network_probe('exam-denied')
            and not network_probe('exam-backend') and network_probe('exam-allowed'))


def check_tls():
    secret = core.get('secret', 'site-tls', 'exam-tls')
    if not core.check_tls(secret):
        return False
    d = running_deployment('certificate-reader', 'exam-tls')
    if not d:
        return False
    spec = d['spec']['template']['spec']
    volumes = {v['name'] for v in spec.get('volumes', []) if v.get('secret', {}).get('secretName') == 'site-tls'}
    mounted = any(m.get('name') in volumes and m.get('mountPath') == '/tls' and m.get('readOnly') is True
                  for c in spec.get('containers', []) for m in c.get('volumeMounts', []))
    return mounted and base64.b64decode(secret.get('data', {}).get('tls.crt', ''), validate=True).strip() == core.JUMPBOX.joinpath('tls.crt').read_bytes().strip()


def check_token():
    sa = core.get('serviceaccount', 'app-sa', 'exam-tokens')
    p = core.get('pod', 'token-client', 'exam-tokens')
    s = p.get('spec', {})
    if sa.get('automountServiceAccountToken') is not False or s.get('automountServiceAccountToken') is not False or s.get('serviceAccountName') != 'app-sa' or not core.ready(p):
        return False
    for v in s.get('volumes', []):
        for source in v.get('projected', {}).get('sources', []):
            t = source.get('serviceAccountToken', {})
            if t.get('path') == 'token' and t.get('audience') == 'cks-lab' and t.get('expirationSeconds') == 3600:
                if any(m.get('name') == v['name'] and m.get('mountPath') == '/var/run/secrets/tokens' and m.get('readOnly') is True
                       for c in s.get('containers', []) for m in c.get('volumeMounts', [])):
                    return True
    return False


def package_names(text):
    try:
        d = json.loads(text)
    except ValueError:
        fields = {}
        for line in text.splitlines():
            if ': ' in line:
                k, v = line.split(': ', 1); fields.setdefault(k, []).append(v)
        if not any(v.startswith('SPDX-2.') for v in fields.get('SPDXVersion', [])) or 'CC0-1.0' not in fields.get('DataLicense', []) or 'SPDXRef-DOCUMENT' not in fields.get('SPDXID', []) or not fields.get('DocumentNamespace'):
            raise ValueError('not an SPDX document')
        return set(fields.get('PackageName', []))
    if not isinstance(d, dict) or not str(d.get('spdxVersion', '')).startswith('SPDX-2.') or d.get('SPDXID') != 'SPDXRef-DOCUMENT' or d.get('dataLicense') != 'CC0-1.0' or not d.get('documentNamespace'):
        raise ValueError('not an SPDX document')
    return {p['name'] for p in d.get('packages', [])}


def check_supply(expected):
    found = json.loads((FILES / 'findings.json').read_text())
    target = expected['removed']
    if found != {'container': target, 'image': expected['candidates'][target], 'package': 'libcrypto3'}:
        return False
    for name in expected['candidates']:
        packages = package_names((FILES / f'{name}.spdx').read_text())
        if not packages or ('libcrypto3' in packages) != (name == target):
            return False
    d = running_deployment('inventory', 'exam-supply')
    if not d:
        return False
    remaining = {c['name']: c['image'] for c in d['spec']['template']['spec']['containers']}
    return remaining == {n: i for n, i in expected['candidates'].items() if n != target}


def check_runtime(expected):
    incident = json.loads((FILES / 'incident.json').read_text())
    culprit = expected['culprit']
    if incident.get('namespace') != 'exam-runtime' or incident.get('deployment') != culprit:
        return False
    events = [json.loads(line) for line in (FILES / 'runtime-events.jsonl').read_text().splitlines()]
    suspicious = [e['output_fields']['k8s.pod.name'] for e in events if e['output_fields']['fd.name'] == '/dev/mem']
    if incident.get('pod') not in suspicious:
        return False
    for name in ('orders', 'ledger', 'reporting'):
        d = core.get('deployment', name, 'exam-runtime')
        if name == culprit:
            if d.get('spec', {}).get('replicas') != 0 or d.get('status', {}).get('replicas', 0) != 0:
                return False
        elif not running_deployment(name, 'exam-runtime'):
            return False
    return True


def check_hardened(name, ns, uid=None, restricted=False):
    d = running_deployment(name, ns)
    if not d or not secure_containers(d['spec']['template']['spec'], uid, restricted):
        return False
    live = pods(name, ns)
    if not live or not all(core.ready(p) and secure_containers(p['spec'], uid, restricted) for p in live):
        return False
    if uid is not None:
        for p in live:
            if exec_text(p['metadata']['name'], ns, ['id', '-u']) != str(uid):
                return False
            flags = exec_text(p['metadata']['name'], ns, ['awk', '$2 == \"/\" {print $4}', '/proc/mounts'])
            if 'ro' not in flags.split(','):
                return False
        return True
    return True


def score_exam(task=None):
    check_owner()
    if not (STATE / 'setup-complete').exists():
        raise core.EvidenceError('setup incomplete')
    expected = json.loads((STATE / 'exam-expected.json').read_text()) if task in (None, 4, 11) else {}
    checks = {
        2: check_tls,
        3: lambda: check_hardened('build-app', 'exam-build', 65535) and check_build((FILES / 'Dockerfile').read_text(), core.get('deployment', 'build-app', 'exam-build')['spec']['template']['spec']),
        4: lambda: check_runtime(expected),
        5: lambda: check_hardened('immutable-app', 'exam-immutable', 30000),
        7: check_network,
        9: check_token,
        11: lambda: check_supply(expected),
        12: lambda: core.get('namespace', 'exam-restricted').get('metadata', {}).get('labels', {}).get('pod-security.kubernetes.io/enforce') == 'restricted' and check_hardened('locked-app', 'exam-restricted', restricted=True),
    }
    config_grader = ConfigGrader(lambda path: core.command(core.PREFIX + ['ssh', '--', 'sudo cat ' + shlex.quote(path)]))
    earned = errors = 0
    for q, (title, weight) in enumerate(zip(TITLES, WEIGHTS), 1):
        if task is not None and q != task:
            continue
        available = 3 if q == 4 else weight if q in LIVE or q in CONFIG_TASKS else 0
        status = 'MANUAL'
        task_earned = 0
        details = []
        if q in CONFIG_TASKS:
            try:
                result = config_grader.grade(q)
                status = 'PASS CONFIG' if result.passed else 'FAIL CONFIG'
                task_earned = available if result.passed else 0
                details = [('PASS' if passed else 'FAIL', label) for label, passed in result.checks]
            except ConfigurationError as error:
                status = 'ERROR (no credit)'; errors += 1
                details = [('ERROR', str(error))]
            except (core.EvidenceError, OSError, ValueError, TypeError, KeyError, AttributeError):
                status = 'ERROR (no credit)'; errors += 1
                details = [('ERROR', 'Cannot read or validate configuration; check YAML syntax, duplicate keys/flags and the required files.')]
        if q in checks:
            try:
                passed = checks[q]()
                status = ('REPLAY PARTIAL' if q == 4 else 'PASS') if passed else 'FAIL'
                task_earned = available if passed else 0
            except (core.EvidenceError, OSError, ValueError, TypeError, KeyError, AttributeError):
                status = 'ERROR (no credit)'; errors += 1
        earned += task_earned
        print(f'{q:02}. {status:20} {title} [earned {task_earned}/{weight}; auto {available}, manual {weight - available}]')
        for outcome, label in details:
            print(f'    {outcome:5} {label}')
    if task is None:
        print(f'Mock evidence points: {earned}/100; automatic ceiling 72/100 (44 live + 3 replay + 25 configuration).')
    else:
        print(f'Task {task:02} practice points: {earned}/{WEIGHTS[task - 1]}.')
    print('CONFIG checks validate saved copies; they do not verify live component behavior.')
    print('28 points require external/manual evidence. No exam pass prediction. Run time for your deadline.')
    return 1 if errors else 0


def main():
    try:
        if sys.argv[1:] == ['setup']:
            setup(); return 0
        if sys.argv[1:] == ['score']:
            return score_exam()
        if len(sys.argv) == 4 and sys.argv[1:3] == ['score', '--task']:
            task = int(sys.argv[3])
            if 1 <= task <= len(WEIGHTS):
                return score_exam(task)
        raise ValueError('Use score [--task NUMBER] (1-16), or setup, via k8s-sim.sh')
    except (core.EvidenceError, OSError, ValueError, KeyError) as e:
        print(f'Mock unavailable: {e}', file=sys.stderr); return 1


if __name__ == '__main__':
    sys.exit(main())
