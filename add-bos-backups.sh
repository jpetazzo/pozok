#!/bin/sh
set -eu
CLUSTER_NAME=$1
SECRET_NAME=${CLUSTER_NAME}-bos

kubectl apply -f- <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: $SECRET_NAME
stringData:
  AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY: $AWS_SECRET_ACCESS_KEY
  AWS_DEFAULT_REGION: $AWS_DEFAULT_REGION
EOF

kubectl patch cluster $CLUSTER_NAME --type=merge --patch="
spec:
  backup:
    retentionPolicy: 15d
    barmanObjectStore:
      destinationPath: s3://$BUCKET_NAME/
      endpointURL: $AWS_ENDPOINT_URL
      data:
        compression: bzip2
      wal:
        compression: bzip2
      s3Credentials:
        accessKeyId:
          name: $SECRET_NAME
          key: AWS_ACCESS_KEY_ID
        secretAccessKey:
          name: $SECRET_NAME
          key: AWS_SECRET_ACCESS_KEY
        region:
          name: $SECRET_NAME
          key: AWS_DEFAULT_REGION
"
