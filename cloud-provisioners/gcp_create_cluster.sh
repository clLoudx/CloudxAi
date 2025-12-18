#!/usr/bin/env bash
set -euo pipefail

assert_cmd gcloud

CLUSTER_NAME=${1:-aiagent-prod}

gcloud container clusters create "$CLUSTER_NAME" \
    --zone europe-west1-b \
    --num-nodes 3

gcloud container clusters get-credentials "$CLUSTER_NAME" --zone europe-west1-b

./oneclick_cluster_install.sh

