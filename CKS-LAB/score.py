#!/usr/bin/env python3
"""Conservative configuration checks. This is not an exam pass prediction."""
import base64
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent
STATE = ROOT / '.cks-state'
JUMPBOX = STATE / 'jumpbox'
PREFIX = ['minikube', '-p', 'cks-lab']
KUBECTL = ['kubectl', '--context=cks-lab']


class EvidenceError(Exception):
    pass


def command(args, input_data=None, timeout_seconds=45):
    try:
        p = subprocess.run(args, input=input_data, text=True, capture_output=True, timeout=timeout_seconds)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise EvidenceError('evidence command unavailable or timed out') from e
    if p.returncode:
        # Never print command output: it can include Secret data.
        raise EvidenceError('evidence command failed; no credit awarded')
    return p.stdout


def get(kind, name=None, namespace=None):
    args = KUBECTL + ['get', kind]
    if name:
        args.append(name)
    if namespace:
        args += ['-n', namespace]
    try:
        result = json.loads(command(args + ['-o', 'json', '--request-timeout=15s']))
    except ValueError as e:
        raise EvidenceError('invalid Kubernetes JSON') from e
    if not isinstance(result, dict):
        raise EvidenceError('invalid Kubernetes object')
    return result


def ready(pod):
    return pod.get('status', {}).get('phase') == 'Running' and any(
        c.get('type') == 'Ready' and c.get('status') == 'True'
        for c in pod.get('status', {}).get('conditions', []))


def check_network(policies):
    items = policies.get('items', [])
    target = next((p for p in items if p.get('metadata', {}).get('name') == 'default-deny-all'), {})
    s = target.get('spec', {})
    # NetworkPolicies are additive; another allow policy defeats default isolation.
    return (s.get('podSelector') == {} and set(s.get('policyTypes', [])) == {'Ingress', 'Egress'}
            and not s.get('ingress') and not s.get('egress')
            and all(not p.get('spec', {}).get('ingress') and not p.get('spec', {}).get('egress') for p in items))


def check_dockerfile(text):
    # Static final-stage check only; building and testing the image remains manual.
    lines = [s.strip() for s in text.splitlines() if s.strip() and not s.lstrip().startswith('#')]
    stages = [i for i, s in enumerate(lines) if re.match(r'FROM\s', s, re.I)]
    if not stages:
        return False
    final = lines[stages[-1]:]
    users = [s.split(maxsplit=1)[1].strip() for s in final if re.match(r'USER\s', s, re.I)]
    return bool(users and users[-1] in ('appuser', '1000', '1000:1000', 'appuser:appgroup')
                and any(re.match(r'RUN\s', s, re.I) and 'adduser' in s and 'appuser' in s
                        and re.search(r'(?:-u\s+|--uid(?:=|\s+))1000\b', s) for s in final))


def check_sbom(text):
    try:
        doc = json.loads(text)
    except ValueError:
        fields = {}
        for line in text.splitlines():
            if ': ' in line:
                key, value = line.split(': ', 1)
                fields.setdefault(key, []).append(value)
        return (any(v.startswith('SPDX-2.') for v in fields.get('SPDXVersion', []))
                and 'CC0-1.0' in fields.get('DataLicense', [])
                and 'SPDXRef-DOCUMENT' in fields.get('SPDXID', [])
                and bool(fields.get('DocumentName')) and bool(fields.get('DocumentNamespace'))
                and any('nginx' in v.lower() for v in fields.get('PackageName', [])))
    return (isinstance(doc, dict) and str(doc.get('spdxVersion', '')).startswith('SPDX-2.')
            and doc.get('SPDXID') == 'SPDXRef-DOCUMENT' and doc.get('dataLicense') == 'CC0-1.0'
            and bool(doc.get('name')) and bool(doc.get('documentNamespace'))
            and any('nginx' in p.get('name', '').lower() for p in doc.get('packages', [])))


def check_multi(pod):
    names = [c.get('name') for c in pod.get('spec', {}).get('containers', [])]
    return ready(pod) and 'good-app' in names and 'vulnerable-app' not in names


def check_token(sa, pod):
    s = pod.get('spec', {})
    if sa.get('automountServiceAccountToken') is not False or s.get('serviceAccountName') != 'db-sa' or not ready(pod):
        return False
    volumes = {v['name']: v for v in s.get('volumes', [])}
    for c in s.get('containers', []):
        for mount in c.get('volumeMounts', []):
            if mount.get('mountPath') != '/var/run/secrets/tokens':
                continue
            sources = volumes.get(mount.get('name'), {}).get('projected', {}).get('sources', [])
            for source in sources:
                t = source.get('serviceAccountToken', {})
                if t.get('path') == 'token' and t.get('audience') == 'api' and t.get('expirationSeconds') == 7200:
                    return True
    return False


def check_image(deployment):
    s = deployment.get('spec', {})
    status = deployment.get('status', {})
    count = s.get('replicas', 1)
    containers = s.get('template', {}).get('spec', {}).get('containers', [])
    return (count > 0 and any(c.get('name') == 'httpd' and c.get('image') == 'httpd:2.4.58' for c in containers)
            and status.get('observedGeneration', 0) >= deployment.get('metadata', {}).get('generation', 1)
            and status.get('updatedReplicas', 0) == count and status.get('availableReplicas', 0) == count
            and status.get('replicas', 0) == count)


def check_immutable(pod):
    containers = pod.get('spec', {}).get('containers', [])
    return ready(pod) and bool(containers) and all(c.get('securityContext', {}).get('readOnlyRootFilesystem') is True for c in containers)


def check_tls(secret):
    if secret.get('type') != 'kubernetes.io/tls':
        return False
    try:
        cert = base64.b64decode(secret.get('data', {}).get('tls.crt', ''), validate=True)
        key = base64.b64decode(secret.get('data', {}).get('tls.key', ''), validate=True)
    except (ValueError, TypeError):
        return False
    if not cert or not key:
        return False
    with tempfile.TemporaryDirectory() as directory:
        certfile, keyfile = Path(directory) / 'cert', Path(directory) / 'key'
        certfile.write_bytes(cert); keyfile.write_bytes(key)
        keyfile.chmod(0o600)
        try:
            pubcert = command(['openssl', 'x509', '-in', str(certfile), '-noout', '-pubkey'])
            pubkey = command(['openssl', 'pkey', '-in', str(keyfile), '-passin', 'pass:', '-pubout'])
            command(['openssl', 'x509', '-in', str(certfile), '-noout', '-checkend', '0'])
        except EvidenceError:
            return False
        return pubcert == pubkey


def check_trivy(report):
    if not isinstance(report, dict) or report.get('SchemaVersion') != 2 or report.get('ArtifactName') != 'httpd:2.4.49' or report.get('ArtifactType') != 'container_image':
        return False
    results = report.get('Results')
    if not isinstance(results, list) or not results:
        return False
    for r in results:
        if not isinstance(r, dict) or not r.get('Target') or not r.get('Type'):
            return False
        vulns = r.get('Vulnerabilities') or []
        if not isinstance(vulns, list) or any(not isinstance(v, dict) or not v.get('VulnerabilityID') or v.get('Severity') != 'CRITICAL' for v in vulns):
            return False
    return True


def check_rbac(role, binding):
    rules = role.get('rules', [])
    ref = binding.get('roleRef', {})
    subjects = binding.get('subjects', [])
    return (bool(rules) and all(r.get('apiGroups') == [''] and r.get('resources') == ['pods']
            and set(r.get('verbs', [])) <= {'get', 'list'} and not r.get('nonResourceURLs')
            and not r.get('resourceNames') for r in rules)
            and set(v for r in rules for v in r.get('verbs', [])) == {'get', 'list'}
            and ref == {'apiGroup': 'rbac.authorization.k8s.io', 'kind': 'Role', 'name': 'auditor'}
            and subjects == [{'kind': 'ServiceAccount', 'name': 'auditor', 'namespace': 'rbac'}])


def rbac_evidence():
    if not check_rbac(get('role', 'auditor', 'rbac'), get('rolebinding', 'auditor', 'rbac')):
        return False
    # Check the effective union of permissions, including other bindings.
    base = KUBECTL + ['auth', 'can-i']
    for verb, resource, expected in [('get', 'pods', True), ('list', 'pods', True),
                                      ('get', 'secrets', False), ('create', 'pods', False),
                                      ('delete', 'pods', False), ('create', 'deployments.apps', False)]:
        try:
            p = subprocess.run(base + [verb, resource, '-n', 'rbac', '--as=system:serviceaccount:rbac:auditor',
                                       '--request-timeout=15s'], text=True, capture_output=True, timeout=45)
        except (OSError, subprocess.TimeoutExpired) as e:
            raise EvidenceError('RBAC permission evidence unavailable') from e
        answer = p.stdout.strip()
        if answer not in ('yes', 'no') or p.returncode not in (0, 1):
            raise EvidenceError('RBAC permission query failed')
        if (answer == 'yes') != expected:
            return False
    return True


MANUAL = {
    1: 'Admission config: needs working webhook and real API restart/rejection test.',
    2: 'Upgrade: use a disposable kubeadm Linux cluster; no architecture auto-pass.',
    4: 'Falco: requires engine, valid rules, event replay and containment evidence.',
    5: 'Cilium: requires actual CNI and allowed/denied traffic tests.',
    6: 'Istio: requires actual mesh, enrolled workloads and plaintext rejection.',
    8: 'AppArmor/seccomp: load profile on eligible nodes and verify workload behavior.',
    9: 'Kubelet: file-only fixture; verify authn/authz and restart on a disposable VM.',
    13: 'Audit: fixture policy logs only pods; test required coverage and log delivery.',
    17: 'Encryption: fixture only; rewrite existing Secrets and inspect raw etcd data.',
    19: 'Ingress: requires backend, TLS binding, controller and HTTP/HTTPS probes.',
    20: 'Docker: use a disposable Docker host; real users/sockets are not altered.',
}


def main():
    try:
        uid = STATE.joinpath('cluster-uid').read_text().strip()
        if not uid or get('namespace', 'kube-system').get('metadata', {}).get('uid') != uid:
            raise EvidenceError('cluster ownership mismatch')
        if not STATE.joinpath('setup-complete').exists():
            raise EvidenceError('setup is incomplete')
        checks = {
            3: ('Default deny policy configuration (traffic test still required)', lambda: check_network(get('networkpolicies', namespace='backend'))),
            7: ('Final Dockerfile user (build/runtime test still required)', lambda: check_dockerfile(JUMPBOX.joinpath('Dockerfile').read_text())),
            10: ('SPDX structure and surviving Ready pod', lambda: check_sbom(command(PREFIX + ['ssh', '--', 'cat /opt/cks-lab/sbom.spdx'])) and check_multi(get('pod', 'multi-pod', 'default'))),
            11: ('Restricted namespace label', lambda: get('namespace', 'frontend').get('metadata', {}).get('labels', {}).get('pod-security.kubernetes.io/enforce') == 'restricted'),
            12: ('SA automount and mounted token projection', lambda: check_token(get('serviceaccount', 'db-sa', 'database'), get('pod', 'token-pod', 'database'))),
            14: ('Tampered fixture removed after valid checksum staging', lambda: command(PREFIX + ['ssh', '--', 'set -e; grep -qx cks-lab-fixtures-v1 /opt/cks-lab/fixture-marker; test -s /opt/cks-lab/kube-apiserver-test.sha512; test ! -e /opt/cks-lab/kube-apiserver-test; printf removed']).strip() == 'removed'),
            15: ('Historical image replacement and completed rollout', lambda: check_image(get('deployment', 'web-server', 'dmz'))),
            16: ('Read-only filesystem and Ready pod', lambda: check_immutable(get('pod', 'immutable-pod', 'default'))),
            18: ('TLS type, parseable unexpired cert and matching key', lambda: check_tls(get('secret', 'secure-tls', 'default'))),
            22: ('Least-privilege Role, binding and effective permission probes', rbac_evidence),
            21: ('Trivy JSON structure, target image and CRITICAL filter', lambda: check_trivy(json.loads(JUMPBOX.joinpath('trivy-report.json').read_text()))),
        }
    except (OSError, EvidenceError, ValueError) as e:
        print(f'Scoring unavailable: {e}', file=sys.stderr)
        return 1
    earned = errors = 0
    for q in range(1, 23):
        if q in MANUAL:
            print(f'Q{q:02} MANUAL: {MANUAL[q]}')
            continue
        title, check = checks[q]
        try:
            passed = bool(check())
            earned += 5 if passed else 0
            result = 'PASS' if passed else 'FAIL'
        except (EvidenceError, OSError, ValueError, TypeError, KeyError, AttributeError):
            result = 'ERROR (evidence unavailable; zero credit)'
            errors += 1
        print(f'Q{q:02} {result}: {title}')
    total = 5 * len(checks)
    print(f'Configuration checks: {earned}/{total} ({earned / total:.0%}); coverage {len(checks)}/22 tasks; {len(MANUAL)} manual.')
    print('This is a practice configuration score, not a CKS pass prediction or proof of enforcement.')
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
