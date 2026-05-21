#!/bin/bash
# exam-setup.sh - Hybrid CKS Setup for Docker Desktop

echo "Setting up Hybrid CKS Simulator for Docker Desktop..."

# 1. Create local simulation directory for Control Plane/Node tasks
mkdir -p /opt/cks-lab/
cd /opt/cks-lab/

# Q1, Q13, Q17: Simulated API Server
cat <<EOF > kube-apiserver.yaml
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

# Q9: Simulated Kubelet Config
cat <<EOF > kubelet-config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
authorization:
  mode: AlwaysAllow
EOF

# Q7: Dockerfile
cat <<EOF > Dockerfile
FROM alpine:3.18
RUN apk add --no-cache curl
CMD ["curl", "-s", "http://example.com"]
EOF

# Q14: Compromised binary simulation
echo "fake-binary-content" > kube-apiserver-test
echo "invalid-hash  kube-apiserver-test" > kube-apiserver-test.sha512

# Q4: Falco Log simulation
cat <<EOF > falco.log
10:05:00.000000000: Notice A shell was spawned in a container with an attached terminal (user=root container_id=123 pod=hacker-pod namespace=web shell=/bin/bash)
EOF

# 2. Live Cluster Setup (Standard K8s Resources)
echo "Setting up live cluster resources..."

# Mock CRDs for Cilium and Istio
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
kubectl create ns backend web app istio-system prod frontend database dmz 2>/dev/null

# Live resources
kubectl run hacker-pod --image=nginx -n web 2>/dev/null
kubectl create deploy secure-app --image=nginx -n prod 2>/dev/null
kubectl create sa db-sa -n database 2>/dev/null
kubectl create deploy web-server --image=httpd:2.4.49 -n dmz 2>/dev/null
kubectl run immutable-pod --image=nginx -n default 2>/dev/null

echo "✅ Hybrid environment ready!"
