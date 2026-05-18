#!/bin/bash
# k8s-sim.sh - Gabriel Exam (Lab 2 Synchronized - 17 Questions)

LAB_ROOT="$HOME/ckad-lab"
DURATION=120

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
    echo "  🚀 CKAD ULTIMATE SIMULATOR STARTED (17 QUESTIONS) 🚀"
    echo "------------------------------------------------------------"
    echo "⏰ Time remaining: 120 minutes"
    echo "👉 Score your work:  ./k8s-sim.sh score"
    echo "👉 Check timer:      ./k8s-sim.sh time"
}

function score_exam() {
    SCORE=0
    echo "📊 --- CKAD SCORE REPORT ---"

    # Q1: Secret Ref (Target: secret-api-deploy) - 5 pts
    [[ $(kubectl get deploy secret-api-deploy -n default -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="DB_HOST")].valueFrom.secretKeyRef.name}' 2>/dev/null) == "db-credentials" ]] && { echo "✅ Q1: Database Secret linked (+5)"; ((SCORE+=5)); }

    # Q2: CronJob (Target: backup-job) - 6 pts
    [[ $(kubectl get cj backup-job -o jsonpath='{.spec.successfulJobsHistoryLimit}' 2>/dev/null) == "3" ]] && { echo "✅ Q2: CronJob configured (+6)"; ((SCORE+=6)); }

    # Q3: Audit RBAC (Target: log-collector) - 6 pts
    [[ $(kubectl get pod log-collector -n audit -o jsonpath='{.spec.serviceAccountName}' 2>/dev/null) == "log-sa" ]] && { echo "✅ Q3: Audit RBAC fixed (+6)"; ((SCORE+=6)); }

    # Q4: Monitoring RBAC (Target: metrics-pod) - 6 pts
    [[ $(kubectl get pod metrics-pod -n monitoring -o jsonpath='{.spec.serviceAccountName}' 2>/dev/null) == "monitor-sa" ]] && { echo "✅ Q4: Monitoring SA fixed (+6)"; ((SCORE+=6)); }

    # Q5: Image Build (Target: /tmp/my-app.tar) - 5 pts
    [[ -f /tmp/my-app.tar ]] && { echo "✅ Q5: Image saved as tarball (+5)"; ((SCORE+=5)); }

    # Q6: Canary (Target: web-app-canary) - 6 pts
    [[ $(kubectl get deploy web-app-canary -o jsonpath='{.spec.replicas}' 2>/dev/null) == "2" ]] && { echo "✅ Q6: Canary created (+6)"; ((SCORE+=6)); }

    # Q7: NetPol Labels (Target: pods in network-demo) - 6 pts
    [[ $(kubectl get pod frontend -n network-demo --show-labels 2>/dev/null) == *"role=frontend"* ]] && { echo "✅ Q7: NetPol labels fixed (+6)"; ((SCORE+=6)); }

    # Q8: Broken YAML (Target: broken-app) - 6 pts
    [[ $(kubectl get deploy broken-app -o jsonpath='{.status.readyReplicas}' 2>/dev/null) -gt 0 ]] && { echo "✅ Q8: Broken YAML deployment running (+6)"; ((SCORE+=6)); }

    # Q9: Rollback (Target: rolling-update-app) - 6 pts
    [[ $(kubectl get deploy rolling-update-app -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null) == "nginx:1.20" ]] && { echo "✅ Q9: Rollback verified (+6)"; ((SCORE+=6)); }

    # Q10: Readiness (Target: readiness-api-deploy) - 6 pts
    [[ -n $(kubectl get deploy readiness-api-deploy -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}' 2>/dev/null) ]] && { echo "✅ Q10: Readiness probe added (+6)"; ((SCORE+=6)); }

    # Q11: SecContext (Target: security-context-app) - 6 pts
    [[ $(kubectl get deploy security-context-app -o jsonpath='{.spec.template.spec.securityContext.runAsUser}' 2>/dev/null) == "1000" ]] && { echo "✅ Q11: SecurityContext configured (+6)"; ((SCORE+=6)); }

    # Q12: Svc Selector (Target: web-svc) - 6 pts
    [[ -n $(kubectl get ep web-svc -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null) ]] && { echo "✅ Q12: Svc Selector fixed (+6)"; ((SCORE+=6)); }

    # Q13: NodePort (Target: api-nodeport) - 6 pts
    [[ $(kubectl get svc api-nodeport -o jsonpath='{.spec.type}' 2>/dev/null) == "NodePort" ]] && { echo "✅ Q13: NodePort created (+6)"; ((SCORE+=6)); }

    # Q14: Ingress (Target: web-ingress) - 6 pts
    [[ $(kubectl get ingress web-ingress -o jsonpath='{.spec.rules[0].host}' 2>/dev/null) == "web.example.com" ]] && { echo "✅ Q14: Ingress host set (+6)"; ((SCORE+=6)); }

    # Q15: Ingress PathType (Target: api-ingress) - 4 pts
    [[ $(kubectl get ingress api-ingress -o jsonpath='{.spec.rules[0].http.paths[0].pathType}' 2>/dev/null) == "Prefix" ]] && { echo "✅ Q15: Ingress PathType fixed (+4)"; ((SCORE+=4)); }

    # Q16: Quota Math (Target: resource-pod in prod) - 4 pts
    # Checks if limit is half of the 2 CPU quota
    [[ $(kubectl get pod resource-pod -n prod -o jsonpath='{.spec.containers[0].resources.limits.cpu}' 2>/dev/null) == "1" ]] && { echo "✅ Q16: Resource math correct (+4)"; ((SCORE+=4)); }

    # Q17: Build and Export as OCI Archive - 4 pts
    if [ -f /tmp/internal-tool-oci.tar ]; then
        # Use tar -tf to peek inside and see if it looks like an OCI archive
        IS_OCI=$(tar -tf /tmp/internal-tool-oci.tar | grep -E "index.json|oci-layout" | wc -l)
        if [ $IS_OCI -ge 1 ]; then
            echo "✅ Q17: Image exported in OCI format (+4)"
            ((SCORE+=4))
        fi
    fi

    # Q18: Mount PVC in a Pod
    VOL_NAME=$(kubectl get pod nginx-storage-pod -n default -o jsonpath='{.spec.volumes[?(@.persistentVolumeClaim.claimName=="pvc-data")].name}' 2>/dev/null)
    if [ -n "$VOL_NAME" ]; then
        MOUNT_PATH=$(kubectl get pod nginx-storage-pod -n default -o jsonpath="{.spec.containers[0].volumeMounts[?(@.name==\"$VOL_NAME\")].mountPath}" 2>/dev/null)
        [[ "$MOUNT_PATH" == "/usr/share/nginx/html" ]] && { echo "✅ Q18: PVC mounted correctly (+6)"; ((SCORE+=6)); }
    fi

    echo "---------------------------"
    echo "FINAL SCORE: $SCORE / 100"
    
    if [ $SCORE -ge 66 ]; then
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
