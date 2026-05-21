#!/bin/bash
# exam-setup.sh - Prepares the mock environment for the CKS Simulator

echo "Setting up CKS Simulator Environment (Lab 2)..."

mkdir -p /opt/cks-lab/
mkdir -p /etc/kubernetes/manifests/ /etc/kubernetes/enc/ /var/log/k8s/ /var/lib/kubelet/

# Mock CRDs for Cilium and Istio to prevent 'kubectl apply' errors
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

# Namespaces
kubectl create ns backend 2>/dev/null
kubectl create ns web 2>/dev/null
kubectl create ns app 2>/dev/null
kubectl create ns istio-system 2>/dev/null
kubectl create ns prod 2>/dev/null
kubectl create ns frontend 2>/dev/null
kubectl create ns database 2>/dev/null
kubectl create ns dmz 2>/dev/null

# Q1, Q13, Q17: Mock Apiserver
cat <<EOF > /opt/cks-lab/kube-apiserver.yaml
apiVersion: v1
kind: Pod
metadata:
  name: kube-apiserver
  namespace: kube-system
spec:
  containers:
  - command:
    - kube-apiserver
    - --enable-admission-plugins=NodeRestriction
    name: kube-apiserver
EOF
cp /opt/cks-lab/kube-apiserver.yaml /etc/kubernetes/manifests/kube-apiserver.yaml

# Q4: Malicious Pod
kubectl run hacker-pod --image=nginx -n web 2>/dev/null
cat <<EOF > /var/log/falco.log
10:05:00.000000000: Notice A shell was spawned in a container with an attached terminal (user=root container_id=123 pod=hacker-pod namespace=web shell=/bin/bash)
EOF

# Q7: Dockerfile
cat <<EOF > /opt/cks-lab/Dockerfile
FROM alpine:3.18
RUN apk add --no-cache curl
CMD ["curl", "-s", "http://example.com"]
EOF

# Q8: AppArmor Deployment
kubectl create deploy secure-app --image=nginx -n prod 2>/dev/null

# Q9: Kubelet config
cat <<EOF > /var/lib/kubelet/config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
authorization:
  mode: AlwaysAllow
EOF

# Q12: ServiceAccount
kubectl create sa db-sa -n database 2>/dev/null

# Q14: Compromised binary
echo "fake-binary" > /opt/cks-lab/kube-apiserver
echo "invalid-hash  kube-apiserver" > /opt/cks-lab/kube-apiserver.sha512

# Q15: Trivy vulnerable deploy
kubectl create deploy web-server --image=httpd:2.4.49 -n dmz 2>/dev/null

# Q16: RootOnlyFileSystem pod
kubectl run immutable-pod --image=nginx -n default 2>/dev/null

echo "Setup complete!"
