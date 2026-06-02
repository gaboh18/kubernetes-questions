#!/bin/bash
# exam-setup.sh - Self-Healing CKS Environment Setup

echo "Setting up Minikube CKS Simulator..."

# 1. Ensure Node is in a Clean, Recovered State First (Self-Healing)
echo "Healing control plane node state..."
minikube ssh "sudo sed -i 's/mode: AlwaysAllow/mode: Webhook/g' /var/lib/kubelet/config.yaml 2>/dev/null"
minikube ssh "sudo pkill -9 kubelet 2>/dev/null"
minikube ssh "sudo rm -f /usr/local/bin/kube-apiserver-test*"

# 2. Setup Jumpbox Files (Mac Host)
echo "Staging Jumpbox workspace files..."
mkdir -p /opt/cks-lab/
cd /opt/cks-lab/

cat <<EOF > Dockerfile
FROM alpine:3.18
RUN apk add --no-cache curl
CMD ["curl", "-s", "http://example.com"]
EOF

cat <<EOF > falco.log
10:05:00.000000000: Notice A shell was spawned in a container with an attached terminal (user=root container_id=123 pod=hacker-pod namespace=web shell=/bin/bash)
EOF

# 3. Deploy Live Cluster Resources (Only if API Server is reachable)
echo "Deploying infrastructure objects..."
cat <<EOF | kubectl apply -f - --timeout=10s 2>/dev/null
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

kubectl create ns backend web app istio-system prod frontend database dmz --timeout=5s 2>/dev/null
kubectl run hacker-pod --image=nginx -n web --timeout=5s 2>/dev/null
kubectl create deploy secure-app --image=nginx -n prod 2>/dev/null
kubectl create sa db-sa -n database 2>/dev/null
kubectl create deploy web-server --image=httpd:2.4.49 -n dmz 2>/dev/null
kubectl run immutable-pod --image=nginx -n default 2>/dev/null

# 4. Inject Node-Level Vulnerabilities & Stage All Exam Assets
echo "Injecting node-level misconfigurations and staging exam files..."

# Base injection strings from before
minikube ssh "sudo sed -i 's/mode: Webhook/mode: AlwaysAllow/g' /var/lib/kubelet/config.yaml && sudo pkill -9 kubelet && sudo bash -c 'echo \"fake-binary-content\" > /usr/local/bin/kube-apiserver-test' && sudo bash -c 'echo \"invalid-hash  /usr/local/bin/kube-apiserver-test\" > /usr/local/bin/kube-apiserver-test.sha512'"

# --- QUESTION 1: ImagePolicyWebhook Assets ---
minikube ssh "sudo mkdir -p /etc/kubernetes/image-config"
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

# --- QUESTION 8: AppArmor Profile Template ---
minikube ssh "sudo mkdir -p /etc/apparmor.d"
minikube ssh "cat << 'EOF' | sudo tee /etc/apparmor.d/custom-profile
#include <tunables/global>
profile custom-profile flags=(attach_disconnected) {
  #include <abstractions/base>
  network inet stream,
  deny /etc/passwd r,
}
EOF"

# --- QUESTION 13: Audit Policy Template ---
minikube ssh "sudo mkdir -p /etc/kubernetes/audit"
minikube ssh "cat << 'EOF' | sudo tee /etc/kubernetes/audit/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: Metadata
    resources:
      - group: ""
        resources: ["pods"]
  - level: None
EOF"

# --- QUESTION 17: Encryption at Rest Template ---
minikube ssh "sudo mkdir -p /etc/kubernetes/encryption"
minikube ssh "cat << 'EOF' | sudo tee /etc/kubernetes/encryption/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - identity: {}
EOF"

# 5. Pre-stage Essential Exam Tooling
echo "Ensuring node tools (vim, watch) are present..."
minikube ssh "apt-get update -qq && apt-get install -y -qq vim procps" 2>/dev/null

echo "✅ Minikube Hybrid Environment Ready!"
