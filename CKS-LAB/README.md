```bash

                                            ,--,                              
                  ,--.                   ,---.'|                              
  ,----..     ,--/  /| .--.--.           |   | :      ,---,           ,---,.  
 /   /   \ ,---,': / '/  /    '.         :   : |     '  .' \        ,'  .'  \ 
|   :     ::   : '/ /|  :  /`. /         |   ' :    /  ;    '.    ,---.' .' | 
.   |  ;. /|   '   , ;  |  |--`          ;   ; '   :  :       \   |   |  |: | 
.   ; /--` '   |  /  |  :  ;_            '   | |__ :  |   /\   \  :   :  :  / 
;   | ;    |   ;  ;   \  \    `.         |   | :.'||  :  ' ;.   : :   |    ;  
|   : |    :   '   \   `----.   \        '   :    ;|  |  ;/  \   \|   :     \ 
.   | '___ |   |    '  __ \  \  |        |   |  ./ '  :  | \  \ ,'|   |   . | 
'   ; : .'|'   : |.  \/  /`--'  /        ;   : ;   |  |  '  '--'  '   :  '; | 
'   | '/  :|   | '_\.'--'.     /         |   ,/    |  :  :        |   |  | ;  
|   :    / '   : |     `--'---'          '---'     |  | ,'        |   :   /   
 \   \ .'  ;   |,'                                 `--''          |   | ,'    
  `---`    '---'                                                  `----'      
                                                                              
                                                                                               
```
---

> **Disclaimer:** To protect your host system, control plane files are simulated in `/opt/cks-lab/`.

---

## Q1 - Admission Controller
**Task:** The cluster's API server is missing critical admission control plugins. 
1. Enable the `NodeRestriction` and `ImagePolicyWebhook` plugins on the API server.
2. An admission configuration file has been pre-staged at `/etc/kubernetes/image-config/admission-configuration.yaml`. Configure the API server to use it.
3. Modify the pre-staged configuration file to reject pods by default if the external webhook backend is unreachable.

*Note: You can access the control plane node via `minikube ssh`.*

**Solution**:
```bash
# 1. Edit the pre-staged config to enforce strict security (change defaultAllow: true to false)
vi /etc/kubernetes/image-config/admission-configuration.yaml

# 2. Modify the API Server Manifest
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Add/Modify under spec.containers.command:
# - --enable-admission-plugins=NodeRestriction,ImagePolicyWebhook
# - --admission-control-config-file=/etc/kubernetes/image-config/admission-configuration.yaml
# Ensure volumeMounts and volumes mapping /etc/kubernetes/image-config/ are active.
```

---

## Q2 - Kubeadm Upgrade
**Task: Upgrade the control plane node components (`kubeadm`, `kubelet`, `kubectl`) from `v1.30.0` to `v1.30.1`.

**Solution**:

```bash
apt-mark unhold kubeadm kubectl kubelet
apt-get update && apt-get install -y kubeadm=1.30.1-1.1
kubeadm upgrade apply v1.30.1
apt-get install -y kubelet=1.30.1-1.1 kubectl=1.30.1-1.1
systemctl daemon-reload && systemctl restart kubelet
```

---

## Q3 - Network Policy
**Context:**  
`kubectl config use-context minikube`


**Task:** Create a NetworkPolicy named `default-deny-all` in the `backend` namespace that denies all ingress and egress traffic by default.

**Solution:** 
```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: backend
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF
```

---

## Q4 - Falco Runtime Security
**Task:** A new security policy dictates that any read or write access to `/dev/mem` on the host must trigger a Falco alert. 
1. Append a custom rule to `/etc/falco/falco_rules.local.yaml` to detect this behavior. Set the priority to `WARNING`.
2. A deployment named `web-backend` in the `web` namespace has been flagged for violating this policy. Scale the deployment down to `0` replicas immediately.

*Note: You can access the host via `minikube ssh`.*

**Solution:**
```bash
# 1. Edit Falco rules on the node
minikube ssh
sudo vi /etc/falco/falco_rules.local.yaml
# Append the following:
- rule: Detect Memory Access
  desc: Alert when /dev/mem is accessed
  condition: open_read or open_write and fd.name = "/dev/mem"
  output: "Memory accessed (user=%user.name command=%proc.cmdline)"
  priority: WARNING
exit

# 2. Scale deployment on base terminal
kubectl scale deploy web-backend --replicas=0 -n web
```

---

## Q5 - Cilium Network Policy
**Task:** The cluster uses Cilium for CNI. Create a CiliumNetworkPolicy named restrict-dns in the app namespace. The policy must strictly restrict all egress traffic from pods in the app namespace so they can only communicate with the kube-dns pods in the kube-system namespace on UDP port 53.

**Solution:** 
```bash
cat <<EOF | kubectl apply -f -
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: restrict-dns
  namespace: app
spec:
  endpointSelector: {}
  egress:
  - toEndpoints:
    - matchLabels:
        k8s:io.kubernetes.pod.namespace: kube-system
        k8s-app: kube-dns
    toPorts:
    - ports:
      - port: "53"
        protocol: UDP
EOF
```

---

## Q6 - Istio mTLS
**Task:** The cluster has Istio installed. Enforce STRICT mutual TLS (mTLS) for all workloads across the entire cluster by creating a PeerAuthentication resource named default-strict-mtls in the istio-system namespace.

**Solution:** 
```bash
cat <<EOF | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default-strict-mtls
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
EOF
```

---

## Q7 - Dockerfile Security
**Task:** Inspect the Dockerfile at `/opt/cks-lab/Dockerfile`. Modify it so the container runs as a non-root user `appuser` (UID 1000) instead of root.

**Solution:** 
```bash
vi /opt/cks-lab/Dockerfile
# Add the following lines before CMD/ENTRYPOINT:
# RUN addgroup -S appgroup && adduser -S appuser -G appgroup -u 1000
# USER appuser
```

---

## Q8 - AppArmor & Seccomp
**Task:** An AppArmor profile named custom-profile has been loaded into the kernel of the control plane node.
Update the existing Deployment named secure-app in the prod namespace to utilize native Kubernetes security context fields (v1.30+):

1. Enforce the custom-profile AppArmor profile on the container.

2. Enforce the RuntimeDefault seccomp profile on the container.

**Solution:** 
```bash
# 1. Load the profile into the kernel (Run inside minikube ssh as root):
apparmor_parser -r -W /etc/apparmor.d/custom-profile

# 2. Configure the Deployment (Run on your Mac terminal):
kubectl edit deploy -n prod secure-app

Under spec.template.spec.containers[0].securityContext, add:

securityContext:
  appArmorProfile:
    type: Localhost
    localhostProfile: custom-profile
  seccompProfile:
    type: RuntimeDefault
```

---

## Q9 - Kube-bench Fixes
**Task:** A kube-bench report indicated that the kubelet on the control plane node is allowing unauthenticated API requests.
Reconfigure the node's Kubelet to delegate authorization to the Kubernetes API server using Webhooks. Ensure the Kubelet service successfully restarts.

Note: Access the node via minikube ssh.

**Solution:**
```bash
vi /var/lib/kubelet/config.yaml
# Change authorization.mode from AlwaysAllow to Webhook:
# authorization:
#   mode: Webhook
systemctl restart kubelet
```

---

## Q10 - SBOM (Software Bill of Materials)
**Task:** Generate a Software Bill of Materials (SBOM) in SPDX format for the image nginx:1.24. Save it to /opt/cks-lab/sbom.spdx on the host node. Use the bom CLI tool which is pre-installed on the node.

Inspect the pod multi-pod in the default namespace. A vulnerable library was detected in one of its containers. Remove the container named vulnerable-app from the pod.

Note: Access the node via minikube ssh for the BOM tool.

**Solution:** 
```bash
# 1. Generate BOM
minikube ssh "bom generate --image nginx:1.24 -o /opt/cks-lab/sbom.spdx"

# 2. Update Pod
kubectl get pod multi-pod -o yaml > pod.yaml
vi pod.yaml 
# Delete the entire container block for 'vulnerable-app'
kubectl replace --force -f pod.yaml
```

---

## Q11 - Pod Security Standards (PSS)
**Task:** Configure the frontend namespace to enforce the restricted Pod Security Standard (PSS).

**Solution:**
```bash
kubectl label ns frontend pod-security.kubernetes.io/enforce=restricted
```

---

## Q12 - ServiceAccount Token
**Task:** 
1. Modify the ServiceAccount db-sa in the database namespace to prevent it from automatically mounting API tokens into pods.

2. Create a new Pod named token-pod in the database namespace using the nginx image.

3. Configure the Pod to use the db-sa ServiceAccount, and manually mount its token using a projected volume at the path /var/run/secrets/tokens.

**Solution:** 
```bash
# 1. Disable automount
kubectl edit sa db-sa -n database 
# Add: automountServiceAccountToken: false

# 2 & 3. Create Pod with Projected Volume
kubectl run token-pod --image=nginx -n database --dry-run=client -o yaml > pod.yaml
vi pod.yaml

# Modify to match:
spec:
  serviceAccountName: db-sa
  containers:
  - name: token-pod
    image: nginx
    volumeMounts:
    - mountPath: /var/run/secrets/tokens
      name: token-vol
  volumes:
  - name: token-vol
    projected:
      sources:
      - serviceAccountToken:
          path: token
          expirationSeconds: 7200
          audience: api

kubectl apply -f pod.yaml
```

---

## Q13 - Auditing
**Task:** The cluster must persist an audit log of all API server requests. An audit policy file is staged at /etc/kubernetes/audit/audit-policy.yaml.
Configure the API server to use this policy file and write the audit logs to /var/log/k8s/audit.log. Ensure the API server mounts these host paths appropriately.

Note: Access the node via minikube ssh.

**Solution:** 
```bash
minikube ssh
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml

# Add Flags:
# - --audit-policy-file=/etc/kubernetes/audit/audit-policy.yaml
# - --audit-log-path=/var/log/k8s/audit.log

# Add under volumeMounts:
# - mountPath: /etc/kubernetes/audit
#   name: audit-config
#   readOnly: true
# - mountPath: /var/log/k8s
#   name: audit-log
#   readOnly: false

# Add under volumes:
# - hostPath:
#     path: /etc/kubernetes/audit
#     type: DirectoryOrCreate
#   name: audit-config
# - hostPath:
#     path: /var/log/k8s
#     type: DirectoryOrCreate
#   name: audit-log
```

---

## Q14 - SHA512SUM Verification
**Task:** A test binary named kube-apiserver-test and its expected SHA512 checksum file (kube-apiserver-test.sha512) are located in /usr/local/bin/ on the control plane node.
Verify the integrity of the binary. If the hash does not match, permanently remove the compromised binary.

Note: Access the node via minikube ssh.

**Solution:** 
```bash
minikube ssh
cd /usr/local/bin/
sha512sum -c kube-apiserver-test.sha512
# Output will say FAILED
sudo rm -f kube-apiserver-test*

```

---

## Q15 -
**Task:** The Deployment web-server in the dmz namespace is currently running httpd:2.4.49. Update the deployment image to httpd:2.4.58 to resolve a CRITICAL known vulnerability.

**Solution:** 
```bash
kubectl set image deploy/web-server httpd=httpd:2.4.58 -n dmz
```

---

## Q16 -
**Task:** Modify the Pod immutable-pod in the default namespace to enforce container immutability. Specifically, ensure its root filesystem is mounted as read-only.

**Solution:** 
```bash
kubectl get pod immutable-pod -o yaml > pod.yaml
vi pod.yaml 
# Under spec.containers[0].securityContext, add:
# readOnlyRootFilesystem: true
kubectl replace --force -f pod.yaml
```

---

## Q17 - Secrets Encryption at Rest
**Task:** Kubernetes Secrets are currently unencrypted in etcd.

The API server has a pre-staged EncryptionConfiguration file at /etc/kubernetes/encryption/encryption-config.yaml.

Generate a random 32-byte base64 key and add it to the configuration file using the secretbox provider.

Configure the API Server to utilize this configuration.

Note: Access the node via minikube ssh.

**Solution:** 
```bash
minikube ssh
sudo -i

# 1. Get the key
head -c 32 /dev/urandom | base64

# 2. Edit config
vi /etc/kubernetes/encryption/encryption-config.yaml
# Replace {RAND_KEY} with the generated string.

# 3. Edit API Server
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Add flag:
# - --encryption-provider-config=/etc/kubernetes/encryption/encryption-config.yaml
# (Ensure volume mounts for /etc/kubernetes/encryption exist)
exit
```
## Q18 
**Task:** Create a Kubernetes TLS secret named secure-tls in the default namespace. Use the raw certificate and key files located at /opt/cks-lab/tls.crt and /opt/cks-lab/tls.key on the base terminal.

```bash
kubectl create secret tls secure-tls --cert=/opt/cks-lab/tls.crt --key=/opt/cks-lab/tls.key -n default
```

## Q19
**Task:** An Ingress resource named secure-ingress exists in the default namespace. Currently, it accepts HTTP traffic. Update the Ingress configuration to strictly enforce an SSL redirect.

```bash
kubectl edit ingress secure-ingress -n default
# Add under metadata.annotations:
#   nginx.ingress.kubernetes.io/ssl-redirect: "true"
```

## Q20
**Task:** A node forensics audit revealed that an unauthorized user (unauthorized_user) has been attached to the Docker daemon group, and the Docker socket (/var/run/docker.sock) is incorrectly owned by this user.
Remove the user from the docker group and restore ownership of the socket to root.

Note: Access the node via minikube ssh.

```bash
minikube ssh
sudo -i
gpasswd -d unauthorized_user docker
chown root:docker /var/run/docker.sock
exit
```

---

### Question 21 | Weight: 5%

**Context:**  
`kubectl config use-context minikube`

**Task:**  
You need to audit an older image before it is approved for use in the cluster.
1. Use `trivy` to scan the image `httpd:2.4.49` for `CRITICAL` vulnerabilities. 
2. Save the scan results in `json` format to `/opt/cks-lab/trivy-report.json` on the base terminal.

<details><summary><b>Reveal Solution</b></summary>

```bash
trivy image --severity CRITICAL --format json --output /opt/cks-lab/trivy-report.json httpd:2.4.49
```