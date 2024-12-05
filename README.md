# PoZoK

PostgreSQL on ZFS on Kubernetes

I've seen on [that page](https://vadosware.io/post/everything-ive-seen-on-optimizing-postgres-on-zfs-on-linux/) that PoZoL was "PostgreSQL on ZFS on Linux", so this is PoZoK - same thing but on Kubernetes, with CNPG.

This is a repository of scripts, manifests, etc., to run/test/demo PostgreSQL on Kubernetes, with [CNPG](https://cloudnative-pg.io/) and [OpenEBS LocalPV-ZFS](https://github.com/openebs/zfs-localpv).

The examples use Linode but are easily adaptable to pretty much any other cloud provider. I'm using Linode because they're affordable (way cheaper than AWS) and their Kubernetes clusters start quickly (way faster than AWS). I've also had success with Digital Ocean, Scaleway; and I also run PostgreSQL production workloads (with CNPG and ZFS) on Hetzner. These are not endorsements; just some random person on the Internet telling you "trust me sib, this works" so take it with a grain of salt and/or a pinch of spice!


## Cluster provisioning

Warning: if you change the node type (e.g. to put a smaller node), you will probably want to change the `"size"` parameter in the disk setup. The size is the size (in MB) of the ZFS partition. It will be subtracted from the system disk. This means that the system disk must be big enough to accommodate a "normal" system partition (say, anything between 10-100 GB depending on the number and size of images, local volumes, etc. that you need) + that ZFS partition.

```
REGION=fr-par

CLUSTER_NAME=lke-db-$RANDOM
lin lke cluster-create --label $CLUSTER_NAME --region $REGION --k8s_version 1.31 \
  --node_pools.type g6-standard-6 \
  --node_pools.count 3 \
  --node_pools.autoscaler.enabled true \
  --node_pools.autoscaler.min 3 \
  --node_pools.autoscaler.max 10 \
  --node_pools.disks '[{"type": "raw", "size": 204800}]' \
  #

CLUSTER_ID=$(lin  lke clusters-list --label $CLUSTER_NAME  --json | jq .[].id)
while ! lin lke kubeconfig-view $CLUSTER_ID; do
  sleep 10
done
lin lke kubeconfig-view $CLUSTER_ID --json | jq -r .[].kubeconfig | base64 -d > kubeconfig.$CLUSTER_ID
export KUBECONFIG=kubeconfig.$CLUSTER_ID
```

## Install ZFS Local-PV

```
helm upgrade --install --namespace zfs-system --create-namespace \
 --repo https://openebs.github.io/zfs-localpv \
 zfs zfs-localpv

k apply -f debian-setup.yaml
k apply -f storageclass.yaml
```

## Install CNPG

```
helm upgrade --install --namespace cnpg-system --create-namespace \
  --repo https://cloudnative-pg.io/charts/ \
  cloudnative-pg cloudnative-pg
```

## Install Rancher Local Path

```
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
```

## Create bucket for CNPG backups

```
BUCKET_NAME=cnpg-backups-$RANDOM
lin obj mb $BUCKET_NAME --cluster $REGION-1
lin object-storage keys-create --label $BUCKET_NAME \
  --bucket_access.bucket_name=$BUCKET_NAME \
  --bucket_access.permissions=read_write \
  --bucket_access.region=$REGION \
  --json > key.$BUCKET_NAME.json

cat > env.$BUCKET_NAME <<EOF
export ACCESS_KEY=$(jq < key.$BUCKET_NAME.json .[0].access_key)
export SECRET_KEY=$(jq < key.$BUCKET_NAME.json .[0].secret_key)
export BUCKET_NAME=$(jq < key.$BUCKET_NAME.json .[0].bucket_access[0].bucket_name)
export S3_ENDPOINT=$(jq < key.$BUCKET_NAME.json .[0].regions[0].s3_endpoint)
EOF
```

Note: some providers require that you specify the region that you will be using. OVH is one of them. Check `env.example.ovh` for an example showing which environment variables should be set; and make sure to pass the `region` field in the backup section of your cluster, too!

## Create some databases

First, a very simple database with just a primary and a replica:

```
kubectl apply -f cluster-minimal.yaml
watch kubectl get clusters,pods
```

Then, a more complex one with backups, separate WAL storage, etc:

```
envsubst < cluster-maximal.yaml | kubectl apply -f-
watch kubectl get clusters,pods
```

## Benchmarks

```
./benchmark-storage-class.sh <storageClassName> [scale] [clients] [size]
```

Where:
- `scale` is the `-s` (scaling) parameter for pgbench (default value: 1)
- `clients` is the `--clients` parameter for pgbench (default value: 1)
- `size` is the size of the PV created for the database (default value: 10G)

This will:
- create a cluster
- wait for the cluster to be up and running
- start a `pgbench` on the primary
- after the `pgbench` it will show the size and apparent size of the database
- delete the cluster

```
./benchmark-cluster.sh <clusterName> [scale] [clients]
```

This will only run the benchmark on the given cluster. It won't create (or destroy) that cluster.

## Clean up the bucket

```
export AWS_ACCESS_KEY_ID=$ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$SECRET_KEY
# Check the content of the bucket
aws s3 --endpoint-url https://$S3_ENDPOINT/ ls s3://$BUCKET_NAME
# Destroy everything in the bucket
aws s3 --endpoint-url https://$S3_ENDPOINT/ rm --recursive s3://$BUCKET_NAME
# Destroy the bucket itself (this is specific to Linode; other providers will use other commands)
lin obj rb $BUCKET_NAME --cluster $REGION-1
```

