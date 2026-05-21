#!/bin/bash
# k8s-sim.sh - Hybrid CKS Simulator for Docker Desktop

DURATION=120
LAB_DIR="/opt/cks-lab"

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
    echo "  🚀 CKS DOCKER DESKTOP SIMULATOR STARTED (17 QUESTIONS) 🚀"
    echo "------------------------------------------------------------"
    echo "⏰ Time remaining: 120 minutes"
    echo "⚠️  Control Plane files are in: $LAB_DIR"
    echo "⚠️  Pod/Deployments/NetPols are live on your cluster!"
    echo "👉 Score your work:  ./k8s-sim.sh score"
    echo "👉 Check timer:      ./k8s-sim.sh time"
    echo "👉 Cleanup exam:     ./k8s-sim.sh cleanup"
}

function score_exam() {
    SCORE=0
    echo "📊 --- CKS SCORE REPORT ---"

    # Q1: Admission Controller (Simulated)
    if grep -q "ImagePolicyWebhook" $LAB_DIR/kube-apiserver.yaml 2>/dev/null && grep -q "NodeRestriction" $LAB_DIR/kube-apiserver.yaml 2>/dev/null; then
        echo "✅ Q1: Admission controllers enabled (+6)"
        ((SCORE+=6))
    fi

    # Q2: Kubeadm Upgrade (Skipped/Auto-Pass for Docker Desktop compatibility)
    echo "✅ Q2: Kubeadm upgraded (Auto-passed for Docker Desktop) (+6)"
    ((SCORE+=6))

    # Q3: NetworkPolicy (Live)
    if kubectl get netpol default-deny-all -n backend 2>/dev/null | grep -q "default-deny-all"; then
        echo "✅ Q3: Default deny network policy created (+6)"
        ((SCORE+=6))
    fi

    # Q4: Falco Runtime Security (Live Pod deletion check)
    if ! kubectl get pod hacker-pod -n web 2>/dev/null | grep -q "hacker-pod"; then
        echo "✅ Q4: Malicious pod deleted (+6)"
        ((SCORE+=6))
    fi

    # Q5: Cilium Network Policy (Live)
    if kubectl get ciliumnetworkpolicy restrict-dns -n app 2>/dev/null | grep -q "restrict-dns"; then
        echo "✅ Q5: Cilium network policy created (+6)"
        ((SCORE+=6))
    fi

    # Q6: Istio mTLS (Live)
    if kubectl get peerauthentication default-strict-mtls -n istio-system 2>/dev/null | grep -q "default-strict-mtls"; then
        echo "✅ Q6: Istio strict mTLS applied (+6)"
        ((SCORE+=6))
    fi

    # Q7: Dockerfile Security (Simulated)
    if grep -q "USER appuser" $LAB_DIR/Dockerfile 2>/dev/null; then
        echo "✅ Q7: Non-root user set in Dockerfile (+6)"
        ((SCORE+=6))
    fi

    # Q8: AppArmor & Seccomp (Live)
    if kubectl get deploy secure-app -n prod -o jsonpath='{.spec.template.metadata.annotations}' 2>/dev/null | grep -q "localhost/custom-profile"; then
        if kubectl get deploy secure-app -n prod -o jsonpath='{.spec.template.spec.securityContext.seccompProfile.type}' 2>/dev/null | grep -q "RuntimeDefault"; then
            echo "✅ Q8: AppArmor and Seccomp profiles configured (+6)"
            ((SCORE+=6))
        fi
    fi

    # Q9: Kube-bench Fixes (Simulated)
    if grep -q "mode: Webhook" $LAB_DIR/kubelet-config.yaml 2>/dev/null; then
        echo "✅ Q9: Kubelet authorization mode fixed (+6)"
        ((SCORE+=6))
    fi

    # Q10: SBOM (Simulated Path)
    if [ -f $LAB_DIR/nginx-sbom.json ]; then
        echo "✅ Q10: SBOM generated (+6)"
        ((SCORE+=6))
    fi

    # Q11: Pod Security Standards (Live)
    if kubectl get ns frontend --show-labels 2>/dev/null | grep -q "pod-security.kubernetes.io/enforce=restricted"; then
        echo "✅ Q11: PSS enforce restricted applied (+6)"
        ((SCORE+=6))
    fi

    # Q12: ServiceAccount Token (Live)
    if [[ $(kubectl get sa db-sa -n database -o jsonpath='{.automountServiceAccountToken}' 2>/dev/null) == "false" ]]; then
        echo "✅ Q12: Automount ServiceAccount token disabled (+6)"
        ((SCORE+=6))
    fi

    # Q13: Auditing (Simulated)
    if grep -q "audit-policy-file" $LAB_DIR/kube-apiserver.yaml 2>/dev/null; then
        echo "✅ Q13: Audit logging enabled (+6)"
        ((SCORE+=6))
    fi

    # Q14: SHA512SUM Verification (Simulated)
    if [ ! -f $LAB_DIR/kube-apiserver-test ] && [ -d $LAB_DIR ]; then
        echo "✅ Q14: Compromised binary deleted (+5)"
        ((SCORE+=5))
    fi

    # Q15: Trivy Image Scan (Live)
    if [[ $(kubectl get deploy web-server -n dmz -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null) == "httpd:2.4.58" ]]; then
        echo "✅ Q15: Vulnerable image updated (+6)"
        ((SCORE+=6))
    fi

    # Q16: RootOnlyFileSystem (Live)
    if [[ $(kubectl get pod immutable-pod -n default -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}' 2>/dev/null) == "true" ]]; then
        echo "✅ Q16: ReadOnlyRootFilesystem enforced (+5)"
        ((SCORE+=5))
    fi

    # Q17: Secrets Encryption at Rest (Simulated)
    if grep -q "encryption-provider-config" $LAB_DIR/kube-apiserver.yaml 2>/dev/null; then
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
