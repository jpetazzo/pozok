#!/bin/sh
SCALE=${2-1}
CLIENTS=${3-1}
export STORAGECLASS=$1
export NAME=pgbench-$STORAGECLASS

[ "$STORAGECLASS" ] || {
  echo "Please specify storage class as first argument."
  exit 1
}

envsubst < cluster-pgbench.yaml | kubectl apply -f-
kubectl wait cluster $NAME --for=condition=Ready --timeout=5m
./benchmark-cluster.sh "$NAME" "$SCALE" "$CLIENTS" \
  | tee "out.sc=$STORAGECLASS.scale=$SCALE.clients=$CLIENTS.run=$RANDOM"
kubectl delete cluster $NAME
