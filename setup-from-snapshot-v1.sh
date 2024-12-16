#!/bin/sh
set -eu
BACKUP_NAME=$1
NEW_CLUSTER_NAME=$2

RESTORE_SIZE="$(
  kubectl get volumesnapshot $BACKUP_NAME -o json | 
  jq -r .status.restoreSize
)"

IMAGE_NAME="$(
  kubectl get volumesnapshot $BACKUP_NAME -o json |
  jq -r '.metadata.annotations["cnpg.io/clusterManifest"]' |
  jq -r .spec.imageName
)"

kubectl apply -f- <<YAML
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: $NEW_CLUSTER_NAME
spec:
  instances: 1
  imageName: $IMAGE_NAME

  bootstrap:
    recovery:
      backup:
        name: $BACKUP_NAME
      #recoveryTarget:
      #  targetTime: "2024-XX-XX XX:XX:XX+00"

  storage:
    size: $RESTORE_SIZE
    storageClass: zfs
YAML
