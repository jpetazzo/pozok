#!/bin/sh
set -eu
kubectl patch cluster $1 --type=merge --patch "
spec:
  monitoring:
    enablePodMonitor: true
"
