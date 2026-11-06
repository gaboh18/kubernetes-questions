# CKS mock exam: step-by-step solutions

Use this guide after attempting [the questions](EXAM.md). Each task below has its own procedure and a final check. Commands change your current attempt; run only the task you intend to solve.

## Before following the solutions

Start in the **`CKS-LAB/secon_version` folder on your Mac**, with an existing, successfully started exam. Do not run `start` again to open this guide: that creates a new attempt.

In your Mac terminal, define this shortcut once:

```bash
k() { ./k8s-sim.sh kubectl "$@"; }
k get nodes
```

`k` means the simulator's guarded kubectl wrapper. It targets `cks-lab` even when your current kubectl context points elsewhere. Define it again if you open a new Mac terminal. If `get nodes` fails, fix cluster access before following the workload solutions.

| Label in this guide | Where to run the commands |
| --- | --- |
| **Mac** | Your terminal in `CKS-LAB/secon_version`; `k` is available here. |
| **Inside cks-lab** | After running `./k8s-sim.sh ssh` from your Mac. Use plain `kubectl` here. |
| **External lab** | A separate Linux host/cluster that you provide. These tasks cannot be completed fully in the default Minikube setup. |

Mac answer files live in `../.cks-state/jumpbox/exam/`. Node configuration copies live in `/opt/cks-lab/exam/`. When a wrapper command takes a file argument, it resolves from the parent `CKS-LAB` folder; this is why the TLS command below uses `.cks-state/...` while `vim` uses `../.cks-state/...`.

For Vim: press `i` to edit, `Esc` to leave insert mode, then type `:wq` and press Enter to save and close. Type `:q!` to close without saving. Search with `/text` followed by Enter; press `n` for the next match.

Tasks 1, 6, 15 and 16 edit **copies only**. Never copy these files into `/etc/kubernetes/manifests` or overwrite the active kubelet configuration. The same API server copy is shared by tasks 6, 15 and 16; preserve your earlier changes.

## Find a solution

| Task | Solution | Run from |
| --- | --- | --- |
| 01 | [Component authentication](#task-01--component-authentication) | SSH node |
| 02 | [TLS Secret](#task-02--restore-a-tls-workload) | Mac |
| 03 | [Image and Deployment hardening](#task-03--harden-an-image-and-deployment) | Mac |
| 04 | [Runtime investigation](#task-04--investigate-and-contain-a-workload) | Mac; Falco externally |
| 05 | [Container immutability](#task-05--enforce-container-immutability) | Mac |
| 06 | [Audit configuration](#task-06--configure-api-auditing) | SSH node |
| 07 | [NetworkPolicy](#task-07--restrict-namespace-ingress) | Mac |
| 08 | [HTTPS Ingress](#task-08--expose-an-application-over-https) | Mac; external controller required |
| 09 | [Projected token](#task-09--control-serviceaccount-token-mounts) | Mac |
| 10 | [Worker upgrade](#task-10--upgrade-a-worker-node) | External kubeadm lab |
| 11 | [SBOM investigation](#task-11--identify-an-image-through-its-sbom) | Mac; Trivy required |
| 12 | [Restricted Deployment](#task-12--repair-a-pod-security-violation) | Mac |
| 13 | [Docker access](#task-13--remove-unauthorized-docker-access) | External Docker host |
| 14 | [Cilium authentication](#task-14--require-cilium-mutual-authentication) | External Cilium lab |
| 15 | [Image admission](#task-15--make-image-admission-fail-closed) | SSH node |
| 16 | [API server access](#task-16--harden-api-server-access) | SSH node |

---

## Task 01 | Component authentication

**Where:** inside `cks-lab`. **Result:** corrected kubelet and etcd configuration copies. This task receives automatic CONFIG checks; run `./k8s-sim.sh score --task 1` from your Mac after saving.

### 1. Open the kubelet copy

**Mac:**

```bash
./k8s-sim.sh ssh
```

**Inside cks-lab:**

```bash
vim /opt/cks-lab/exam/kubelet-config.yaml
```

Find the existing `authentication` and `authorization` sections. Change their fields to match the following, preserving any other fields, such as the existing client CA path. Do not add duplicate top-level sections.

```yaml
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
authorization:
  mode: Webhook
```

`anonymous.enabled: false` turns off unauthenticated access. The webhook settings delegate authentication and authorization decisions to Kubernetes.

### 2. Open the etcd copy

```bash
vim /opt/cks-lab/exam/etcd.yaml
```

Under `spec.containers`, locate the etcd container's existing `command` list. Ensure it contains:

```yaml
- --client-cert-auth=true
```

The client CA argument is deliberately incorrect. Change `--trusted-ca-file` to the same CA path shown by the unchanged `--peer-trusted-ca-file` argument. Preserve the existing server certificate/key arguments, peer TLS and data paths. Inspect the arguments first:

```bash
grep -E -- 'client-cert-auth|trusted-ca-file|cert-file|key-file|peer-|data-dir' /opt/cks-lab/exam/etcd.yaml
```

Change the existing `--client-cert-auth=false` entry to `true` and replace the incorrect client CA path; do not add conflicting duplicate flags. Both etcd faults must be repaired. All three kubelet fields above also start wrong in a fresh revision-2 exam.

### 3. Check and return to your Mac

```bash
grep -A 12 '^authentication:' /opt/cks-lab/exam/kubelet-config.yaml
grep -A 3 '^authorization:' /opt/cks-lab/exam/kubelet-config.yaml
kubectl get nodes
exit
```

**Done when:** the saved copy has anonymous authentication disabled, webhook authentication enabled and Webhook authorization; etcd's copy requires client certificates with the existing trusted CA. The live nodes should remain Ready because you edited copies. Testing new component behavior requires a separate disposable Linux cluster. [etcd client TLS reference](https://etcd.io/docs/v3.6/op-guide/security/).

---

## Task 02 | Restore a TLS workload

**Where:** Mac. **Result:** the missing Secret exists and `certificate-reader` has an available replica.

### 1. Confirm why the Pod is blocked

```bash
k get pods -n exam-tls
k describe deployment certificate-reader -n exam-tls
k get events -n exam-tls --sort-by=.metadata.creationTimestamp
```

The volume refers to the missing Secret `site-tls`. Keep that volume and its `/tls` mount.

### 2. Create or update the Secret from the supplied files

```bash
k create secret tls site-tls -n exam-tls \
  --cert=.cks-state/jumpbox/tls.crt \
  --key=.cks-state/jumpbox/tls.key \
  --dry-run=client -o yaml | k apply -f -
```

The command reads the original certificate and matching key. Kubernetes can now mount them in the waiting Pod.

### 3. Verify recovery

```bash
k rollout status deployment/certificate-reader -n exam-tls --timeout=180s
k get secret site-tls -n exam-tls
k get deployment certificate-reader -n exam-tls
k exec -n exam-tls deployment/certificate-reader -- ls -l /tls
```

**Done when:** the Secret type is `kubernetes.io/tls`, the Deployment shows `1/1` Ready and `/tls` contains `tls.crt` and `tls.key`. The existing mount must still be read-only. Do not print the private key.

---

## Task 03 | Harden an image and Deployment

**Where:** Mac. **Result:** the Dockerfile uses `nobody`; the running container uses UID `65535` and a read-only root filesystem.

### 1. Edit the Dockerfile

```bash
vim ../.cks-state/jumpbox/exam/Dockerfile
```

For the supplied single-stage file, the complete result is:

```dockerfile
FROM busybox:1.37
USER nobody
CMD ["sleep", "86400"]
```

If you have added image stages yourself, put `USER nobody` in the final stage. The image username and the Deployment's numeric UID are separate requirements.

### 2. Apply a readable YAML patch

Run this complete command, including the opening and closing single quotes:

```bash
k patch deployment build-app -n exam-build --type=strategic --patch '
spec:
  template:
    spec:
      containers:
      - name: app
        securityContext:
          runAsUser: 65535
          readOnlyRootFilesystem: true
          privileged: false
          allowPrivilegeEscalation: false
'
```

The container name `app` tells the strategic merge patch which existing container to update. It preserves the image and command. [Patch behavior](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/update-api-object-kubectl-patch/).

### 3. Verify the running container

```bash
k rollout status deployment/build-app -n exam-build --timeout=180s
k exec -n exam-build deployment/build-app -- id -u
k exec -n exam-build deployment/build-app -- awk '$2 == "/" {print $4}' /proc/mounts
k get deployment build-app -n exam-build
```

**Done when:** `id -u` prints `65535`, the root mount options include `ro`, and the Deployment is `1/1` Ready. The Dockerfile's final user must be `nobody`. This local task does not rebuild or replace the Deployment image. [Container security settings](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/).

---

## Task 04 | Investigate and contain a workload

**Where:** Mac. **Result:** the actual offending Deployment is scaled to zero and the required evidence files are saved.

### 1. Read the supplied events

```bash
python3 - <<'PY'
import json
from pathlib import Path
for line in Path('../.cks-state/jumpbox/exam/runtime-events.jsonl').read_text().splitlines():
    event = json.loads(line)['output_fields']
    print(event['k8s.ns.name'], event['k8s.pod.name'], event['fd.name'])
PY
```

Find the line whose file is `/dev/mem`. The Pod name varies between attempts.

### 2. Trace that Pod's owner

The next command selects the Pod from the event file; it does not guess its name:

```bash
POD=$(python3 - <<'PY'
import json
from pathlib import Path
events = [json.loads(line)['output_fields'] for line in
          Path('../.cks-state/jumpbox/exam/runtime-events.jsonl').read_text().splitlines()]
matches = [e['k8s.pod.name'] for e in events if e['fd.name'] == '/dev/mem']
assert len(matches) == 1, 'Expected exactly one offending Pod; inspect the evidence.'
print(matches[0])
PY
)
RS=$(k get pod "$POD" -n exam-runtime -o jsonpath='{.metadata.ownerReferences[?(@.kind=="ReplicaSet")].name}')
DEPLOYMENT=$(k get replicaset "$RS" -n exam-runtime -o jsonpath='{.metadata.ownerReferences[?(@.kind=="Deployment")].name}')
printf 'Pod: %s\nReplicaSet: %s\nDeployment: %s\n' "$POD" "$RS" "$DEPLOYMENT"
```

The ownership chain is Pod → ReplicaSet → Deployment. Confirm that all three printed names are populated before continuing. If the named Pod was replaced since the event capture, locate its original ReplicaSet and owner from the captured Pod-name prefix and existing ReplicaSets rather than selecting another workload arbitrarily.

### 3. Save your finding, then contain the Deployment

```bash
python3 - "$POD" "$DEPLOYMENT" <<'PY'
import json, sys
from pathlib import Path
assert sys.argv[1] and sys.argv[2], 'Missing Pod or Deployment name.'
finding = {'namespace': 'exam-runtime', 'pod': sys.argv[1], 'deployment': sys.argv[2]}
Path('../.cks-state/jumpbox/exam/incident.json').write_text(json.dumps(finding, indent=2) + '\n')
PY
k scale deployment "$DEPLOYMENT" -n exam-runtime --replicas=0
k wait --for=delete pod -n exam-runtime -l "app=$DEPLOYMENT" --timeout=180s
k get deployments -n exam-runtime
```

Only the identified Deployment should show zero desired replicas. The other two must remain available.

### 4. Write the Falco rule

```bash
cat > ../.cks-state/jumpbox/exam/falco_rules.local.yaml <<'YAML'
- rule: Memory device opened
  desc: Detect read or write opens of the memory device
  condition: (open_read or open_write) and fd.name = "/dev/mem"
  output: "Memory device opened (user=%user.name command=%proc.cmdline file=%fd.name)"
  priority: WARNING
YAML
```

`open_read` and `open_write` come from the [default Falco macros](https://falco.org/docs/reference/rules/default-macros/). On a separate host with Falco installed, copy your file to `/tmp/cks-memory-rule.yaml` and validate it together with that installation's base rules:

```bash
sudo falco --validate /etc/falco/falco_rules.yaml --validate /tmp/cks-memory-rule.yaml
```

Adjust the base rules path to the installed ruleset if necessary. Validation should finish without rule errors. [Falco validation arguments](https://falco.org/docs/reference/daemon/cli-arguments/).

**Done locally when:** `incident.json` matches the captured offending Pod and its owner, only that Deployment is stopped and the rule file exists. This earns at most 3 of the task's 7 points automatically. The other 4 require actual Falco rule/alert verification in an external runtime lab; replayed events do not test the engine.

---

## Task 05 | Enforce container immutability

**Where:** Mac. **Result:** UID `30000`, read-only root filesystem and a healthy Deployment.

### 1. Patch the application container

```bash
k patch deployment immutable-app -n exam-immutable --type=strategic --patch '
spec:
  template:
    spec:
      containers:
      - name: app
        securityContext:
          runAsUser: 30000
          readOnlyRootFilesystem: true
          privileged: false
          allowPrivilegeEscalation: false
'
```

### 2. Check the actual runtime settings

```bash
k rollout status deployment/immutable-app -n exam-immutable --timeout=180s
k exec -n exam-immutable deployment/immutable-app -- id -u
k exec -n exam-immutable deployment/immutable-app -- awk '$2 == "/" {print $4}' /proc/mounts
k get deployment immutable-app -n exam-immutable
```

**Done when:** the UID is `30000`, root mount options include `ro`, and the Deployment is `1/1` Ready. Editing a template without a successful rollout is insufficient.

---

## Task 06 | Configure API auditing

**Where:** inside `cks-lab`. **Result:** an all-request Metadata policy plus flags and mounts in the copied API server manifest. Automatic CONFIG checks; live enforcement is not tested.

### 1. Connect and write the policy

**Mac:**

```bash
./k8s-sim.sh ssh
```

**Inside cks-lab:**

```bash
cat > /opt/cks-lab/audit/audit-policy.yaml <<'YAML'
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: Metadata
YAML
```

This rule covers every request and records metadata without request/response bodies. It includes operations on Secrets without recording their values.

### 2. Add the audit arguments

```bash
vim /opt/cks-lab/exam/kube-apiserver.yaml
```

Find the API server container's existing `command:` list and add these arguments with the same indentation as its other arguments. Update existing entries instead of duplicating them.

```yaml
- --audit-policy-file=/opt/cks-lab/audit/audit-policy.yaml
- --audit-log-path=/var/log/k8s/audit.log
- --audit-log-maxbackup=2
- --audit-log-maxage=7
- --audit-log-maxsize=10
```

### 3. Add the two mounts and corresponding volumes

In the API server container's **existing `volumeMounts:` list**, append:

```yaml
- name: cks-audit-policy
  mountPath: /opt/cks-lab/audit
  readOnly: true
- name: cks-audit-logs
  mountPath: /var/log/k8s
  readOnly: false
```

In the Pod's **existing `spec.volumes:` list**, append:

```yaml
- name: cks-audit-policy
  hostPath:
    path: /opt/cks-lab/audit
    type: Directory
- name: cks-audit-logs
  hostPath:
    path: /var/log/k8s
    type: DirectoryOrCreate
```

These are list entries, not complete manifests. Preserve all existing certificate mounts, volumes and API server flags. The policy path inside the container must match the flag; the log directory needs a writable mount.

### 4. Review the saved copy

```bash
cat /opt/cks-lab/audit/audit-policy.yaml
grep -n -E 'audit-|cks-audit|/var/log/k8s' /opt/cks-lab/exam/kube-apiserver.yaml
kubectl get nodes
exit
```

**Done locally when:** the policy, five flags and both mount/volume pairs are correct. There will be no new audit log from this file-only exercise. On a disposable live control plane, verify actual Metadata events and rotation after applying its real configuration. [Audit configuration reference](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/).

---

## Task 07 | Restrict namespace ingress

**Where:** Mac. **Result:** only the allowed namespace can reach the backend on TCP/8080.

### 1. Apply the two policies

```bash
k apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: exam-backend
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-client-namespace
  namespace: exam-backend
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: exam-allowed
    ports:
    - protocol: TCP
      port: 8080
YAML
```

The first policy isolates every backend Pod for ingress. The second adds one allowed source and destination port for `app=api`. Neither policy restricts egress.

### 2. Find the backend Pod IP and confirm healthy test endpoints

```bash
k get pods -n exam-backend -o wide
k get pod probe -n exam-allowed
k get pod probe -n exam-denied
BACKEND_IP=$(k get pod -n exam-backend -l app=api -o jsonpath='{.items[0].status.podIP}')
printf 'Backend IP: %s\n' "$BACKEND_IP"
```

All three `probe` Pods and the backend must be running. Test the Pod IP so DNS policy does not affect the result.

### 3. Test allowed and blocked sources separately

```bash
k exec -n exam-allowed probe -- wget -q -T 3 -O- "http://$BACKEND_IP:8080"
```

Expected: `cks-network-ok`.

```bash
k exec -n exam-denied probe -- wget -T 3 -O- "http://$BACKEND_IP:8080"
k exec -n exam-backend probe -- wget -T 3 -O- "http://$BACKEND_IP:8080"
```

Expected: both requests time out and return nonzero. A missing Pod, failed `kubectl exec`, or refused connection from a stopped backend is not evidence of correct filtering.

**Done when:** the allowed request succeeds, the other two time out, and workloads remain healthy. If unwanted traffic still succeeds, inspect `k get networkpolicy -n exam-backend -o yaml`; another allow policy can add access.

---

## Task 08 | Expose an application over HTTPS

**Where:** Mac, with a separately installed controller. **Result:** trusted HTTPS and an HTTP redirect. This task is manual/external.

The following worked example uses **Traefik**, an IngressClass named `traefik`, entrypoints named `web`/`websecure`, and its Kubernetes CRD provider. It assumes Traefik is installed in this lab cluster; it does not install or replace your controller. For a different controller, keep the Ingress host/backend/TLS settings and use its redirect configuration.

### 1. Check the prerequisites

```bash
k get ingressclass
k get crd middlewares.traefik.io
k get service web -n exam-ingress
```

If the class or CRD is missing, stop this worked example until the required controller is provided.

### 2. Generate a certificate for this task and create its Secret

The shared `cks.example.com` certificate has a different host name, so generate a separate one for `exam.cks.local`:

```bash
openssl req -x509 -nodes -newkey rsa:2048 -days 7 \
  -keyout ../.cks-state/jumpbox/exam/ingress.key \
  -out ../.cks-state/jumpbox/exam/ingress.crt \
  -subj '/CN=exam.cks.local' \
  -addext 'subjectAltName=DNS:exam.cks.local'
chmod 600 ../.cks-state/jumpbox/exam/ingress.key
k create secret tls web-tls -n exam-ingress \
  --cert=.cks-state/jumpbox/exam/ingress.crt \
  --key=.cks-state/jumpbox/exam/ingress.key \
  --dry-run=client -o yaml | k apply -f -
```

### 3. Create the redirect and HTTPS routes

```bash
k apply -f - <<'YAML'
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: redirect-https
  namespace: exam-ingress
spec:
  redirectScheme:
    scheme: https
    port: "443"
    permanent: true
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-http
  namespace: exam-ingress
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
    traefik.ingress.kubernetes.io/router.middlewares: exam-ingress-redirect-https@kubernetescrd
spec:
  ingressClassName: traefik
  rules:
  - host: exam.cks.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web
            port:
              number: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-https
  namespace: exam-ingress
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
spec:
  ingressClassName: traefik
  tls:
  - hosts:
    - exam.cks.local
    secretName: web-tls
  rules:
  - host: exam.cks.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web
            port:
              number: 80
YAML
```

Traefik's redirect belongs to the HTTP route; the HTTPS route serves the TLS backend. [Ingress annotations](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/ingress/) and [RedirectScheme settings](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/redirectscheme/).

### 4. Test through the controller

Find the actual controller Service and namespace:

```bash
k get services -A
```

If it is `traefik` in namespace `traefik` and exposes ports 80/443, run:

```bash
k port-forward -n traefik service/traefik 18080:80 18443:443
```

Adjust the namespace/Service to the actual installation. Leave the forwarding terminal open. In a **second Mac terminal in `secon_version`**, test:

```bash
curl -I --resolve exam.cks.local:18080:127.0.0.1 http://exam.cks.local:18080/
curl --cacert ../.cks-state/jumpbox/exam/ingress.crt \
  --connect-to exam.cks.local:443:127.0.0.1:18443 https://exam.cks.local/
```

**Done when:** HTTP returns a redirect to `https://exam.cks.local/` and HTTPS returns `cks-network-ok` without disabling certificate checks. The URL preserves the host name for SNI and identity verification. Press Ctrl+C in the first terminal to end port forwarding. A saved Ingress alone does not prove the task works.

---

## Task 09 | Control ServiceAccount token mounts

**Where:** Mac. **Result:** no automatic token mount, with one explicitly configured read-only projected token.

### 1. Disable automount on the ServiceAccount

```bash
k patch serviceaccount app-sa -n exam-tokens --type=merge --patch '{"automountServiceAccountToken":false}'
```

### 2. Inspect and recreate the misconfigured Pod

The supplied Pod has automount enabled and the wrong projection audience, lifetime, filename, mount directory and mount access. Those Pod fields require recreation. Inspect it, then remove only this exercise Pod:

```bash
k get pod token-client -n exam-tokens -o yaml
k delete pod token-client -n exam-tokens --wait=true
```

Create its corrected replacement with the same image and command:

```bash
k apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: token-client
  namespace: exam-tokens
spec:
  serviceAccountName: app-sa
  automountServiceAccountToken: false
  containers:
  - name: app
    image: busybox:1.37
    command: ["sleep", "86400"]
    volumeMounts:
    - name: api-token
      mountPath: /var/run/secrets/tokens
      readOnly: true
  volumes:
  - name: api-token
    projected:
      sources:
      - serviceAccountToken:
          path: token
          audience: cks-lab
          expirationSeconds: 3600
YAML
```

Deleting and recreating this one Pod removes its previously injected automatic token volume as well as replacing the incorrect explicit projection. Do not delete the namespace or ServiceAccount.

### 3. Verify without printing the token

```bash
k wait --for=condition=Ready pod/token-client -n exam-tokens --timeout=180s
k get serviceaccount app-sa -n exam-tokens -o yaml
k get pod token-client -n exam-tokens -o yaml
k exec -n exam-tokens token-client -- test -s /var/run/secrets/tokens/token
```

The last command should return successfully with no output. Check the two YAML objects for `automountServiceAccountToken: false`, and the Pod for the requested audience, lifetime and read-only mount.

**Done when:** the Pod is Ready, both automount settings are false and the nonempty token is explicitly projected at the requested path. Do not use the token as a test credential for an API with a different audience. [Projection reference](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#serviceaccount-token-volume-projection).

---

## Task 10 | Upgrade a worker node

**Where:** external Linux kubeadm lab. **Result:** a worker upgraded to the control plane's patch version. Minikube's `cks-lab-m02` does not implement this package-managed exercise.

### 1. Identify the worker and target version

On the **external cluster administration host**, using its own kubeconfig:

```bash
kubectl get nodes -o wide
```

Record the worker name and control-plane version. The example below assumes worker `worker01`, control plane `v1.35.1` and worker `v1.35.0`. Substitute the values from your external lab.

```bash
kubectl drain worker01 --ignore-daemonsets
```

If eviction is blocked, inspect the reported workloads/PDBs. Resolve their constraints before proceeding; do not add force or data-deletion flags automatically.

### 2. Upgrade kubeadm on the worker

SSH to the **external worker**, then inspect repository versions:

```bash
ssh worker01
sudo apt-get update
apt-cache madison kubeadm
apt-cache madison kubelet
```

Choose the exact package revision corresponding to the target patch. For example, use the following **only if `1.35.1-1.1` appears for both packages**:

```bash
K8S_PKG=1.35.1-1.1
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm="$K8S_PKG"
sudo apt-mark hold kubeadm
sudo kubeadm upgrade node
```

If the version is absent, configure the correct signed Kubernetes package repository for that minor release before continuing.

### 3. Upgrade kubelet and restart it

```bash
sudo apt-mark unhold kubelet
sudo apt-get install -y kubelet="$K8S_PKG"
sudo apt-mark hold kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet
kubelet --version
apt-mark showhold
exit
```

If kubectl is installed on this worker and also needs updating, verify its package revision and update it with the same unhold/install/hold sequence.

### 4. Return the worker to service

Back on the **external administration host**:

```bash
kubectl uncordon worker01
kubectl wait --for=condition=Ready node/worker01 --timeout=180s
kubectl get node worker01 -o wide
kubectl get pods -A -o wide
```

**Done when:** the worker reports the intended patch, is Ready and schedulable, package holds are restored and affected workloads recover. These commands are for Debian/Ubuntu-style packages; use your external host's package manager otherwise. [Kubeadm worker upgrade procedure](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/upgrading-linux-nodes/).

---

## Task 11 | Identify an image through its SBOM

**Where:** Mac, with Trivy installed separately. **Result:** two real SBOMs, an exact finding and only the affected container removed.

### 1. Read the current image assignment

```bash
command -v trivy
k get deployment inventory -n exam-supply -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\t"}{.image}{"\n"}{end}'
```

If Trivy is missing, install a trusted SBOM tool before continuing; this simulator does not install it. These commands use Trivy's [SPDX JSON output](https://trivy.dev/docs/latest/guide/supply-chain/sbom/).

Save the Deployment snapshot and capture both references **before removing a container**:

```bash
k get deployment inventory -n exam-supply -o json > ../.cks-state/jumpbox/exam/inventory-before.json
AMBER_IMAGE=$(k get deployment inventory -n exam-supply -o jsonpath='{.spec.template.spec.containers[?(@.name=="amber")].image}')
COBALT_IMAGE=$(k get deployment inventory -n exam-supply -o jsonpath='{.spec.template.spec.containers[?(@.name=="cobalt")].image}')
printf 'amber: %s\ncobalt: %s\n' "$AMBER_IMAGE" "$COBALT_IMAGE"
```

Both references must be populated. If you already removed a container, use your original saved snapshot/reports rather than overwriting them with incomplete input.

### 2. Generate both reports

```bash
trivy image --format spdx-json --output ../.cks-state/jumpbox/exam/amber.spdx "$AMBER_IMAGE"
trivy image --format spdx-json --output ../.cks-state/jumpbox/exam/cobalt.spdx "$COBALT_IMAGE"
```

Both commands must succeed. A download/scanner error is not a clean image report.

### 3. Inspect package data and save the finding

```bash
python3 - <<'PY'
import json
from pathlib import Path
root = Path('../.cks-state/jumpbox/exam')
deployment = json.loads((root / 'inventory-before.json').read_text())
images = {c['name']: c['image'] for c in deployment['spec']['template']['spec']['containers']}
assert set(images) == {'amber', 'cobalt'}, 'Need the original two-container snapshot.'
matches = []
for name in ('amber', 'cobalt'):
    doc = json.loads((root / f'{name}.spdx').read_text())
    assert str(doc['spdxVersion']).startswith('SPDX-2.'), 'Expected SPDX 2.x.'
    packages = {p['name'] for p in doc['packages']}
    assert packages, f'{name}: no package data.'
    found = 'libcrypto3' in packages
    print(f'{name}: libcrypto3 present = {found}')
    if found:
        matches.append({'container': name, 'image': images[name], 'package': 'libcrypto3'})
assert len(matches) == 1, 'Expected exactly one matching image; inspect the reports.'
(root / 'findings.json').write_text(json.dumps(matches[0], indent=2) + '\n')
print(json.dumps(matches[0], indent=2))
PY
```

This discovers the target from the actual reports. It never assumes `amber` or `cobalt` is always the affected container.

### 4. Remove only the identified container

```bash
TARGET_CONTAINER=$(python3 -c 'import json; print(json.load(open("../.cks-state/jumpbox/exam/findings.json"))["container"])')
printf 'Remove this container entry: %s\n' "$TARGET_CONTAINER"
k edit deployment inventory -n exam-supply
```

In Vim, find `spec.template.spec.containers`. Delete the entire list entry whose `name` matches the printed finding, including that entry's image and command. Keep the other container entry unchanged. Save and close.

```bash
k rollout status deployment/inventory -n exam-supply --timeout=180s
k get deployment inventory -n exam-supply -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\t"}{.image}{"\n"}{end}'
k get pods -n exam-supply
```

**Done when:** both package reports and `findings.json` exist, exactly the correct container was removed, and the survivor is Ready with its original image. Package presence is the task's selection criterion, not proof of a particular CVE.

---

## Task 12 | Repair a Pod Security violation

**Where:** Mac. **Result:** `locked-app` runs while Restricted enforcement remains enabled.

### 1. Read the admission failure

```bash
k get namespace exam-restricted --show-labels
k describe deployment locked-app -n exam-restricted
k get events -n exam-restricted --sort-by=.metadata.creationTimestamp
```

Events identify the denied settings. A Deployment object can exist even when admission prevents its ReplicaSet from creating Pods.

### 2. Make the application container compliant

```bash
k patch deployment locked-app -n exam-restricted --type=strategic --patch '
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: app
        securityContext:
          privileged: false
          allowPrivilegeEscalation: false
          capabilities:
            add: null
            drop:
            - ALL
'
```

The Pod-level identity and seccomp settings replace the explicit root identity and Unconfined profile. The container disables privileged execution/escalation, drops capabilities and removes the preconfigured `SYS_ADMIN` addition. In a strategic merge patch, `add: null` deletes that old field; adding `drop: [ALL]` alone would leave the forbidden addition in place. This matches the supplied sleeping workload; other applications may require additional compatibility changes. [Restricted controls](https://kubernetes.io/docs/concepts/security/pod-security-standards/).

### 3. Verify admission and availability

```bash
k rollout status deployment/locked-app -n exam-restricted --timeout=180s
k get pods -n exam-restricted
k get namespace exam-restricted -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}{"\n"}'
```

**Done when:** the Deployment is `1/1` Ready and the label still prints `restricted`. If earlier edits added a conflicting container-level UID, seccomp override or host namespace setting, fix it too; review the newest events if admission still fails.

---

## Task 13 | Remove unauthorized Docker access

**Where:** external disposable Linux Docker host. **Result:** the designated user loses Docker-group access; the socket is `root:docker` with mode `660`. The Mac and containerd lab nodes are not targets.

### 1. Inspect the user and socket

On that **external host**, replace the example username with the explicitly designated user:

```bash
LAB_USER=unauthorized-user
id "$LAB_USER"
getent group docker
stat -c '%U:%G %a %n' /var/run/docker.sock
```

Ensure you have an independent administrator session before changing the designated user's memberships.

### 2. Remove only that membership and restore socket access

```bash
sudo gpasswd -d "$LAB_USER" docker
sudo chown root:docker /var/run/docker.sock
sudo chmod 660 /var/run/docker.sock
```

If the user has Docker as its primary group, first assign its intended non-Docker primary group; supplementary-group removal alone does not fix that case. Do not invent a replacement group or change unrelated memberships.

### 3. Verify new and existing sessions

```bash
id "$LAB_USER"
stat -c '%U:%G %a %n' /var/run/docker.sock
sudo -iu "$LAB_USER" id
sudo -iu "$LAB_USER" env DOCKER_HOST=unix:///var/run/docker.sock docker ps
```

Expected: no Docker group in the user's new session; socket ownership/mode `root:docker 660`; direct access through this socket is denied. Run the check against this socket, rather than a different Docker context or rootless daemon.

Existing processes can retain the old supplementary group. End the designated user's old sessions using the lab's session-management procedure, then check a fresh login. Do not terminate your only administrator session.

**Done when:** both new and remaining sessions lack unauthorized Docker access, while authorized administrators still have the intended access. If the user retains root/sudo or another privileged Docker access route, removing one group is insufficient. [Docker group access reference](https://docs.docker.com/engine/install/linux-postinstall/).

---

## Task 14 | Require Cilium mutual authentication

**Where:** external Cilium/SPIRE cluster. **Result:** authenticated application access on TCP/8080 plus a separate local-host exception.

### 1. Confirm you are in the external environment

Use plain `kubectl` with that cluster's kubeconfig, not this simulator's `k` shortcut:

```bash
kubectl config current-context
kubectl get crd ciliumnetworkpolicies.cilium.io
kubectl get pods -n kube-system -l k8s-app=cilium
kubectl get pods -n exam-mesh -l app=invoices -o wide
```

Cilium mutual authentication and SPIRE must already be configured, and target/client workloads must be present. Installing a CRD alone does not provide authentication.

### 2. Apply the scoped policy

```bash
kubectl apply -f - <<'YAML'
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: invoices-auth
  namespace: exam-mesh
spec:
  endpointSelector:
    matchLabels:
      app: invoices
  ingress:
  - fromEndpoints:
    - matchLabels:
        k8s:io.kubernetes.pod.namespace: exam-allowed
    authentication:
      mode: required
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
  - fromEntities:
    - host
    authentication:
      mode: disabled
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
YAML
```

The rules intentionally differ: application peers require authentication; the local host does not. `host` does not mean every remote node. This is the same policy as `examples/cilium-mutual-auth.yaml`.

### 3. Verify application traffic and authentication evidence

Inspect the target address and existing client names:

```bash
kubectl get pods -n exam-mesh -l app=invoices -o wide
kubectl get pods -n exam-allowed -o wide
```

For handshake verification, use an allowed client on a different node from the target. Request the target Pod IP on port 8080. For example, if that client is named `probe`, set `INVOICE_IP` to the observed target IP, then run:

```bash
kubectl exec -n exam-allowed probe -- wget -T 3 -O- "http://$INVOICE_IP:8080"
```

Inspect authentication entries on the Cilium agent running on the target's node. Set `AGENT` to its actual Pod name:

```bash
kubectl get pods -n kube-system -l k8s-app=cilium -o wide
kubectl exec -n kube-system "$AGENT" -c cilium-agent -- cilium-dbg bpf auth list
```

Use the source/destination identities and handshake evidence to confirm mutual authentication, rather than assuming successful HTTP alone proves it. On the **target's own Linux node**, request the same Pod IP with `curl` to verify the local-host exception. Also test a disallowed namespace and inspect other policies for broader additive allow rules.

**Done when:** authenticated application traffic succeeds on the requested port, disallowed application sources are blocked and local-host traffic succeeds through its separate exception. Authentication is not payload encryption. Follow the installed Cilium version's [mutual-authentication verification](https://docs.cilium.io/en/stable/network/servicemesh/mutual-authentication/mutual-authentication-example/) and [auth-map command](https://docs.cilium.io/en/stable/cmdref/cilium-dbg_bpf_auth_list/).

---

## Task 15 | Make image admission fail closed

**Where:** inside `cks-lab`. **Result:** fail-closed image webhook configuration and matching API server flag/mounts in the copy. Automatic CONFIG checks; live enforcement is not tested.

### 1. Edit the admission configuration

**Mac:**

```bash
./k8s-sim.sh ssh
```

**Inside cks-lab:**

```bash
vim /opt/cks-lab/image-config/admission-configuration.yaml
```

For the supplied configuration, the result should be:

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
- name: ImagePolicyWebhook
  configuration:
    imagePolicy:
      kubeConfigFile: /opt/cks-lab/image-config/webhook-kubeconfig.yaml
      defaultAllow: false
```

If you added other admission configurations, preserve their entries. `defaultAllow: false` denies a request when the webhook cannot produce a decision.

### 2. Enable and configure the plugin in the copied manifest

```bash
vim /opt/cks-lab/exam/kube-apiserver.yaml
```

In the API server's existing command list, find `--enable-admission-plugins`. Append `ImagePolicyWebhook` to its comma-separated value, retaining the other existing plugins. For example, if the current value is only `NamespaceLifecycle`, the result is:

```yaml
- --enable-admission-plugins=NamespaceLifecycle,ImagePolicyWebhook
- --admission-control-config-file=/opt/cks-lab/image-config/admission-configuration.yaml
```

Replace the deliberately incorrect configuration-file argument; do not create duplicate flags. Also find `--disable-admission-plugins` and remove **only `ImagePolicyWebhook`** from that list. Leave `NodeRestriction` for task 16 and preserve any unrelated disabled plugins. Enabling and explicitly disabling the same plugin is not a valid repair. For a real installation, check whether its Kubernetes version also requires enabling `imagepolicy.k8s.io/v1alpha1` through `--runtime-config`, preserving other runtime settings.

### 3. Mount the directory containing both files

Append this entry to the API server container's existing `volumeMounts`:

```yaml
- name: cks-image-policy
  mountPath: /opt/cks-lab/image-config
  readOnly: true
```

Append the matching entry to the Pod's existing `spec.volumes`:

```yaml
- name: cks-image-policy
  hostPath:
    path: /opt/cks-lab/image-config
    type: Directory
```

Mounting the directory makes both the admission YAML and webhook kubeconfig available at their referenced paths. A real backend also needs its TLS trust/client credentials configured and accessible. Preserve task 6's audit mounts.

### 4. Review and return

```bash
cat /opt/cks-lab/image-config/admission-configuration.yaml
grep -n -E 'enable-admission|disable-admission|admission-control-config|cks-image-policy|/opt/cks-lab/image-config' /opt/cks-lab/exam/kube-apiserver.yaml
kubectl get nodes
exit
```

**Done locally when:** the copied manifest enables the plugin, references the admission configuration and includes the read-only directory mount, and `defaultAllow` is false. Keep the staged backend URL; it is intentionally not a live service. Test real allow, deny and backend-outage behavior only on a separate disposable control plane with a working authenticated backend. [ImagePolicyWebhook configuration](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#imagepolicywebhook).

---

## Task 16 | Harden API server access

**Where:** inside `cks-lab`. **Result:** corrected authentication, authorization and admission flags in the existing API server copy. Automatic CONFIG checks; live enforcement is not tested.

### 1. Open the same API server copy

**Mac:**

```bash
./k8s-sim.sh ssh
```

**Inside cks-lab:**

```bash
vim /opt/cks-lab/exam/kube-apiserver.yaml
```

### 2. Update existing flags rather than duplicating them

In the API server container's `command` list, ensure:

```yaml
- --anonymous-auth=false
- --authorization-mode=Node,RBAC
```

Find `--enable-admission-plugins` and append `NodeRestriction` to its existing comma-separated list. For example, if task 15 left `NamespaceLifecycle,ImagePolicyWebhook`, it becomes:

```yaml
- --enable-admission-plugins=NamespaceLifecycle,ImagePolicyWebhook,NodeRestriction
```

Preserve any other plugins already present. Do not add a second `--enable-admission-plugins` flag or remove the audit/admission mounts from earlier tasks. Remove `NodeRestriction` from `--disable-admission-plugins` too. If the disabled list becomes empty, remove that entire argument; otherwise retain its unrelated entries. Fresh revision-2 copies deliberately have all three task-16 controls wrong.

### 3. Verify the saved values

```bash
grep -n -E -- '--anonymous-auth|--authorization-mode|--enable-admission-plugins|--disable-admission-plugins' /opt/cks-lab/exam/kube-apiserver.yaml
kubectl get nodes
exit
```

**Done locally when:** there is one unambiguous value for each flag, anonymous authentication is disabled, authorization is `Node,RBAC`, and `NodeRestriction` is enabled without losing earlier work. This checks the copy; live authentication/authorization behavior needs a disposable Linux control plane.

---

## Review your attempt

Back on your **Mac in `secon_version`**:

```bash
./k8s-sim.sh score
./k8s-sim.sh score --task 1
./k8s-sim.sh time
```

The automatic ceiling is **72/100**. Tasks 1, 6, 15 and 16 receive `PASS CONFIG` or `FAIL CONFIG`, followed by individual requirements. They earn their task weight only when every check passes. `MANUAL` means the remaining task requires external evidence that this simulator cannot verify automatically. `ERROR` means evidence could not be read, not that the task was necessarily solved incorrectly. See [EXAM-NOTES.md](EXAM-NOTES.md) for the full breakdown.

Use this guide to review individual tasks without restarting. Run `./k8s-sim.sh start` only when you want to archive the current attempt and create a fresh exam.
