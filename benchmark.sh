#!/bin/sh
[ "$1" ] || {
  echo "Syntax:"
  echo "$0 cluster <cluster> [scale] [clients]"
  echo "$0 storageclass <storageclass> [scale] [clients] [size] [description]"
  echo "$0 ALL [scale] [clients] [size] [description]"
  exit 1
}

_set_vars () {
  SCALE=${1-1}
  CLIENTS=${2-1}
  SIZE=${3-10G}
  DESCRIPTION=${4-$(date +%Y-%m-%d_%H:%M:%S)}
  DURATION=60
}

_benchmark_cluster () {
  kubectl exec $NAME-1 -- sh -c "
    set -e
    pgbench -i -s $SCALE
    pgbench -P 1 -T $DURATION --client $CLIENTS
    echo ''
    echo 'Disk usage:'
    du -sh /var/lib/postgresql
    echo 'Disk usage (apparent):'
    du -sh --apparent-size /var/lib/postgresql
    "
}

_benchmark_storageclass () {
  NAME=pgbench-$STORAGECLASS
  kubectl apply -f- <<YAML
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: $NAME
spec:
  instances: 1
  resources:
    requests:
      cpu: 1
      memory: 4G
  storage:
    size: $SIZE
    storageClass: $STORAGECLASS
  #walStorage:
  #  size: $SIZE
  #  storageClass: $STORAGECLASS
  postgresql:
    parameters:
      full_page_writes: "off"
  #    wal_init_zero: "off" # zero-fill new WAL files
  #    wal_recycle: "off" # recycle WAL files
YAML

  kubectl wait cluster $NAME --for=condition=Ready --timeout=5m
  OUTPUT_DIR="benchmarks/$DESCRIPTION"
  OUTPUT_FILE="$OUTPUT_DIR/sc=$STORAGECLASS,scale=$SCALE,clients=$CLIENTS,size=$SIZE"
  mkdir -p "$OUTPUT_DIR"
  _benchmark_cluster | tee "$OUTPUT_FILE"
  kubectl delete cluster $NAME
}

_benchmark_ALL () {
  for STORAGECLASS in $(kubectl get storageclasses -o name | cut -d/ -f2); do
    _benchmark_storageclass
  done
}

WHAT=$1

if [ "$WHAT" = "cluster" ]; then
  NAME=$2
  shift 2
  _set_vars "$@"
  _benchmark_cluster
fi

if [ "$WHAT" = "storageclass" ]; then
  STORAGECLASS=$2
  shift 2
  _set_vars "$@"
  _benchmark_storageclass
fi

if [ "$WHAT" = "ALL" ]; then
  shift
  _set_vars "$@"
  _benchmark_ALL
fi
