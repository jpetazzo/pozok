#!/bin/sh
export NAME=$1
SCALE=${2-1}
CLIENTS=${3-1}
DURATION=60

kubectl exec $NAME-1 -- sh -c "
  set -e
  pgbench -i -s $SCALE
  pgbench -P 1 -T $DURATION --client $CLIENTS
  echo 'Disk usage:'
  du -sh /var/lib/postgresql
  echo 'Disk usage (apparent):'
  du -sh --apparent-size /var/lib/postgresql
  "
