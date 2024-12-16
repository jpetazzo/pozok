#!/bin/sh
set -eu
BACKUP_NAME=$1
NEW_CLUSTER_NAME=$2

OLD_CLUSTER_NAME=$(kubectl get backup $BACKUP_NAME -o jsonpath={.spec.cluster.name})

kubectl get cluster $OLD_CLUSTER_NAME -o yaml |
  kubectl neat |
  kubectl patch --dry-run=client -o yaml -f- --local --type=merge --patch="
  metadata:
    name: $NEW_CLUSTER_NAME
  spec:
    bootstrap: null
  " |
  kubectl patch --dry-run=client -o yaml -f- --local --type=merge --patch="
  spec:
    bootstrap:
      recovery:
        backup:
          name: $BACKUP_NAME
  " |
  kubectl apply -f-

