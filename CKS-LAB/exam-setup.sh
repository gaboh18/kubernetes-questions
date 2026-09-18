#!/bin/bash
# exam-setup.sh - Clean, Self-Healing CKS Environment Setup

echo "Setting up Minikube CKS Simulator..."

# ============================================================
# 📦 STEP 1: Stage Config Files On the Node First
# ============================================================
minikube ssh "sudo mkdir -p /etc/kubernetes/image-config /etc/apparmor.d /etc/kubernetes/audit /etc/kubernetes/encryption"

# Admission Config
minikube ssh "cat << 'EOF' | sudo tee /etc/kubernetes/image-config/admission-configuration.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
  - name: ImagePolicyWebhook
    configuration:
      imagePolicy:
        kubeConfigFile: /etc/kubernetes/image-config/webhook-kubeconfig.yaml
        defaultAllow: true
EOF"

minikube ssh "cat << 'EOF' | sudo tee /etc/kubernetes/image-config/webhook-kubeconfig.yaml
apiVersion: v1
kind: Config
preferences: {}
clusters:
  - cluster:
      server: https://imagescanner.local/validate
    name: image-scanner
users:
  - name: api-server
contexts:
  - context:
      cluster: image-scanner
      user: api-server
    name: webhook
current-context: webhook
EOF"

# AppArmor
minikube ssh "cat << 'EOF' | sudo tee /etc/apparmor.d/custom-profile
#include <tunables/global>
profile custom-profile flags=(attach_disconnected) {
  #include <abstractions/base>
  network inet stream,
  deny /etc/passwd r,
}
EOF"
# Pre-parse into kernel
minikube ssh "sudo apparmor_parser -r -W /etc/apparmor.d/custom-profile" 2>/dev/null || true

# Audit Policy
minikube ssh "cat << 'EOF' | sudo tee /etc/kubernetes/audit/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: Metadata
    resources:
      - group: \"\"
        resources: [\"pods\"]
  - level: None
EOF"

# Encryption at Rest
RAND_KEY=$(head -c 32 /dev/urandom | base64)
minikube ssh "cat << EOF | sudo tee /etc/kubernetes/encryption/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - secretbox:
          keys:
            - name: key1
              secret: ${RAND_KEY}
      - identity: {}
EOF"

# ============================================================
# 🚨 STEP 2:)
# ============================================================
echo "Staging advanced exam components..."

# Q4: Falco rules and target
minikube ssh "sudo mkdir -p /etc/falco && sudo touch /etc/falco/falco_rules.local.yaml"

# Q10: Install BOM CLI
minikube ssh "curl -sL https://github.com/kubernetes-sigs/bom/releases/download/v0.5.1/bom-amd64-linux -o /tmp/bom && sudo mv /tmp/bom /usr/local/bin/bom && sudo chmod +x /usr/local/bin/bom"

# Q18: TLS files
mkdir -p /opt/cks-lab/
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /opt/cks-lab/tls.key -out /opt/cks-lab/tls.crt -subj "/CN=cks.example.com" 2>/dev/null

# Q20: Host Docker socket forensics
minikube ssh "sudo useradd unauthorized_user 2>/dev/null; sudo groupadd docker 2>/dev/null; sudo usermod -aG docker unauthorized_user; sudo touch /var/run/docker.sock; sudo chown unauthorized_user:docker /var/run/docker.sock"

# ============================================================
# ⚠️ STEP 3: Break the API Server Manifest
# ============================================================
minikube ssh "sudo sed -i '/--admission-control-config-file/d' /etc/kubernetes/manifests/kube-apiserver.yaml"
minikube ssh "sudo sed -i 's/,ImagePolicyWebhook//g' /etc/kubernetes/manifests/kube-apiserver.yaml"
minikube ssh "sudo sed -i '/image-policy-config/,+3d' /etc/kubernetes/manifests/kube-apiserver.yaml"

# Kubelet misconfiguration and dummy binaries
minikube ssh "sudo sed -i 's/mode: Webhook/mode: AlwaysAllow/g' /var/lib/kubelet/config.yaml && sudo pkill -9 kubelet && sudo bash -c 'echo \"fake-binary-content\" > /usr/local/bin/kube-apiserver-test' && sudo bash -c 'echo \"invalid-hash  /usr/local/bin/kube-apiserver-test\" > /usr/local/bin/kube-apiserver-test.sha512'"

# ============================================================
# ⏳ STEP 4: Wait for Stabilize
# ============================================================
echo "Waiting for cluster stability..."
until kubectl get serviceaccount default &>/dev/null; do printf "."; sleep 3; done
sleep 5

# ============================================================
# 🚀 STEP 5: Deploy Cluster Objects
# ============================================================
cat <<EOF | kubectl apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: ciliumnetworkpolicies.cilium.io
spec:
  group: cilium.io
  names:
    kind: CiliumNetworkPolicy
    plural: ciliumnetworkpolicies
    singular: ciliumnetworkpolicy
  scope: Namespaced
  versions:
  - name: v2
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        x-kubernetes-preserve-unknown-fields: true
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: peerauthentications.security.istio.io
spec:
  group: security.istio.io
  names:
    kind: PeerAuthentication
    plural: peerauthentications
    singular: peerauthentication
  scope: Namespaced
  versions:
  - name: v1beta1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        x-kubernetes-preserve-unknown-fields: true
EOF

for ns in backend web app istio-system prod frontend database dmz; do
    kubectl create ns "$ns" 2>/dev/null
done

# Standard Deployments
kubectl create deploy web-backend --image=nginx -n web
kubectl create deploy secure-app --image=nginx -n prod
kubectl create sa db-sa -n database
kubectl create deploy web-server --image=httpd:2.4.49 -n dmz
kubectl run immutable-pod --image=nginx -n default
kubectl create ingress secure-ingress --rule="cks.example.com/*=secure-svc:80" -n default

# Multipod for BOM
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: multi-pod
  namespace: default
spec:
  containers:
  - name: good-app
    image: nginx
  - name: vulnerable-app
    image: httpd:2.4.49
EOF

# ============================================================
# 💻 STEP 6: Jumpbox Setup
# ============================================================
cat <<EOF > /opt/cks-lab/Dockerfile
FROM alpine:3.18
RUN apk add --no-cache curl
CMD ["curl", "-s", "http://example.com"]
EOF

# ============================================================
# 🛡️ STEP 7: Ensure Trivy is Installed for Q21
# ============================================================
if ! command -v trivy &> /dev/null; then
    echo "Installing Trivy via Homebrew for Q21..."
    if command -v brew &> /dev/null; then
        brew install trivy
    else
        echo "⚠️ Homebrew not found. Please install Trivy manually: brew install trivy"
    fi
fi

# Ensure node tools
minikube ssh "sudo apt-get update -qq && sudo apt-get install -y -qq vim procps curl apparmor apparmor-utils" 2>/dev/null
echo "✅ Environment Ready!"
