#!/bin/sh
set -e
[ "$CLUSTER_NAME" ] || {
  echo -n export CLUSTER_NAME=
  read CLUSTER_NAME
}
[ "$PBF_URL" ] || {
  echo "# Pick a PBF file from e.g. one of the following sources:"
  echo "# https://download.openstreetmap.fr/extracts/"
  echo "# https://download.geofabrik.de/"
  echo -n export PBF_URL=
  read PBF_URL
}
POD_NAME=$CLUSTER_NAME-loader

kubectl apply -f- <<YAML
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: $CLUSTER_NAME
  labels:
    osm: $CLUSTER_NAME
spec:
  imageName: ghcr.io/cloudnative-pg/postgis:17
  instances: 2
  storage:
    size: 50Gi
    storageClass: zfs-cnpg
  #walStorage:
  #  size: 50G
  #  storageClass: zfs-lz4
  bootstrap:
    initdb:
      postInitTemplateSQL:
      - CREATE EXTENSION postgis;
      - CREATE EXTENSION postgis_topology;
      - CREATE EXTENSION fuzzystrmatch;
      - CREATE EXTENSION postgis_tiger_geocoder;
YAML

kubectl wait cluster $CLUSTER_NAME --for=condition=Ready --timeout=5m

kubectl apply -f- <<YAML
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: pbfdata
  labels:
    osm: pbfdata
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 50G
YAML

kubectl apply -f- <<YAML
---
apiVersion: v1
kind: Pod
metadata:
  name: $POD_NAME
  labels:
    osm: $POD_NAME
spec:
  terminationGracePeriodSeconds: 3
  volumes:
  - name: pbfdata
    persistentVolumeClaim:
      claimName: pbfdata
  containers:
  - image: iboates/osm2pgsql
    name: osm2pgsql
    workingDir: /pbfdata
    stdin: true
    tty: true
    command:
    - sh
    volumeMounts:
    - name: pbfdata
      mountPath: /pbfdata
    envFrom:
    - secretRef:
        name: $CLUSTER_NAME-app
YAML

kubectl wait pod $POD_NAME --for=condition=Ready --timeout=5m

kubectl exec $POD_NAME -- wget --continue "$PBF_URL"

PBF_FILE="$(basename "$PBF_URL")"

kubectl exec $POD_NAME -- sh -c 'osm2pgsql --database $uri '"$PBF_FILE"

