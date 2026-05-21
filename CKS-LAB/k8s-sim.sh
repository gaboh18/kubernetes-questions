#!/bin/bash
# k8s-sim.sh - Gabriel Exam (CKS Lab Simulator - 17 Questions)

LAB_ROOT="/opt/cks-lab"
DURATION=120

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
    echo "  🚀 CKS ULTIMATE SIMULATOR STARTED (17 QUESTIONS) 🚀"
    echo "------------------------------------------------------------"
    echo "⏰ Time remaining: 120 minutes"
    echo "👉 Score your work:  ./k8s-sim.sh score"
    echo "👉 Check timer:      ./k8s-sim.sh time"
    echo "👉 Cleanup exam:     ./k8s-sim.sh cleanup"
}

function score_exam() {
    SCORE=0
    echo "📊 --- CKS SCORE REPORT ---"

    # Q1: Admission Controller - 6 pts
    if grep -q "ImagePolicyWebhook" /opt/cks-lab/kube-apiserver.yaml 2>/dev/null && grep -q "NodeRestriction" /opt/cks-lab/kube-apiserver.yaml 2>/dev/null; then
        echo "✅ Q1: Admission controllers enabled (+6)"
        ((SCORE+=6))
    fi

    # Q2: Kubeadm Upgrade - 6 pts
    if kubeadm version 2>/dev/null | grep -q "v1.30.1" || dpkg -l 2>/dev/null | grep -q "kubeadm.*1.30.1"; then
        echo "✅ Q2: Kubeadm upgraded (+6)"
        ((SCORE+=6))
    fi

    # Q3: NetworkPolicy - 6 pts
    if kubectl get netpol default-deny-all -n backend 2>/dev/null | grep -q "default-deny-all"; then
        echo "✅ Q3: Default deny network policy created (+6)"
        ((SCORE+=6))
    fi

    # Q4: Falco Runtime Security - 6 pts
    if ! kubectl get pod hacker-pod -n web 2>/dev/null | grep -q "hacker-pod"; then
        echo "✅ Q4: Malicious pod deleted (+6)"
        ((SCORE+=6))
    fi

    # Q5: Cilium Network Policy - 6 pts
    if kubectl get ciliumnetworkpolicy restrict-dns -n app 2>/dev/null | grep -q "restrict-dns"; then
        echo "✅ Q5: Cilium network policy created (+6)"
        ((SCORE+=6))
    fi

    # Q6: Istio mTLS - 6 pts
    if kubectl get peerauthentication default-strict-mtls -n istio-system 2>/dev/null | grep -q "default-strict-mtls"; then
        echo "✅ Q6: Istio strict mTLS applied (+6)"
        ((SCORE+=6))
    fi

    # Q7: Dockerfile Security - 6 pts
    if grep -q "USER appuser" /opt/cks-lab/Dockerfile 2>/dev/null; then
        echo "✅ Q7: Non-root user set in Dockerfile (+6)"
        ((SCORE+=6))
    fi

    # Q8: AppArmor & Seccomp - 6 pts
    if kubectl get deploy secure-app -n prod -o jsonpath='{.spec.template.metadata.annotations}' 2>/dev/null | grep -q "localhost/custom-profile"; then
        if kubectl get deploy secure-app -n prod -o jsonpath='{.spec.template.spec.securityContext.seccompProfile.type}' 2>/dev/null | grep -q "RuntimeDefault"; then
            echo "✅ Q8: AppArmor and Seccomp profiles configured (+6)"
            ((SCORE+=6))
        fi
    fi

    # Q9: Kube-bench Fixes - 6 pts
    if grep -q "mode: Webhook" /var/lib/kubelet/config.yaml 2>/dev/null; then
        echo "✅ Q9: Kubelet authorization mode fixed (+6)"
        ((SCORE+=6))
    fi

    # Q10: SBOM - 6 pts
    if [ -f /opt/cks-lab/nginx-sbom.json ]; then
        echo "✅ Q10: SBOM generated (+6)"
        ((SCORE+=6))
    fi

    # Q11: Pod Security Standards - 6 pts
    if kubectl get ns frontend --show-labels 2>/dev/null | grep -q "pod-security.kubernetes.io/enforce=restricted"; then
        echo "✅ Q11: PSS enforce restricted applied (+6)"
        ((SCORE+=6))
    fi

    # Q12: ServiceAccount Token - 6 pts
    if [[ $(kubectl get sa db-sa -n database -o jsonpath='{.automountServiceAccountToken}' 2>/dev/null) == "false" ]]; then
        echo "✅ Q12: Automount ServiceAccount token disabled (+6)"
        ((SCORE+=6))
    fi

    # Q13: Auditing - 6 pts
    if grep -q "audit-policy-file" /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null; then
        echo "✅ Q13: Audit logging enabled (+6)"
        ((SCORE+=6))
    fi

    # Q14: SHA512SUM Verification - 5 pts
    if [ ! -f /opt/cks-lab/kube-apiserver ] && [ -d /opt/cks-lab ]; then
        echo "✅ Q14: Compromised binary deleted (+5)"
        ((SCORE+=5))
    fi

    # Q15: Trivy Image Scan - 6 pts
    if [[ $(kubectl get deploy web-server -n dmz -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null) == "httpd:2.4.58" ]]; then
        echo "✅ Q15: Vulnerable image updated (+6)"
        ((SCORE+=6))
    fi

    # Q16: RootOnlyFileSystem - 5 pts
    if [[ $(kubectl get pod immutable-pod -n default -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}' 2>/dev/null) == "true" ]]; then
        echo "✅ Q16: ReadOnlyRootFilesystem enforced (+5)"
        ((SCORE+=5))
    fi

    # Q17: Secrets Encryption at Rest - 6 pts
    if grep -q "encryption-provider-config" /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null; then
        echo "✅ Q17: Encryption at rest configured (+6)"
        ((SCORE+=6))
    fi

    echo "---------------------------"
    echo "FINAL SCORE: $SCORE / 100"
    
    if [ $SCORE -ge 67 ]; then
        echo "🎉 Result: PASS"
    else
        echo "❌ Result: FAIL"
    fi
}

case "$1" in
    start) start_exam ;;
    score) score_exam ;;
    time) cat .remaining_time 2>/dev/null || echo "Not running." ;;
    cleanup) ./exam-cleanup.sh ;;
    *) echo "Usage: ./k8s-sim.sh {start|score|time|cleanup}" ;;
esac
