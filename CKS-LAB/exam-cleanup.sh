#!/bin/bash
# exam-cleanup.sh - Tears down the mock environment for the CKS Simulator

echo "Cleaning up CKS Simulator Environment..."

rm -rf /opt/cks-lab/
rm -f /etc/kubernetes/audit-policy.yaml
rm -f /etc/kubernetes/enc/encryption.yaml
rm -f /var/log/falco.log
rm -f /var/lib/kubelet/config.yaml

echo "Cleanup complete."
