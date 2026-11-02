#!/bin/bash
set -euo pipefail
EXAM_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LAB_DIR=$(cd -- "$EXAM_DIR/.." && pwd)
# All task file arguments resolve from the shared runtime directory.
cd -- "$LAB_DIR"
case "${1:-}" in
    start)
        shift
        if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != --exam ]; }; then
            echo "Usage: $0 start" >&2; exit 1
        fi
        exec bash "$LAB_DIR/k8s-sim.sh" start --exam
        ;;
    tasks) cat "$EXAM_DIR/EXAM.md" ;;
    score|time|cleanup|kubectl|ssh)
        [ "$(cat "$LAB_DIR/.cks-state/mode" 2>/dev/null || true)" = exam ] || {
            echo "No active second mock. Start it with ./k8s-sim.sh start." >&2
            exit 1
        }
        exec bash "$LAB_DIR/k8s-sim.sh" "$@"
        ;;
    *) echo "Usage: $0 {start|tasks|score|time|cleanup|kubectl ...|ssh [--node NAME] [command]}"; exit 1 ;;
esac
