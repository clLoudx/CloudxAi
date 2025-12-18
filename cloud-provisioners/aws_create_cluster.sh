#!/usr/bin/env bash
set -euo pipefail

assert_cmd eksctl

CLUSTER_NAME=${1:-aiagent-prod}

eksctl create cluster --name "$CLUSTER_NAME" --region eu-central-1

./oneclick_cluster_install.sh

