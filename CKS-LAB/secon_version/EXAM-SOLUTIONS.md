# Mock hints, solutions and evidence checklist

Open after your attempt. All `kubectl` examples below use the isolated wrapper. These are training examples for the stated tasks, not a promise of future exam questions. See [EXAM-SOURCES.md](EXAM-SOURCES.md) for source corrections and the distinction between live, replay and external exercises.

## Tasks 1, 6, 15 and 16: component configuration

Edit the **copies** inside `/opt/cks-lab/exam`; they are not watched manifests. Preserve unrelated flags, mounts, certificates and component arguments. The audit/admission input files are in `/opt/cks-lab/audit` and `/opt/cks-lab/image-config`. On a separate disposable Linux cluster, use real host paths, back up outside the watched manifest directory and validate API/node health after each change.

Task 1 kubelet fields:

```yaml
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
authorization:
  mode: Webhook
```

For etcd, inspect `--client-cert-auth=true`, `--trusted-ca-file`, `--cert-file`, `--key-file`, and their peer equivalents. Use certificate-authenticated etcdctl endpoint checks, then a request without client credentials; confirm that required authenticated clients still work. Kubernetes Node/RBAC authorization flags do not configure etcd.

Task 6 API flags:

```text
--audit-policy-file=/opt/cks-lab/audit/audit-policy.yaml
--audit-log-path=/var/log/k8s/audit.log
--audit-log-maxbackup=2
--audit-log-maxage=7
--audit-log-maxsize=10
```

Use a basic all-request `Metadata` policy, then verify that bodies containing Secret values are not captured. Mount the policy read-only and logs writable. Validate actual rotation externally; flag presence is insufficient.

Task 15: enable ImagePolicyWebhook without replacing other required plugins, set `--admission-control-config-file`, mount both admission configuration and webhook kubeconfig/certificates, and use `defaultAllow: false`. The `.invalid` URL intentionally cannot work. Real validation needs a genuine reachable backend plus deny and outage tests, not a permanently broken API.

Task 16: check `--anonymous-auth=false`, `--authorization-mode=Node,RBAC` and NodeRestriction in the complete admission plugin list. Check all required current plugins before editing. Keep an authenticated recovery session and inspect kubelet/container logs if the static Pod fails.

## Task 2: unblock the Secret volume

```bash
./k8s-sim.sh kubectl create secret tls site-tls -n exam-tls --cert=.cks-state/jumpbox/tls.crt --key=.cks-state/jumpbox/tls.key
./k8s-sim.sh kubectl rollout status deployment/certificate-reader -n exam-tls --timeout=180s
```

Inspect Pod events and the existing volume first. Removing that volume bypasses the requirement and does not earn credit.

## Tasks 3 and 5: real workload hardening

Change the final Dockerfile USER to `nobody`; busybox already defines that account. Apply task 3's numeric UID to the Deployment explicitly. A username's image UID and a task's requested numeric runtime UID are separate constraints.

```bash
./k8s-sim.sh kubectl patch deployment build-app -n exam-build --type=strategic -p '{"spec":{"template":{"spec":{"containers":[{"name":"app","securityContext":{"runAsUser":65535,"readOnlyRootFilesystem":true,"allowPrivilegeEscalation":false,"privileged":false}}]}}}}'
./k8s-sim.sh kubectl patch deployment immutable-app -n exam-immutable --type=strategic -p '{"spec":{"template":{"spec":{"containers":[{"name":"app","securityContext":{"runAsUser":30000,"readOnlyRootFilesystem":true,"allowPrivilegeEscalation":false,"privileged":false}}]}}}}'
```

Wait for rollout, then inspect `id -u` and the root entry in `/proc/mounts` in the new Pods. Build and run the Dockerfile separately for full image verification; editing it does not rebuild the already running Deployment image.

## Task 4: investigation before containment

Read each JSON event's namespace, Pod name and `fd.name`. Query the suspicious Pod's ownerReferences, then the ReplicaSet's ownerReferences; do not assume the first event or a fixed Deployment is bad. Record those identities in `incident.json`, then scale only that Deployment to zero. Wait for its Pods to disappear while confirming both innocent Deployments remain available.

Example rule for a real Falco installation:

```yaml
- rule: Memory device opened
  desc: Detect read or write opens of the memory device
  condition: (open_read or open_write) and fd.name = "/dev/mem"
  output: "Memory device opened (user=%user.name command=%proc.cmdline file=%fd.name)"
  priority: WARNING
```

Validate the complete rule set with the installed Falco version and test appropriate events in a disposable Linux runtime lab. Replayed JSON here is investigation practice; it is not a real Falco event emitted by this setup.

## Task 7: allow one namespace

```bash
./k8s-sim.sh kubectl apply -f - <<'YAML'
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

Check other additive policies. Test direct Pod-IP traffic from all three existing `probe` Pods; DNS is not involved in these probes. Keep clients and the server healthy so a stopped application cannot impersonate successful isolation.

## Task 8: actual ingress evidence

Inspect the provided controller and its IngressClass. Create a TLS Secret in `exam-ingress`, configure host/path/backend and `spec.tls`, and use that controller's redirect settings. Test plain HTTP for a redirect to HTTPS and use the matching SNI/Host and CA when testing HTTPS. A self-signed certificate must be explicitly trusted for the test; disabling verification does not validate identity.

The legacy NGINX annotation is useful only with a controller that implements it. This lab supplies the backend Service but does not install a retired ingress-nginx controller. Do not treat adding an annotation as an end-to-end solution.

## Task 9: disable implicit tokens, mount the intended projection

```bash
./k8s-sim.sh kubectl patch serviceaccount app-sa -n exam-tokens --type=merge -p '{"automountServiceAccountToken":false}'
./k8s-sim.sh kubectl apply -f - <<'YAML'
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

The API server may choose a different actual token lifetime. Scoring checks the requested projection and mount, not a claim about token acceptance by an unrelated API audience.

## Task 10: a real worker upgrade needs kubeadm-managed Linux

Inspect control-plane/worker versions and available packages first. Use your environment's exact package version strings. On the appropriate worker perform the documented kubeadm worker upgrade, restore package holds, restart kubelet, uncordon and verify workload recovery. Do not apply an API server control-plane upgrade command to a worker. Minikube SSH/drain practice is supplementary; apt changes to its container image do not prove its managed Kubernetes binaries were upgraded.

## Task 11: identify rather than guess

Read the Deployment's current container-to-image map. Generate each image's SPDX document using the trusted BOM tool available in your environment. Save it with the corresponding container name, then inspect package entries for `libcrypto3`. Save the exact image/container/package finding and remove only that container from `spec.template.spec.containers`.

The target assignment changes, so no single container name is the fixed solution. A scanner/tool fetch error is not an empty clean report. Keep the surviving image/container unchanged, wait for rollout and check the remaining Pod is Ready.

## Task 12: make the Deployment comply

Use Pod/ReplicaSet events to find the denied security settings. Retain the namespace's Restricted label and repair the container/template. A suitable starting point for this sleeping workload is:

```yaml
securityContext:
  runAsUser: 65532
  runAsNonRoot: true
  privileged: false
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
  seccompProfile:
    type: RuntimeDefault
```

The seccomp and non-root settings may be inherited from the Pod security context. Reconcile all containers and wait for a compliant healthy replica. Relabelling the namespace to privileged or deleting the workload is not a solution.

## Task 13: Docker privileges

Use a separate disposable Docker host. Check the actual user/group/socket first, remove only the specified unauthorized membership, restore intended ownership/permissions and verify effective sessions. Do not change the Mac's Docker socket or invent a Docker socket on a containerd node just to satisfy a file check.

## Task 14: actual Cilium authentication

`examples/cilium-mutual-auth.yaml` shows separate application and local-host rules. It is never applied automatically. Use a Cilium installation with the mutual-authentication feature and SPIRE enabled, verify identity issuance, exercise the allowed path and inspect authentication evidence. Review other policies for an additive bypass. Local `host` and `remote-node` identities are different; do not broaden the exception unintentionally. Require separate encryption configuration/evidence if the task asks for encrypted payloads.
