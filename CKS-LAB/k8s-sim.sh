#!/bin/bash
# k8s-sim.sh - Finalized CKS Simulator Control Engine

DURATION=120
JUMPBOX_DIR="/opt/cks-lab"

function start_exam() {
    echo "🧹 Wiping old environment and caches..."
    minikube delete --all --purge &>/dev/null
    pkill -f "remaining_time" &>/dev/null
    rm -rf ~/.kube ~/.minikube &>/dev/null

    echo "🏗️ Spinning up a completely fresh Minikube cluster baseline..."
    minikube start

    echo "⚙️ Running exam injection payloads..."
    chmod +x exam-cleanup.sh exam-setup.sh
    
    ./exam-cleanup.sh
    ./exam-setup.sh
    
    (
        seconds=$((DURATION * 60))
        while [ $seconds -gt 0 ]; do
            printf "%02d:%02d:%02d\n" $((seconds/3600)) $(( (seconds/60)%60 )) $((seconds%60)) > .remaining_time
            sleep 1
            ((seconds--))
        done
        echo "EXPIRED" > .remaining_time
    ) &
    echo $! > .timer_pid

    clear
    echo "------------------------------------------------------------"
    echo "   🚀 CKS MINIKUBE HYBRID SIMULATOR STARTED 🚀"
    echo "------------------------------------------------------------"
    echo "⏰ Time remaining: 120 minutes"
    echo "⚠️  Jumpbox Workspace: $JUMPBOX_DIR"
    echo "⚠️  Control Plane Configs: minikube ssh"
    echo "👉 Score your work:  ./k8s-sim.sh score"
}

function score_exam() {
    echo "📊 --- CKS MINIKUBE SCORE REPORT ---"
    SCORE=0

    # Q1: Admission Controllers
    if minikube ssh "sudo grep -q 'ImagePolicyWebhook' /etc/kubernetes/manifests/kube-apiserver.yaml" 2>/dev/null; then
        echo "✅ Q1: Admission controllers enabled (+5)"; ((SCORE+=5))
    fi

    # Q2: Kubeadm Upgrade
    echo "✅ Q2: Kubeadm upgraded (Architecture Auto-pass) (+5)"; ((SCORE+=5))

    # Q3: Network Policy
    if kubectl get netpol default-deny-all -n backend &>/dev/null; then
        echo "✅ Q3: Default deny network policy created (+5)"; ((SCORE+=5))
    fi

    # Q4: Falco Rule & Scale
    if minikube ssh "sudo grep -q '/dev/mem' /etc/falco/falco_rules.local.yaml" 2>/dev/null && [[ $(kubectl get deploy web-backend -n web -o jsonpath='{.spec.replicas}' 2>/dev/null) == "0" ]]; then
        echo "✅ Q4: Falco rule added and deployment scaled down (+5)"; ((SCORE+=5))
    fi

    # Q5: Cilium
    if kubectl get ciliumnetworkpolicy restrict-dns -n app &>/dev/null; then
        echo "✅ Q5: Cilium network policy created (+5)"; ((SCORE+=5))
    fi

    # Q6: Istio
    if kubectl get peerauthentication default-strict-mtls -n istio-system &>/dev/null; then
        echo "✅ Q6: Istio strict mTLS applied (+5)"; ((SCORE+=5))
    fi

    # Q7: Dockerfile
    if grep -q "USER appuser" $JUMPBOX_DIR/Dockerfile 2>/dev/null; then
        echo "✅ Q7: Non-root user set in Dockerfile (+5)"; ((SCORE+=5))
    fi

    # Q8: AppArmor & Seccomp (Native v1.30+)
    if kubectl get deploy secure-app -n prod -o jsonpath='{.spec.template.spec.containers[0].securityContext.appArmorProfile.localhostProfile}' 2>/dev/null | grep -q "custom-profile" && kubectl get deploy secure-app -n prod -o jsonpath='{.spec.template.spec.containers[0].securityContext.seccompProfile.type}' 2>/dev/null | grep -q "RuntimeDefault"; then
        echo "✅ Q8: Native AppArmor and Seccomp profiles configured (+5)"; ((SCORE+=5))
    fi

    # Q9: Kubelet
    if minikube ssh "sudo grep -q 'mode: Webhook' /var/lib/kubelet/config.yaml" 2>/dev/null; then
        echo "✅ Q9: Kubelet authorization mode fixed (+5)"; ((SCORE+=5))
    fi

    # Q10: BOM & Container Removal
    if minikube ssh "test -f /opt/cks-lab/sbom.spdx" 2>/dev/null && ! kubectl get pod multi-pod -n default -o jsonpath='{.spec.containers[*].name}' 2>/dev/null | grep -q "vulnerable-app"; then
        echo "✅ Q10: BOM generated and vulnerable container removed (+5)"; ((SCORE+=5))
    fi

    # Q11: Pod Security Standards
    if kubectl get ns frontend --show-labels 2>/dev/null | grep -q "pod-security.kubernetes.io/enforce=restricted"; then
        echo "✅ Q11: PSS enforce restricted applied (+5)"; ((SCORE+=5))
    fi

    # Q12: ServiceAccount Token Projection
    if [[ $(kubectl get pod token-pod -n database -o jsonpath='{.spec.volumes[*].projected.sources[*].serviceAccountToken.path}' 2>/dev/null) == "token" ]]; then
        echo "✅ Q12: ServiceAccount token projected (+5)"; ((SCORE+=5))
    fi

    # Q13: Audit Policy
    if minikube ssh "sudo grep -q '/etc/kubernetes/audit/audit-policy.yaml' /etc/kubernetes/manifests/kube-apiserver.yaml" 2>/dev/null; then
        echo "✅ Q13: Audit logging enabled (+5)"; ((SCORE+=5))
    fi

    # Q14: SHA512
    if ! minikube ssh "test -f /usr/local/bin/kube-apiserver-test" 2>/dev/null; then
        echo "✅ Q14: Compromised binary deleted (+5)"; ((SCORE+=5))
    fi

    # Q15: Vulnerable image updated (Leave this as it was)
    if [[ $(kubectl get deploy web-server -n dmz -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null) == "httpd:2.4.58" ]]; then
        echo "✅ Q15: Vulnerable image updated (+5)"
        ((SCORE+=5))
    fi

    # Q16: RootOnlyFS
    if [[ $(kubectl get pod immutable-pod -n default -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}' 2>/dev/null) == "true" ]]; then
        echo "✅ Q16: ReadOnlyRootFilesystem enforced (+5)"; ((SCORE+=5))
    fi

    # Q17: Encryption at Rest
    if minikube ssh "sudo grep -q '/etc/kubernetes/encryption/encryption-config.yaml' /etc/kubernetes/manifests/kube-apiserver.yaml" 2>/dev/null; then
        echo "✅ Q17: Encryption at rest configured (+5)"; ((SCORE+=5))
    fi

    # Q18: TLS Secret
    if kubectl get secret secure-tls -n default --field-selector type=kubernetes.io/tls &>/dev/null; then
        echo "✅ Q18: TLS Secret created successfully (+5)"; ((SCORE+=5))
    fi

    # Q19: Ingress
    if kubectl get ingress secure-ingress -n default -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/ssl-redirect}' 2>/dev/null | grep -q "true"; then
        echo "✅ Q19: Ingress SSL redirect enforced (+5)"; ((SCORE+=5))
    fi

    # Q20: Docker Socket
    if ! minikube ssh "groups unauthorized_user" 2>/dev/null | grep -q "docker" && minikube ssh "stat -c %U /var/run/docker.sock" 2>/dev/null | grep -q "root"; then
        echo "✅ Q20: Host Docker daemon secured (+5)"; ((SCORE+=5))
    fi

    # Q21: Trivy Image Scan (NEW)
    if [ -f "$JUMPBOX_DIR/trivy-report.json" ]; then
        echo "✅ Q21: Trivy scan report generated (+5)"
        ((SCORE+=5))
    fi

    echo "---------------------------"
    echo "FINAL SCORE: $SCORE / 105"
}

case "$1" in
    start) start_exam ;;
    score) score_exam ;;
    time) cat .remaining_time 2>/dev/null || echo "Not running." ;;
    cleanup) ./exam-cleanup.sh ;;
    *) echo "Usage: ./k8s-sim.sh {start|score|time|cleanup}" ;;
esac
