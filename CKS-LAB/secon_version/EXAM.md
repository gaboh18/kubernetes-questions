# CKS practice exam

**Time allowed:** 120 minutes · **Tasks:** 16 · **Total weight:** 100%

These are original practice questions. The host information and task layout approximate the exam experience; question wording and weights are local training choices.

Start from `secon_version` with `./k8s-sim.sh start`. The timer begins after setup completes. Use `./k8s-sim.sh time` to check it.

For tasks assigned to `cks-lab`, connect from your Mac with `./k8s-sim.sh ssh` and use `kubectl` inside that session. Use `sudo` when required. Return to your Mac with `exit` between host tasks. Alternatively, run cluster commands from your Mac with `./k8s-sim.sh kubectl ...`.

Paths beginning with `/opt/cks-lab` are inside the node. Paths beginning with `../.cks-state` are on your Mac, relative to `secon_version`. External hosts and controllers are not created by this simulator. Edit only the specified component copies; leave active Minikube component files unchanged.

Review [lab scope and grading](EXAM-NOTES.md) before beginning. Open [solutions](EXAM-SOLUTIONS.md) after your attempt.

---

## Task 01 | Component authentication

**Weight:** 7%

> **Host:** `cks-lab` · **Scope:** configuration copies
> **Files:** `/opt/cks-lab/exam/kubelet-config.yaml`, `/opt/cks-lab/exam/etcd.yaml`

**Context**

A security review identified five authentication and authorization faults in the supplied node and etcd configurations.

**Task**

Update the supplied configuration files so that:

- The kubelet rejects anonymous requests, enables webhook authentication and uses webhook authorization.
- etcd requires a valid client certificate signed by its trusted CA for client connections. Restore the client CA path using the unchanged peer CA reference in the supplied manifest.
- Existing peer TLS settings, certificate paths and data paths are preserved.

Save the corrected copies at their original paths. Do not apply them to the running Minikube components.

---

## Task 02 | Restore a TLS workload

**Weight:** 5%

> **Host:** `cks-lab` · **Namespace:** `exam-tls`
> **Deployment:** `certificate-reader`
> **Input files on your Mac:** `../.cks-state/jumpbox/tls.crt`, `../.cks-state/jumpbox/tls.key`

**Context**

The Deployment cannot start successfully because a required TLS Secret is missing.

**Task**

Create a TLS Secret named `site-tls` from the supplied certificate and private key in the Deployment's namespace.

Restore the Deployment to one available replica. Preserve its existing read-only Secret mount at `/tls` and use the supplied certificate material.

---

## Task 03 | Harden an image and Deployment

**Weight:** 7%

> **Host:** `cks-lab` · **Namespace:** `exam-build`
> **Deployment:** `build-app`
> **File on your Mac:** `../.cks-state/jumpbox/exam/Dockerfile`

**Context**

An application image and its Deployment must satisfy the organization's container security requirements.

**Task**

Modify the supplied Dockerfile so that the final image stage uses the existing user `nobody`.

Update the Deployment so that its application container:

- Runs with effective UID `65535`.
- Uses a read-only root filesystem.
- Runs without privileged access or privilege escalation.

Keep one replica available and save the Dockerfile at its original path. Updating the Deployment image is not required for this local task.

---

## Task 04 | Investigate and contain a workload

**Weight:** 7%

> **Host:** `cks-lab` · **Namespace:** `exam-runtime`
> **Evidence on your Mac:** `../.cks-state/jumpbox/exam/runtime-events.jsonl`
> **Outputs on your Mac:** `../.cks-state/jumpbox/exam/incident.json`, `../.cks-state/jumpbox/exam/falco_rules.local.yaml`
> **Scope:** supplied event replay; Falco execution requires an external runtime lab

**Context**

Captured runtime events indicate that one of the namespace's workloads opened `/dev/mem`.

**Task**

Identify the Pod responsible and its owning Deployment. Scale only that Deployment to zero replicas, leaving the other two Deployments available.

Write the identified `namespace`, `pod` and `deployment` as fields in `incident.json`.

Write a Falco rule in `falco_rules.local.yaml` that detects read or write opens of `/dev/mem` and emits an alert with priority `WARNING`.

---

## Task 05 | Enforce container immutability

**Weight:** 6%

> **Host:** `cks-lab` · **Namespace:** `exam-immutable`
> **Deployment:** `immutable-app`

**Context**

The application must run with a restricted identity and an immutable root filesystem.

**Task**

Update the Deployment so that its application container runs with effective UID `30000`, has a read-only root filesystem and runs without privileged access or privilege escalation.

Ensure one replica is available with the required runtime settings.

---

## Task 06 | Configure API auditing

**Weight:** 7%

> **Host:** `cks-lab` · **Scope:** configuration copies
> **Files:** `/opt/cks-lab/audit/audit-policy.yaml`, `/opt/cks-lab/exam/kube-apiserver.yaml`

**Context**

The supplied audit configuration has incomplete coverage, exposes Secret bodies and uses incorrect log settings. The cluster requires metadata for every API operation.

**Task**

Update the supplied audit policy to record request metadata for all API operations without recording request or response bodies.

Configure the copied API server manifest to use that policy and these log settings:

| Setting | Required value |
| --- | --- |
| Log path | `/var/log/k8s/audit.log` |
| Maximum backup files | `2` |
| Maximum age | `7` days |
| Maximum size per file | `10 MiB` |

Include the required policy and log mounts, with the policy mounted read-only. Preserve unrelated API server settings. Do not replace the active manifest.

---

## Task 07 | Restrict namespace ingress

**Weight:** 7%

> **Host:** `cks-lab` · **Namespace:** `exam-backend`
> **Target Pods:** `app=api`

**Context**

The backend currently accepts connections from namespaces that should not have access.

**Task**

Create a NetworkPolicy named `default-deny-ingress` that selects all Pods in `exam-backend` and denies ingress by default.

Add a policy allowing only Pods in namespace `exam-allowed` to reach Pods labeled `app=api` on TCP port `8080`.

Keep egress unrestricted. Preserve the existing workloads and `probe` Pods. Connections from `exam-allowed` must succeed; connections from `exam-denied` and other Pods in `exam-backend` must be blocked.

---

## Task 08 | Expose an application over HTTPS

**Weight:** 6%

> **Host:** `cks-lab` · **Namespace:** `exam-ingress`
> **Service:** `web`, port `80`
> **Prerequisite:** a working Ingress controller installed separately

**Context**

An existing application must be available through a TLS-protected endpoint.

**Task**

Create an Ingress for host `exam.cks.local` that routes path `/` to Service `web` on port `80`.

Configure TLS termination using a certificate and TLS Secret in `exam-ingress`. Configure the installed controller to redirect HTTP requests to HTTPS.

Verify the HTTP redirect and a successful HTTPS response using the correct host name and a trusted certificate.

---

## Task 09 | Control ServiceAccount token mounts

**Weight:** 6%

> **Host:** `cks-lab` · **Namespace:** `exam-tokens`
> **ServiceAccount:** `app-sa` · **Existing Pod:** `token-client`

**Context**

An existing application automatically mounts API credentials and has an incorrectly configured explicit token projection.

**Task**

Disable automatic ServiceAccount token mounting on `app-sa` and repair the existing Pod `token-client`, keeping it on that ServiceAccount. Recreate only this Pod if required to change immutable fields.

Configure the Pod with a projected ServiceAccount token having these properties:

| Setting | Required value |
| --- | --- |
| Mount directory | `/var/run/secrets/tokens` |
| Token filename | `token` |
| Audience | `cks-lab` |
| Requested lifetime | `3600` seconds |
| Mount access | Read-only |

Preserve the application image and long-running command and ensure the replacement Pod is Ready.

---

## Task 10 | Upgrade a worker node

**Weight:** 7%

> **Host:** a separate disposable kubeadm-managed worker
> **Prerequisite:** a Linux kubeadm cluster with the worker one patch version behind its control plane; not provisioned by this simulator

**Context**

A worker node requires a patch upgrade to match its control plane.

**Task**

Upgrade the worker to the control plane's Kubernetes patch version using the packages available in its configured repository.

Drain the node appropriately, upgrade kubeadm and the node configuration, upgrade the node packages and restore package holds. Restart the required service and return the node to a schedulable state.

Verify the resulting version, Ready condition and workload recovery. Preserve workload data.

---

## Task 11 | Identify an image through its SBOM

**Weight:** 7%

> **Host:** `cks-lab` · **Namespace:** `exam-supply`
> **Deployment:** `inventory` · **Containers:** `amber`, `cobalt`
> **Outputs on your Mac:** `../.cks-state/jumpbox/exam/amber.spdx`, `../.cks-state/jumpbox/exam/cobalt.spdx`, `../.cks-state/jumpbox/exam/findings.json`
> **Prerequisite:** a separately installed image SBOM tool

**Context**

One of the Deployment's container images includes the package `libcrypto3` and must be removed from service.

**Task**

Generate an SPDX 2.x SBOM containing package data for each container image. Save each report under its corresponding container name at the paths above. JSON and tag/value SPDX formats are accepted.

Identify the container whose image contains `libcrypto3`. Write a JSON object with exactly these fields to `findings.json`: `container`, `image` and `package`.

Remove only the identified container from the Deployment. Preserve the remaining container and its image, and ensure the Deployment has one available replica.

---

## Task 12 | Repair a Pod Security violation

**Weight:** 6%

> **Host:** `cks-lab` · **Namespace:** `exam-restricted`
> **Deployment:** `locked-app`

**Context**

The namespace enforces the Restricted Pod Security Standard. The Deployment cannot create compliant Pods.

**Task**

Identify and correct the Deployment's security settings so that its Pods satisfy the namespace's enforced policy.

Restore one available replica. Preserve Restricted enforcement on the namespace and keep the application workload in place.

---

## Task 13 | Remove unauthorized Docker access

**Weight:** 5%

> **Host:** a separate disposable Linux Docker host
> **Prerequisite:** a Docker daemon and an explicitly designated unauthorized user; not provisioned by this simulator

**Context**

A user who is not authorized to administer Docker has access through membership in the Docker group.

**Task**

Remove the designated user's Docker group membership without changing other users' access.

Restore `/var/run/docker.sock` ownership to `root:docker` with permissions appropriate for owner/group access only. Verify that the user's effective sessions no longer retain unauthorized access.

Perform this exercise on the separate Linux host, leaving your Mac's Docker socket unchanged.

---

## Task 14 | Require Cilium mutual authentication

**Weight:** 6%

> **Host:** a separate Cilium-enabled cluster administration host
> **Namespace:** `exam-mesh` · **Target Pods:** `app=invoices`
> **Prerequisite:** Cilium with mutual authentication and SPIRE enabled, plus the target workloads; not provisioned by this simulator

**Context**

The invoices application must authenticate application peers while continuing to accept local host traffic.

**Task**

Configure policy for the target Pods so that application traffic from namespace `exam-allowed` is permitted on TCP port `8080` only with mutual authentication.

Permit local host access through a separate rule that does not require mutual authentication. Keep the application rule scoped to the required namespace and port.

Verify authenticated application access and the local host exception.

---

## Task 15 | Make image admission fail closed

**Weight:** 6%

> **Host:** `cks-lab` · **Scope:** configuration copies
> **Files:** `/opt/cks-lab/exam/kube-apiserver.yaml`, `/opt/cks-lab/image-config/admission-configuration.yaml`, `/opt/cks-lab/image-config/webhook-kubeconfig.yaml`

**Context**

Image admission must deny requests when the image policy backend cannot provide a decision.

**Task**

Update the supplied configuration to enable `ImagePolicyWebhook`, remove its explicit disabling and set its `defaultAllow` value to `false`.

Configure the copied API server manifest with the admission configuration flag and required file mounts. Preserve other required admission plugins and unrelated settings.

Retain the supplied webhook kubeconfig reference. The staged backend is a placeholder; do not activate this configuration on the running Minikube API server.

---

## Task 16 | Harden API server access

**Weight:** 5%

> **Host:** `cks-lab` · **Scope:** configuration copy
> **File:** `/opt/cks-lab/exam/kube-apiserver.yaml`

**Context**

The API server must enforce authenticated, authorized access and restrict the actions available to kubelets.

**Task**

Update the copied API server manifest to:

- Disable anonymous authentication.
- Use `Node,RBAC` authorization.
- Enable the `NodeRestriction` admission plugin, remove its explicit disabling and preserve other required plugins.

Preserve unrelated settings and your changes from the other API server tasks. Save the corrected copy at its original path, leaving the active manifest unchanged.
