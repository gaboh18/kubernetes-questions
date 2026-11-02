# Sources and fidelity decisions

Checked 31 October 2026.

The [candidate report](https://www.reddit.com/r/KubernetesCerts/comments/1rzoh2s/passed_cks_heres_what_actually_came_up/) supplies the topic sequence for this 16-task practice round. It is a personal recollection, not an official question bank. All workloads, names, evidence files and task text here are newly written. Preserve the broader drill bank because one person's report cannot establish complete exam coverage.

The [official CKS instructions](https://docs.linuxfoundation.org/tc-docs/certification/important-instructions-cks) currently describe a two-hour exam with 15–20 tasks, designated SSH hosts and Kubernetes v1.35. This mock supplies two node targets and a two-hour timer, but a Mac terminal plus Minikube is not the exam's Linux desktop/host environment. Check official instructions again near your appointment.

| Report detail | Practice implementation or correction |
| --- | --- |
| Component authentication | Separate kubelet anonymous/webhook settings from etcd's certificate-based transport controls. [etcd transport security](https://etcd.io/docs/v3.6/op-guide/security/) |
| Missing TLS Secret | A real Deployment starts blocked on a missing Secret and must recover with its mount preserved. |
| Image user and numeric UID | Final-stage `USER nobody` is separate from the specifically requested runtime UID. Username mappings vary; do not memorize an assumed equivalence. [Security context documentation](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/) |
| Runtime incident | Shuffled replay events identify a randomly selected real workload; containment is real, engine validation remains external. |
| Namespace policy | Actual Calico-backed traffic checks include allowed namespace, denied namespace and same-namespace source. |
| Ingress redirect annotation | Settings depend on the actual controller. The community ingress-nginx project retired in March 2026, so this lab does not install it automatically. [Retirement announcement](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/) |
| Worker patch procedure | Exact apt package revisions must come from the configured repository. Drain options depend on workloads. Use kubeadm's worker procedure and verify final health; a Minikube version or new worker is not an upgrade. [Linux worker upgrade](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/upgrading-linux-nodes/) |
| SBOM | Inspect both actual image reports and remove only the affected container from a Deployment. Presence of a package alone does not identify a specific CVE. [BOM project](https://github.com/kubernetes-sigs/bom) |
| Restricted namespace | Admission is already enforcing; fix the broken Deployment instead of earning points for a namespace label. [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) |
| Cilium authentication | A DNS-only policy is not equivalent. Mutual authentication requires feature configuration and SPIRE; it does not itself encrypt application traffic. [Architecture/prerequisites](https://docs.cilium.io/en/stable/network/servicemesh/mutual-authentication/mutual-authentication/), [configuration and verification](https://docs.cilium.io/en/stable/network/servicemesh/mutual-authentication/mutual-authentication-example/) |

No live API/kubelet weakening, Docker socket ownership change, unsigned tool download, fake controller or background destructive reset is introduced. Component copies and external exercises remain explicit so file edits cannot masquerade as verified security enforcement. The automatic ceiling is 47 points, not a normalized 100-point readiness score; weights are local training choices.
