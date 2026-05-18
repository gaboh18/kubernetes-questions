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

Disclaimer: In a real CKS exam, you edit live files like /etc/kubernetes/manifests/kube-apiserver.yaml. 
To prevent destroying your local environment, this simulator uses /opt/cks-lab/ to represent your host's filesystem.

<a id="question-1"></a>

## Question 1 - Pod Security / Hardening

In namespace `default`, Deployment `restricted-deploy` violates the restricted Pod Security Standard.
Your task:

Modify the deployment to meet the following requirements:
- Pod Level: Must run as a non-root user.
- Container Level: Privilege escalation must be disabled.
- Container Level: Seccomp profile must be set to RuntimeDefault.
- Container Level: ALL capabilities must be dropped.

```bash
Solution:
kubectl edit deploy restricted-deploy
(Add the following to the spec tree):
    spec:
      securityContext:
        runAsNonRoot: true
      containers:
      - name: nginx
        securityContext:
          allowPrivilegeEscalation: false
          seccompProfile:
            type: RuntimeDefault
          capabilities:
            drop:
            - ALL
```
---

<a id="question-2"></a>
## Question 2 - Cluster Hardening (API Server)

The API server manifest located at /opt/cks-lab/kube-apiserver.yaml contains insecure flags.
Your task:
- Disable anonymous authentication.
- Set the authorization mode to Node and RBAC.

Solution:

```bash
vi /opt/cks-lab/kube-apiserver.yaml
(Change the existing flags to):
    - --anonymous-auth=false
    - --authorization-mode=Node,RBAC
```
---

<a id="question-3"></a>
## Question 3 - Audit Logging

Enable audit logging on the API server manifest located at /opt/cks-lab/kube-apiserver.yaml.
Your task:

- Add the flag to point to the policy file: /etc/kubernetes/audit/policy.yaml
- Add the flag to set the log path to: /var/log/kubernetes/audit.log
(Note: For the simulator, you only need to add the flags, you do not need to create the volume mounts, though in the real exam, missing the mount = fail!).

Solution:

```bash
vi /opt/cks-lab/kube-apiserver.yaml
(Add under the command section):
    - --audit-policy-file=/etc/kubernetes/audit/policy.yaml
    - --audit-log-path=/var/log/kubernetes/audit.log
```
---

<a id="question-4"></a>
## Question 4 - Admission Controller (ImagePolicyWebhook)

You need to enable the ImagePolicyWebhook admission controller.
The configuration file is located at /opt/cks-lab/admission-kubeconfig.yaml.
Your task
:
Edit /opt/cks-lab/kube-apiserver.yaml to:
- Enable the ImagePolicyWebhook plugin.
- Provide the path to the admission control config file.

Solution:
```bash
vi /opt/cks-lab/kube-apiserver.yaml
(Update/Add the following flags):
    - --enable-admission-plugins=NodeRestriction,ImagePolicyWebhook
    - --admission-control-config-file=/opt/cks-lab/admission-kubeconfig.yaml
```
---

<a id="question-5"></a>
## Question 5 - Network Policies

In namespace net-block, communication is blocked. Policies already exist. You are NOT allowed to edit or delete the NetworkPolicies.
Your task:
Update the labels on the existing Pods (frontend, backend, database) so they comply with the existing policies to allow the communication chain: frontend -> backend -> database.

Solution:

```bash
kubectl label pod frontend -n net-block app=frontend --overwrite
kubectl label pod backend -n net-block app=backend --overwrite
kubectl label pod database -n net-block app=db --overwrite
```

--- 

<a id="question-6"></a>
## Question 6 - Docker / Node Hardening

A node has been insecurely configured. 
Youir task:

- Edit /opt/cks-lab/daemon.json and remove the insecure TCP socket exposed on 0.0.0.0:2375.
- Edit /opt/cks-lab/group and remove the user 'hacker' from the docker group.

Solution:
```bash
vi /opt/cks-lab/daemon.json
(Remove "tcp://0.0.0.0:2375" from the hosts array)

vi /opt/cks-lab/group
(Change docker:x:999:ubuntu,hacker,admin TO docker:x:999:ubuntu,admin)

```
---

<a id="question-7"></a>
## Question 7 - Runtime / Workload Security

A misbehaving workload is running in the runtime-sec namespace.
Your task:

Identify the malicious pod (it is mining crypto) and permanently isolate it by deleting it from the cluster.

Solution:

```bash
kubectl get pods -n runtime-sec
kubectl delete pod crypto-miner -n runtime-sec
```

---

<a id="question-8"></a>
## Question 8 - ServiceAccount Security

Deployment token-deploy in the default namespace auto-mounts the default ServiceAccount token insecurely.
Your task:

- Disable the auto-mounting of the default token.
- Manually mount a projected service account token to the path /var/run/secrets/tokens.

Solution:

```bash
kubectl edit deploy token-deploy
(Add automountServiceAccountToken and the projected volume):
    spec:
      automountServiceAccountToken: false
      containers:
      - image: nginx
        name: nginx
        volumeMounts:
        - mountPath: /var/run/secrets/tokens
          name: vault-token
      volumes:
      - name: vault-token
        projected:
          sources:
          - serviceAccountToken:
              path: vault-token
              expirationSeconds: 7200
              audience: vault
```bash

---

<a id="question-9"></a>
## Question 9 - SBOM and Vulnerability Scanning

Pod webapp-pod in the default namespace has multiple containers. You ran an SBOM/Trivy scan and identified that the container named 'vulnerable-sidecar' has critical vulnerabilities.
Your task:

Modify the running pod (or extract, edit, and replace it) to remove ONLY the 'vulnerable-sidecar' container.

Solution:

```bash
kubectl get pod webapp-pod -o yaml > /tmp/webapp.yaml
vi /tmp/webapp.yaml
(Delete the block for the vulnerable-sidecar container)
kubectl delete pod webapp-pod --force
kubectl apply -f /tmp/webapp.yaml
```
--- 

<a id="question-10"></a>
### Question 10 - Istio mTLS

Your cluster uses Istio. 
Your task:

- Label the namespace istio-prod to enable automatic sidecar injection.
- Since Istio might not be installed in this simulator, write a valid Istio PeerAuthentication YAML manifest to /opt/cks-lab/mtls.yaml that enforces STRICT mTLS for the entire istio-prod namespace.

Solution:

```bash
kubectl label ns istio-prod istio-injection=enabled

cat <<EOF > /opt/cks-lab/mtls.yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-prod
spec:
  mtls:
    mode: STRICT
EOF

```

--- 
