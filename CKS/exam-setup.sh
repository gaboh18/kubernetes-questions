#!/bin/bash
# exam-setup.sh - CKS Simulator Setup

echo "🚀 Setting up the CKS environment..."

# --- Infrastructure ---
CKS_DIR="/opt/cks-lab"
sudo mkdir -p $CKS_DIR
sudo chmod 777 $CKS_DIR

NAMESPACES="net-block runtime-sec istio-prod"
for ns in $NAMESPACES; do
    kubectl delete ns $ns --wait=false 2>/dev/null
done
sleep 2
for ns in $NAMESPACES; do
    kubectl create ns $ns 2>/dev/null
done

# Q1: Pod Security (Target: restricted-deploy)
kubectl create deploy restricted-deploy --image=nginx --replicas=1

# Q2, Q3, Q4: Control Plane Hardening (Simulated API Server)
cat <<EOF > $CKS_DIR/kube-apiserver.yaml
apiVersion: v1
kind: Pod
metadata:
  name: kube-apiserver
  namespace: kube-system
spec:
  containers:
  - command:
    - kube-apiserver
    - --advertise-address=10.0.0.1
    - --allow-privileged=true
    - --anonymous-auth=true
    - --authorization-mode=AlwaysAllow
    - --enable-admission-plugins=NodeRestriction
    image: k8s.gcr.io/kube-apiserver:v1.29.0
    name: kube-apiserver
    volumeMounts:
    - mountPath: /etc/kubernetes/pki
      name: k8s-certs
      readOnly: true
EOF

cat <<EOF > $CKS_DIR/admission-kubeconfig.yaml
# Dummy admission config
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
EOF

# Q5: Network Policies (Target: net-block namespace)
kubectl run frontend -n net-block --image=nginx --labels=app=wrong-front
kubectl run backend -n net-block --image=nginx --labels=app=wrong-back
kubectl run database -n net-block --image=nginx --labels=app=wrong-db

kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: deny-all, namespace: net-block }
spec: { podSelector: {}, policyTypes: [Ingress, Egress] }
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: front-to-back, namespace: net-block }
spec:
  podSelector: { matchLabels: { app: backend } }
  ingress: [{ from: [{ podSelector: { matchLabels: { app: frontend } } }] }]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: back-to-db, namespace: net-block }
spec:
  podSelector: { matchLabels: { app: db } }
  ingress: [{ from: [{ podSelector: { matchLabels: { app: backend } } }] }]
EOF

# Q6: Docker/Node Hardening
cat <<EOF > $CKS_DIR/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "hosts": ["unix:///var/run/docker.sock", "tcp://0.0.0.0:2375"],
  "log-driver": "json-file"
}
EOF
echo "root:x:0:" > $CKS_DIR/group
echo "docker:x:999:ubuntu,hacker,admin" >> $CKS_DIR/group

# Q7: Runtime / Workload Security
kubectl run crypto-miner -n runtime-sec --image=busybox -- /bin/sh -c "while true; do echo 'Mining...'; sleep 2; done"

# Q8: ServiceAccount Security (Target: token-deploy)
kubectl create deploy token-deploy --image=nginx

# Q9: SBOM
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: webapp-pod
  namespace: default
spec:
  containers:
  - name: main-app
    image: nginx:alpine
  - name: vulnerable-sidecar
    image: log4j-vulnerable:latest
EOF

echo "✅ CKS Environment Ready!"
