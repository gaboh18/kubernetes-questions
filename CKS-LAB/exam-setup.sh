#!/bin/bash
# exam-setup.sh - Minikube-Native CKS Simulator

echo "Setting up Minikube CKS Simulator..."

# 1. Setup Jumpbox Files (Mac Host)
echo "Setting up Jumpbox (Mac) files in /opt/cks-lab/..."
sudo mkdir -p /opt/cks-lab/
sudo chown -R $USER /opt/cks-lab/
cd /opt/cks-lab/

cat <<EOF > Dockerfile
FROM alpine:3.18
RUN apk add --no-cache curl
CMD ["curl", "-s", "http://example.com"]
EOF

cat <<EOF > falco.log
10:05:00.000000000: Notice A shell was spawned in a container with an attached terminal (user=root container_id=123 pod=hacker-pod namespace=web shell=/bin/bash)
EOF

# 2. Setup Live Cluster Resources
echo "Deploying vulnerable cluster resources..."
cat <<EOF | kubectl apply -f - 2>/dev/null
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

kubectl create ns backend web app istio-system prod frontend database dmz 2>/dev/null
kubectl run hacker-pod --image=nginx -n web 2>/dev/null
kubectl create deploy secure-app --image=nginx -n prod 2>/dev/null
kubectl create sa db-sa -n database 2>/dev/null
kubectl create deploy web-server --image=httpd:2.4.49 -n dmz 2>/dev/null
kubectl run immutable-pod --image=nginx -n default 2>/dev/null

# 3. Inject Node-Level Vulnerabilities (Minikube Node)
echo "Injecting node-level misconfigurations..."

# Break the Kubelet authorization mode
minikube ssh "sudo sed -i 's/mode: Webhook/mode: AlwaysAllow/g' /var/lib/kubelet/config.yaml"
minikube ssh "sudo systemctl restart kubelet"

# Plant compromised binaries on the node
minikube ssh "sudo bash -c 'echo \"fake-binary-content\" > /usr/local/bin/kube-apiserver-test'"
minikube ssh "sudo bash -c 'echo \"invalid-hash  /usr/local/bin/kube-apiserver-test\" > /usr/local/bin/kube-apiserver-test.sha512'"

echo "✅ Minikube Hybrid Environment Ready!"
