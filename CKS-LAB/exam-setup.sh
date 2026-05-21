#!/bin/bash
# exam-setup.sh - Prepares the mock environment for the CKS Simulator

echo "Setting up CKS Simulator Environment..."

# Create base directory
mkdir -p /opt/cks-lab/

# Q1: Admission Controller / Q13: Auditing / Q17: Secrets
mkdir -p /etc/kubernetes/manifests/ /etc/kubernetes/enc/ /var/log/k8s/
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

cat <<EOF > /etc/kubernetes/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: Metadata
EOF

cat <<EOF > /etc/kubernetes/enc/encryption.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: $(head -c 32 /dev/urandom | base64)
      - identity: {}
EOF

# Q4: Falco Runtime Security
mkdir -p /var/log/
cat <<EOF > /var/log/falco.log
10:00:00.000000000: Warning Sensitive file opened for reading by non-trusted program (user=root program=cat command=cat /etc/shadow file=/etc/shadow container_id=host image=<NA>)
10:05:00.000000000: Notice A shell was spawned in a container with an attached terminal (user=root container_id=123456 pod=hacker-pod namespace=web shell=/bin/bash)
EOF

# Q7: Dockerfile Security
cat <<EOF > /opt/cks-lab/Dockerfile
FROM alpine:3.18
RUN apk add --no-cache curl
CMD ["curl", "-s", "http://example.com"]
EOF

# Q9: Kube-bench Fixes
mkdir -p /var/lib/kubelet/
cat <<EOF > /var/lib/kubelet/config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
authentication:
  anonymous:
    enabled: false
  webhook:
    cacheTTL: 0s
    enabled: true
  x509:
    clientCAFile: /etc/kubernetes/pki/ca.crt
authorization:
  mode: AlwaysAllow
EOF

# Q14: SHA512SUM Verification
echo "fake-binary-content-for-testing" > /opt/cks-lab/kube-apiserver
echo "invalid-checksum  kube-apiserver" > /opt/cks-lab/kube-apiserver.sha512

echo "Setup complete. Simulated files are in /opt/cks-lab/ and relevant /etc/kubernetes/ paths."
