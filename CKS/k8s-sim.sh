#!/bin/bash
# k8s-sim.sh - CKS Simulator

DURATION=120
CKS_DIR="/opt/cks-lab"

function start_exam() {
    chmod +x exam-cleanup.sh exam-setup.sh
    ./exam-cleanup.sh
    ./exam-setup.sh
    (
        seconds=$((DURATION * 60))
        while [ $seconds -gt 0 ]; do
            printf "%02d:%02d:%02d" $((seconds/3600)) $(( (seconds/60)%60 )) $((seconds%60)) > .remaining_time
            sleep 1
            ((seconds--))
        done
        echo "EXPIRED" > .remaining_time
    ) &
    echo $! > .timer_pid
    clear
    echo "------------------------------------------------------------"
    echo "  🔒 CKS ULTIMATE SIMULATOR STARTED (10 QUESTIONS) 🔒"
    echo "------------------------------------------------------------"
    echo "⏰ Time remaining: 120 minutes"
    echo "👉 Score your work:  ./k8s-sim.sh score"
    echo "👉 Check timer:      ./k8s-sim.sh time"
}

function score_exam() {
    SCORE=0
    echo "📊 --- CKS SCORE REPORT ---"

    # Q1: Pod Security (10 pts)
    local pod_sec=$(kubectl get deploy restricted-deploy -o jsonpath='{.spec.template.spec.securityContext.runAsNonRoot}' 2>/dev/null)
    local cont_sec_priv=$(kubectl get deploy restricted-deploy -o jsonpath='{.spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation}' 2>/dev/null)
    local cont_sec_drop=$(kubectl get deploy restricted-deploy -o jsonpath='{.spec.template.spec.containers[0].securityContext.capabilities.drop[0]}' 2>/dev/null)
    if [[ "$pod_sec" == "true" && "$cont_sec_priv" == "false" && "$cont_sec_drop" == "ALL" ]]; then
        echo "✅ Q1: Pod Security Hardening correct (+10)"; ((SCORE+=10))
    fi

    # Q2: API Server Hardening (10 pts)
    if grep -q "\--anonymous-auth=false" "$CKS_DIR/kube-apiserver.yaml" 2>/dev/null && grep -q "\--authorization-mode=Node,RBAC" "$CKS_DIR/kube-apiserver.yaml" 2>/dev/null; then
        echo "✅ Q2: API Server Authorization fixed (+10)"; ((SCORE+=10))
    fi

    # Q3: Audit Logging (10 pts)
    if grep -q "\--audit-policy-file" "$CKS_DIR/kube-apiserver.yaml" 2>/dev/null && grep -q "\--audit-log-path" "$CKS_DIR/kube-apiserver.yaml" 2>/dev/null; then
        echo "✅ Q3: Audit Logging configured (+10)"; ((SCORE+=10))
    fi

    # Q4: Admission Controller (10 pts)
    if grep -q "ImagePolicyWebhook" "$CKS_DIR/kube-apiserver.yaml" 2>/dev/null && grep -q "\--admission-control-config-file" "$CKS_DIR/kube-apiserver.yaml" 2>/dev/null; then
        echo "✅ Q4: ImagePolicyWebhook enabled (+10)"; ((SCORE+=10))
    fi

    # Q5: Network Policies (10 pts)
    if [[ $(kubectl get pod frontend -n net-block --show-labels 2>/dev/null) == *"app=frontend"* && $(kubectl get pod database -n net-block --show-labels 2>/dev/null) == *"app=db"* ]]; then
        echo "✅ Q5: Network Policy labels fixed (+10)"; ((SCORE+=10))
    fi

    # Q6: Docker/Node Hardening (10 pts)
    if ! grep -q "0.0.0.0:2375" "$CKS_DIR/daemon.json" 2>/dev/null && ! grep -q "hacker" "$CKS_DIR/group" 2>/dev/null; then
        echo "✅ Q6: Node & Docker Hardening completed (+10)"; ((SCORE+=10))
    fi

    # Q7: Runtime Security (10 pts)
    if ! kubectl get pod crypto-miner -n runtime-sec >/dev/null 2>&1; then
        echo "✅ Q7: Misbehaving workload isolated/deleted (+10)"; ((SCORE+=10))
    fi

    # Q8: ServiceAccount Security (10 pts)
    local auto_mount=$(kubectl get deploy token-deploy -o jsonpath='{.spec.template.spec.automountServiceAccountToken}' 2>/dev/null)
    local proj_vol=$(kubectl get deploy token-deploy -o jsonpath='{.spec.template.spec.volumes[0].projected.sources[0].serviceAccountToken.path}' 2>/dev/null)
    if [[ "$auto_mount" == "false" && -n "$proj_vol" ]]; then
        echo "✅ Q8: Projected SA Token configured (+10)"; ((SCORE+=10))
    fi

    # Q9: SBOM (10 pts)
    local has_main=$(kubectl get pod webapp-pod -o jsonpath='{.spec.containers[?(@.name=="main-app")].name}' 2>/dev/null)
    local has_vuln=$(kubectl get pod webapp-pod -o jsonpath='{.spec.containers[?(@.name=="vulnerable-sidecar")].name}' 2>/dev/null)
    if [[ "$has_main" == "main-app" && -z "$has_vuln" ]]; then
        echo "✅ Q9: Vulnerable container removed (+10)"; ((SCORE+=10))
    fi

    # Q10: Istio mTLS (10 pts)
    local istio_lbl=$(kubectl get ns istio-prod -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null)
    if [[ "$istio_lbl" == "enabled" && -f "$CKS_DIR/mtls.yaml" ]] && grep -q "STRICT" "$CKS_DIR/mtls.yaml" 2>/dev/null; then
        echo "✅ Q10: Istio mTLS STRICT policy drafted and NS labeled (+10)"; ((SCORE+=10))
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
