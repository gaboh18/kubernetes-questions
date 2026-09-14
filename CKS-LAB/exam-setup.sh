#!/bin/bash
# exam-setup.sh - Clean, Self-Healing CKS Environment Setup

echo "Setting up Minikube CKS Simulator..."

# ============================================================
# 📦 STEP 1: Stage Config Files On the Node First
# ============================================================
# Create the target directory on the node
minikube ssh "sudo mkdir -p /etc/kubernetes/image-config /etc/apparmor.d /etc/kubernetes/audit /etc/kubernetes/encryption"

# Stage the exam-grade admission configuration file
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

# Stage the required underlying webhook kubeconfig
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
minikube ssh "cat << 'EOF' | sudo tee /etc/apparmor.d/custom-profile
#include <tunables/global>
profile custom-profile flags=(attach_disconnected) {
  #include <abstractions/base>
  network inet stream,
  deny /etc/passwd r,
}
EOF"

# --- QUESTION 13: Audit Policy Template ---
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
minikube ssh "cat << 'EOF' | sudo tee /etc/kubernetes/encryption/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - identity: {}
EOF"

# ============================================================
# ⚠️ STEP 2: Break the API Server Manifest to Simulate Exam Start
# ============================================================
minikube ssh "sudo sed -i '/--admission-control-config-file/d' /etc/kubernetes/manifests/kube-apiserver.yaml"
minikube ssh "sudo sed -i 's/,ImagePolicyWebhook//g' /etc/kubernetes/manifests/kube-apiserver.yaml"
minikube ssh "sudo sed -i '/image-policy-config/,+3d' /etc/kubernetes/manifests/kube-apiserver.yaml"

# Inject Kubelet misconfiguration and dummy binaries
minikube ssh "sudo sed -i 's/mode: Webhook/mode: AlwaysAllow/g' /var/lib/kubelet/config.yaml && sudo pkill -9 kubelet && sudo bash -c 'echo \"fake-binary-content\" > /usr/local/bin/kube-apiserver-test' && sudo bash -c 'echo \"invalid-hash  /usr/local/bin/kube-apiserver-test\" > /usr/local/bin/kube-apiserver-test.sha512'"

# ============================================================
# ⏳ STEP 3: RESILIENT HEALTH-CHECK (Using Native Kubectl)
# ============================================================
echo "Waiting for the cluster database and controllers to fully stabilize..."
# Use host native kubectl directly without the minikube wrapper proxy
until kubectl get serviceaccount default &>/dev/null; do
    printf "."
    sleep 3
done
sleep 5
echo -e "\nCluster controllers are 100% active and stable!"

# ============================================================
# 🚀 STEP 4: Deploy Cluster Objects (Now Guaranteed to Pass!)
# ============================================================
echo "Deploying infrastructure objects..."

# 1. Apply the CRDs
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

# 2. FIXED: Iterate through the namespaces one-by-one cleanly
for ns in backend web app istio-system prod frontend database dmz; do
    kubectl create ns "$ns"
done

# 3. Deploy the workload resources now that the target environments exist!
kubectl run hacker-pod --image=nginx -n web
kubectl create deploy secure-app --image=nginx -n prod
kubectl create sa db-sa -n database
kubectl create deploy web-server --image=httpd:2.4.49 -n dmz
kubectl run immutable-pod --image=nginx -n default

# ============================================================
# 💻 STEP 5: Setup Local Jumpbox Files (Mac Host)
# ============================================================
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

# RETURN HOME: Snap back to your repository directory!
cd -

# ============================================================
# 🛠️ STEP 6: Pre-stage Essential Exam Node Tooling
# ============================================================
echo "Ensuring node tools (vim, watch, kubectl) are present..."
minikube ssh "sudo apt-get update -qq && sudo apt-get install -y -qq vim procps curl" 2>/dev/null

echo "Installing native kubectl binary inside Minikube node..."
minikube ssh "curl -sLO \"https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\""
minikube ssh "chmod +x ./kubectl && sudo mv ./kubectl /usr/bin/kubectl"

# Permanently configure admin credentials for the root user inside the node
minikube ssh "sudo bash -c 'echo \"export KUBECONFIG=/etc/kubernetes/admin.conf\" >> /root/.bashrc'"

echo "✅ Minikube Hybrid Environment Ready!"
