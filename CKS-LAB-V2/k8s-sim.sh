#!/bin/bash
# k8s-sim.sh - CKS Version 2 Scoring Engine

DURATION=120
CKS_DIR="/opt/cks-lab-v2"

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
    echo "  🔒 CKS V2 ULTIMATE SIMULATOR (16 QUESTIONS) 🔒"
    echo "------------------------------------------------------------"
    echo "⏰ Time remaining: 120 minutes"
    echo "👉 Score your work:  ./k8s-sim.sh score"
}

function score_exam() {
    SCORE=0
    echo "📊 --- CKS V2 SCORE REPORT ---"

    # Q1: Insecure Kubelet & etcd (6 pts)
    if grep -q "enabled: false" "$CKS_DIR/kubelet-config.yaml" 2>/dev/null && grep -q "mode: Webhook" "$CKS_DIR/kubelet-config.yaml" 2>/dev/null; then
        echo "✅ Q1: Kubelet secured (+6)"; ((SCORE+=6))
    fi

    # Q2: TLS Secret (6 pts)
    if kubectl get secret tls-secret -n default >/dev/null 2>&1; then
        echo "✅ Q2: TLS Secret created (+6)"; ((SCORE+=6))
    fi

    # Q3: Dockerfile & Deployment Security (6 pts)
    local d_usr=$(kubectl get deploy docker-deploy -o jsonpath='{.spec.template.spec.securityContext.runAsUser}' 2>/dev/null)
    local d_ro=$(kubectl get deploy docker-deploy -o jsonpath='{.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem}' 2>/dev/null)
    local d_priv=$(kubectl get deploy docker-deploy -o jsonpath='{.spec.template.spec.containers[0].securityContext.privileged}' 2>/dev/null)
    if grep -q "USER nobody" /tmp/cks-q3/Dockerfile 2>/dev/null && [[ "$d_usr" == "65535" && "$d_ro" == "true" && "$d_priv" == "false" ]]; then
        echo "✅ Q3: Dockerfile and Deployment secured (+6)"; ((SCORE+=6))
    fi

    # Q4: Falco /dev/mem isolation (6 pts)
    if [[ $(kubectl get deploy mem-hacker -o jsonpath='{.spec.replicas}' 2>/dev/null) == "0" ]]; then
        echo "✅ Q4: Bad Pod scaled to 0 (+6)"; ((SCORE+=6))
    fi

    # Q5: Container Security Context (6 pts)
    local i_usr=$(kubectl get deploy immutable-deploy -o jsonpath='{.spec.template.spec.securityContext.runAsUser}' 2>/dev/null)
    local i_ro=$(kubectl get deploy immutable-deploy -o jsonpath='{.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem}' 2>/dev/null)
    local i_esc=$(kubectl get deploy immutable-deploy -o jsonpath='{.spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation}' 2>/dev/null)
    if [[ "$i_usr" == "30000" && "$i_ro" == "true" && "$i_esc" == "false" ]]; then
        echo "✅ Q5: Container Immutability enforced (+6)"; ((SCORE+=6))
    fi

    # Q6: Audit Logging (6 pts)
    if grep -q "\--audit-log-maxbackup=" "$CKS_DIR/kube-apiserver.yaml" 2>/dev/null && grep -q "\--audit-log-maxage=" "$CKS_DIR/kube-apiserver.yaml" 2>/dev/null; then
        echo "✅ Q6: Audit log retention configured (+6)"; ((SCORE+=6))
    fi

    # Q7: NetworkPolicy (6 pts)
    if kubectl get netpol -n qa >/dev/null 2>&1; then
        echo "✅ Q7: NetworkPolicy configured in QA (+6)"; ((SCORE+=6))
    fi

    # Q8: Expose HTTPS via Ingress (6 pts)
    local ssl_redir=$(kubectl get ingress https-ingress -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/ssl-redirect}' 2>/dev/null)
    if [[ "$ssl_redir" == "true" ]]; then
        echo "✅ Q8: Ingress TLS and SSL-redirect configured (+6)"; ((SCORE+=6))
    fi

    # Q9: Disable API auto-mounting (6 pts)
    local sa_mount=$(kubectl get sa vault-sa -o jsonpath='{.automountServiceAccountToken}' 2>/dev/null)
    local p_vol=$(kubectl get deploy vault-sa-deploy -o jsonpath='{.spec.template.spec.volumes[0].projected.sources[0].serviceAccountToken.path}' 2>/dev/null)
    if [[ "$sa_mount" == "false" && -n "$p_vol" ]]; then
        echo "✅ Q9: SA auto-mount disabled and projected volume used (+6)"; ((SCORE+=6))
    fi

    # Q10: Node Upgrade (7 pts)
    # *Note: Scoring checks if node01 is cordoned. If you don't have a node01 locally, it awards points automatically.*
    if kubectl get node node01 >/dev/null 2>&1; then
        if [[ $(kubectl get node node01 -o jsonpath='{.spec.unschedulable}') == "true" ]]; then
            echo "✅ Q10: Node01 cordoned for upgrade (+7)"; ((SCORE+=7))
        fi
    else
        echo "✅ Q10: (Auto-Pass) No node01 found in local cluster to drain (+7)"; ((SCORE+=7))
    fi

    # Q11: Generate SPDX (7 pts)
    local lib_c=$(kubectl get pod crypto-pod -o jsonpath='{.spec.containers[?(@.name=="libcrypto-container")].name}' 2>/dev/null)
    if [[ -f /tmp/cks-q3/alpine.spdx && -z "$lib_c" ]]; then
        echo "✅ Q11: SPDX generated and vulnerable container removed (+7)"; ((SCORE+=7))
    fi

    # Q12: Restricted PSS (7 pts)
    local violator_ready=$(kubectl get deploy violator-deploy -n restricted-ns -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    if [[ "$violator_ready" -gt 0 ]]; then
        echo "✅ Q12: PSS restrictions resolved, deployment running (+7)"; ((SCORE+=7))
    fi

    # Q13: Secure Docker Daemon (6 pts)
    local d_owner=$(stat -c "%U" $CKS_DIR/docker.sock 2>/dev/null)
    if ! grep -q "devuser" "$CKS_DIR/group" 2>/dev/null && [[ "$d_owner" == "root" ]]; then
        echo "✅ Q13: Docker daemon secured (+6)"; ((SCORE+=6))
    fi

    # Q14: Cilium Network Policy (6 pts)
    if [ -f "$CKS_DIR/cilium-policy.yaml" ] && grep -q "CiliumNetworkPolicy" "$CKS_DIR/cilium-policy.yaml" 2>/dev/null; then
        echo "✅ Q14: Cilium Policy file created (+6)"; ((SCORE+=6))
    fi

    # Q15: ImagePolicyWebhook (6 pts)
    if grep -q "defaultAllow: false" "$CKS_DIR/admission-config.yaml" 2>/dev/null; then
        echo "✅ Q15: ImagePolicyWebhook defaultAllow set to false (+6)"; ((SCORE+=6))
    fi

    # Q16: API Server Auth (7 pts)
    if grep -q "\--anonymous-auth=false" "$CKS_DIR/kube-apiserver.yaml" 2>/dev/null && grep -q "\--authorization-mode=Node,RBAC" "$CKS_DIR/kube-apiserver.yaml" 2>/dev/null && grep -q "\--enable-admission-plugins=NodeRestriction" "$CKS_DIR/kube-apiserver.yaml" 2>/dev/null; then
        echo "✅ Q16: API Server Auth secured (+7)"; ((SCORE+=7))
    fi

    echo "---------------------------"
    echo "FINAL SCORE: $SCORE / 100"
    [[ $SCORE -ge 67 ]] && echo "🎉 Result: PASS" || echo "❌ Result: FAIL"
}

case "$1" in
    start) start_exam ;;
    score) score_exam ;;
    time) cat .remaining_time 2>/dev/null || echo "Not running." ;;
    cleanup) ./exam-cleanup.sh ;;
    *) echo "Usage: ./k8s-sim.sh {start|score|time|cleanup}" ;;
esac
