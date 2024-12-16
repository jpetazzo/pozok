#!/bin/sh
set -eu
CLUSTER_NAME=$1

kubectl patch cluster $CLUSTER_NAME --type=merge --patch="
spec:
  backup:
    volumeSnapshot:
      className: zfs
"
