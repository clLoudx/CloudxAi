#!/usr/bin/env bash
set -euo pipefail

assert_cmd doctl

CLUSTER_NAME=${1:-aiagent-prod}

doctl kubernetes cluster create "$CLUSTER_NAME" --region fra1 --version latest --wait
doctl kubernetes cluster kubeconfig save "$CLUSTER_NAME"

./oneclick_cluster_install.sh

