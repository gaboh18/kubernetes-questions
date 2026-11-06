#!/bin/bash
# Advanced node exercises are file-only simulations.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lab-common.sh"
require_lab
bash "$LAB_DIR/editor-setup.sh"
bash "$LAB_DIR/node-client-setup.sh"
[ ! -e "$STATE_DIR/setup-complete" ] || die "Setup is already complete. Use cleanup then start for a fresh attempt."
need openssl
mkdir -p "$JUMPBOX_DIR"
for file in Dockerfile tls.key tls.crt trivy-report.json; do
    [ ! -e "$JUMPBOX_DIR/$file" ] || die "Existing jumpbox work found ($file). Move the jumpbox directory aside before starting a fresh attempt."
done
umask 077
openssl req -x509 -nodes -days 30 -newkey rsa:2048 -keyout "$JUMPBOX_DIR/tls.key" -out "$JUMPBOX_DIR/tls.crt" -subj '/CN=cks.example.com' -addext 'subjectAltName=DNS:cks.example.com' 2>/dev/null
cat > "$JUMPBOX_DIR/Dockerfile" <<'DOCKERFILE'
FROM alpine:3.18
RUN apk add --no-cache curl
CMD ["curl", "-s", "http://example.com"]
DOCKERFILE
# All staged node files live inside /opt/cks-lab. Active components are untouched.
node 'sudo mkdir -p /opt/cks-lab && sudo chown "$(id -u):$(id -g)" /opt/cks-lab'
node 'set -eu
mkdir -p /opt/cks-lab/image-config /opt/cks-lab/audit /opt/cks-lab/encryption /opt/cks-lab/falco /opt/cks-lab/apparmor.d
sudo cat /etc/kubernetes/manifests/kube-apiserver.yaml > /opt/cks-lab/kube-apiserver.yaml
sudo cat /var/lib/kubelet/config.yaml > /opt/cks-lab/kubelet-config.yaml
sed -i "s/mode: Webhook/mode: AlwaysAllow/" /opt/cks-lab/kubelet-config.yaml
cat > /opt/cks-lab/image-config/admission-configuration.yaml <<"CONFIG"
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
- name: ImagePolicyWebhook
  configuration:
    imagePolicy:
      kubeConfigFile: /opt/cks-lab/image-config/webhook-kubeconfig.yaml
      defaultAllow: true
CONFIG
cat > /opt/cks-lab/image-config/webhook-kubeconfig.yaml <<"CONFIG"
apiVersion: v1
kind: Config
clusters:
- name: scanner
  cluster:
    server: https://imagescanner.invalid/validate
users:
- name: api-server
contexts:
- name: webhook
  context:
    cluster: scanner
    user: api-server
current-context: webhook
CONFIG
cat > /opt/cks-lab/audit/audit-policy.yaml <<"CONFIG"
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: Metadata
  resources:
  - group: ""
    resources: ["pods"]
- level: None
CONFIG
cat > /opt/cks-lab/encryption/encryption-config.yaml <<"CONFIG"
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources: [secrets]
  providers:
  - secretbox:
      keys:
      - name: key1
        secret: REPLACE_WITH_BASE64_32_BYTE_KEY
  - identity: {}
CONFIG
cat > /opt/cks-lab/apparmor.d/custom-profile <<"CONFIG"
#include <tunables/global>
profile custom-profile flags=(attach_disconnected) {
  #include <abstractions/base>
  network inet stream,
  deny /etc/passwd r,
}
CONFIG
: > /opt/cks-lab/falco/falco_rules.local.yaml
printf "trusted original content\n" > /opt/cks-lab/kube-apiserver-test
(cd /opt/cks-lab && sha512sum kube-apiserver-test > kube-apiserver-test.sha512)
printf "tampered content\n" > /opt/cks-lab/kube-apiserver-test
printf "cks-lab-fixtures-v1\n" > /opt/cks-lab/fixture-marker'
if [ "$(cat "$STATE_DIR/mode" 2>/dev/null || true)" = exam ]; then
    need python3
    python3 "$LAB_DIR/secon_version/exam_mode.py" setup
    touch "$STATE_DIR/setup-complete"
    echo "16-task mock ready. Read secon_version/EXAM.md; the two-hour timer starts next."
    exit 0
fi
for ns in backend web app prod frontend database dmz rbac; do
    k create namespace "$ns" --dry-run=client -o yaml | k apply -f -
done
k create deployment web-backend --image=nginx:1.27 -n web
k create deployment secure-app --image=nginx:1.27 -n prod
k create serviceaccount db-sa -n database
k create deployment web-server --image=httpd:2.4.49 -n dmz
# A sleeping process supports a read-only filesystem without nginx cache/PID errors.
k run immutable-pod --image=busybox:1.37 -n default --command -- sleep 86400
k create ingress secure-ingress --rule='cks.example.com/*=secure-svc:80' -n default
k apply -f - <<'MANIFEST'
apiVersion: v1
kind: Pod
metadata:
  name: multi-pod
  namespace: default
spec:
  containers:
  - name: good-app
    image: nginx:1.27
  - name: vulnerable-app
    image: busybox:1.37
    command: ["sleep", "86400"]
MANIFEST
# Least-privilege exercise: excessive access stays inside a dedicated namespace.
k apply -f - <<'RBAC'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: auditor
  namespace: rbac
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: auditor
  namespace: rbac
rules:
- apiGroups: [""]
  resources: ["pods", "secrets"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: auditor
  namespace: rbac
subjects:
- kind: ServiceAccount
  name: auditor
  namespace: rbac
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: auditor
RBAC
k wait --for=condition=Ready pod/immutable-pod pod/multi-pod --timeout=180s
for target in web/web-backend prod/secure-app dmz/web-server; do
    k rollout status "deployment/${target#*/}" -n "${target%/*}" --timeout=180s
done
touch "$STATE_DIR/setup-complete"
echo "Practice baseline ready. Advanced tasks need manual review; see README.md."
