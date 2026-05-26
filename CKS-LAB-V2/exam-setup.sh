#!/bin/bash
# exam-setup.sh - CKS Simulator Version 2

echo "🚀 Setting up CKS Environment Version 2..."

CKS_DIR="/opt/cks-lab-v2"
sudo mkdir -p $CKS_DIR
sudo chmod 777 $CKS_DIR

NAMESPACES="qa frontend-ns restricted-ns"
for ns in $NAMESPACES; do
    kubectl delete ns $ns --wait=false 2>/dev/null
done
sleep 2
for ns in $NAMESPACES; do
    kubectl create ns $ns 2>/dev/null
done

# Q1 & Q16: API Server, Kubelet, and etcd simulated files
cat <<EOF > $CKS_DIR/kube-apiserver.yaml
apiVersion: v1
kind: Pod
metadata: { name: kube-apiserver, namespace: kube-system }
spec:
  containers:
  - command:
    - kube-apiserver
    - --anonymous-auth=true
    - --authorization-mode=AlwaysAllow
    - --enable-admission-plugins=AlwaysAdmit
EOF

cat <<EOF > $CKS_DIR/kubelet-config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
authentication:
  anonymous:
    enabled: true
authorization:
  mode: AlwaysAllow
EOF

cat <<EOF > $CKS_DIR/etcd.yaml
apiVersion: v1
kind: Pod
spec:
  containers:
  - command:
    - etcd
    - --client-cert-auth=false
EOF

# Q2: TLS Secret Target
kubectl create deploy web-tls -n default --image=nginx

# Q3: Dockerfile & Deployment
mkdir -p /tmp/cks-q3
cat <<EOF > /tmp/cks-q3/Dockerfile
FROM ubuntu:20.04
RUN apt-get update
USER root
CMD ["sleep", "3600"]
EOF
kubectl create deploy docker-deploy -n default --image=nginx

# Q4: Falco /dev/mem Target
kubectl create deploy mem-hacker -n default --image=busybox --replicas=1 -- /bin/sh -c "cat /dev/mem; sleep 3600"

# Q5: Container Security Context
kubectl create deploy immutable-deploy -n default --image=nginx

# Q6: Audit Logging configuration stub
touch $CKS_DIR/audit-policy.yaml

# Q7: Network Policy Targets
kubectl run backend-app -n qa --image=nginx
kubectl run frontend-pod -n frontend-ns --image=nginx

# Q8: Ingress setup
kubectl create deploy https-app -n default --image=nginx
kubectl expose deploy https-app --port=80

# Q9: Disable API auto-mounting
kubectl create sa vault-sa
kubectl create deploy vault-sa-deploy -n default --image=nginx
kubectl set serviceaccount deploy vault-sa-deploy vault-sa

# Q11: SPDX / Bom tool
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata: { name: crypto-pod, namespace: default }
spec:
  containers:
  - name: app
    image: nginx:alpine
  - name: libcrypto-container
    image: alpine:3.19.1
EOF

# Q12: Restricted Pod Security Standard
kubectl label ns restricted-ns pod-security.kubernetes.io/enforce=restricted
kubectl create deploy violator-deploy -n restricted-ns --image=nginx 2>/dev/null || true
# Bypass admission controller for setup by applying raw pod without SC
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: violator-deploy, namespace: restricted-ns }
spec:
  replicas: 1
  selector: { matchLabels: { app: violator } }
  template:
    metadata: { labels: { app: violator } }
    spec:
      containers:
      - name: nginx
        image: nginx
EOF

# Q13: Secure Docker Daemon
echo "root:x:0:" > $CKS_DIR/group
echo "docker:x:999:ubuntu,devuser" >> $CKS_DIR/group
touch $CKS_DIR/docker.sock
chmod 777 $CKS_DIR/docker.sock

# Q15: ImagePolicyWebhook Config
cat <<EOF > $CKS_DIR/admission-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
- name: ImagePolicyWebhook
  configuration:
    imagePolicy:
      kubeConfigFile: /etc/kubernetes/admission/kubeconfig.yaml
      allowTTL: 50
      denyTTL: 50
      retryBackoff: 500
      defaultAllow: true
EOF

echo "✅ Environment Ready!"
