#!/bin/bash
# k8s-sim.sh - Finalized CKS Simulator Control Engine

DURATION=120
JUMPBOX_DIR="/opt/cks-lab"

function start_exam() {
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
    echo "  🚀 CKS MINIKUBE HYBRID SIMULATOR STARTED 🚀"
    echo "------------------------------------------------------------"
    echo "⏰ Time remaining: 120 minutes"
    echo "⚠️  Jumpbox Workspace: $JUMPBOX_DIR"
    echo "⚠️  Control Plane Configs: minikube ssh"
    echo "👉 Score your work:  ./k8s-sim.sh score"
}

function score_exam() {
    echo "📊 --- CKS MINIKUBE SCORE REPORT ---"
    SCORE=0

    if minikube ssh "sudo grep -q 'ImagePolicyWebhook' /etc/kubernetes/manifests/kube-apiserver.yaml" 2>/dev/null; then
        echo "✅ Q1: Admission controllers enabled (+6)"
        ((SCORE+=6))
    fi
    echo "✅ Q2: Kubeadm upgraded (Architecture Auto-pass) (+6)"; ((SCORE+=6))
    if kubectl get netpol default-deny-all -n backend &>/dev/null; then
        echo "✅ Q3: Default deny network policy created (+6)"
        ((SCORE+=6))
    fi
    if ! kubectl get pod hacker-pod -n web &>/dev/null; then
        echo "✅ Q4: Malicious pod deleted (+6)"
        ((SCORE+=6))
    fi
    if kubectl get ciliumnetworkpolicy restrict-dns -n app &>/dev/null; then
        echo "✅ Q5: Cilium network policy created (+6)"
        ((SCORE+=6))
    fi
    if kubectl get peerauthentication default-strict-mtls -n istio-system &>/dev/null; then
        echo "✅ Q6: Istio strict mTLS applied (+6)"
        ((SCORE+=6))
    fi
    if grep -q "USER appuser" $JUMPBOX_DIR/Dockerfile 2>/dev/null; then
        echo "✅ Q7: Non-root user set in Dockerfile (+6)"
        ((SCORE+=6))
    fi
    if kubectl get deploy secure-app -n prod -o jsonpath='{.spec.template.metadata.annotations}' 2>/dev/null | grep -q "localhost/custom-profile" && kubectl get deploy secure-app -n prod -o jsonpath='{.spec.template.spec.securityContext.seccompProfile.type}' 2>/dev/null | grep -q "RuntimeDefault"; then
        echo "✅ Q8: AppArmor and Seccomp profiles configured (+6)"
        ((SCORE+=6))
    fi
    if minikube ssh "sudo grep -q 'mode: Webhook' /var/lib/kubelet/config.yaml" 2>/dev/null; then
        echo "✅ Q9: Kubelet authorization mode fixed (+6)"
        ((SCORE+=6))
    fi
    if [ -f $JUMPBOX_DIR/nginx-sbom.json ]; then
        echo "✅ Q10: SBOM generated (+6)"
        ((SCORE+=6))
    fi
    if kubectl get ns frontend --show-labels 2>/dev/null | grep -q "pod-security.kubernetes.io/enforce=restricted"; then
        echo "✅ Q11: PSS enforce restricted applied (+6)"
        ((SCORE+=6))
    fi
    if [[ $(kubectl get sa db-sa -n database -o jsonpath='{.automountServiceAccountToken}' 2>/dev/null) == "false" ]]; then
        echo "✅ Q12: Automount ServiceAccount token disabled (+6)"
        ((SCORE+=6))
    fi
    if minikube ssh "sudo grep -q 'audit-policy-file' /etc/kubernetes/manifests/kube-apiserver.yaml" 2>/dev/null; then
        echo "✅ Q13: Audit logging enabled (+6)"
        ((SCORE+=6))
    fi
    if ! minikube ssh "test -f /usr/local/bin/kube-apiserver-test" 2>/dev/null; then
        echo "✅ Q14: Compromised binary deleted (+5)"
        ((SCORE+=5))
    fi
    if [[ $(kubectl get deploy web-server -n dmz -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null) == "httpd:2.4.58" ]]; then
        echo "✅ Q15: Vulnerable image updated (+6)"
        ((SCORE+=6))
    fi
    if [[ $(kubectl get pod immutable-pod -n default -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}' 2>/dev/null) == "true" ]]; then
        echo "✅ Q16: ReadOnlyRootFilesystem enforced (+5)"
        ((SCORE+=5))
    fi
    if minikube ssh "sudo grep -q 'encryption-provider-config' /etc/kubernetes/manifests/kube-apiserver.yaml" 2>/dev/null; then
        echo "✅ Q17: Encryption at rest configured (+6)"
        ((SCORE+=6))
    fi

    echo "---------------------------"
    echo "FINAL SCORE: $SCORE / 100"
}

case "$1" in
    start) start_exam ;;
    score) score_exam ;;
    time) cat .remaining_time 2>/dev/null || echo "Not running." ;;
    cleanup) ./exam-cleanup.sh ;;
    *) echo "Usage: ./k8s-sim.sh {start|score|time|cleanup}" ;;
esac
