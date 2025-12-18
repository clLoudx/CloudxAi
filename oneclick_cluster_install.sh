#!/usr/bin/env bash
# oneclick_cluster_install.sh — provisions (optional cloud) + installs cert-manager + ingress-nginx + redis + deploys Helm chart
# Usage: sudo ./oneclick_cluster_install.sh --kubeconfig ~/.kube/config --namespace aiagent --image-pull-secret my-secret --helm-values path
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
NAMESPACE="${NAMESPACE:-aiagent}"
IMAGE_PULL_SECRET="${IMAGE_PULL_SECRET:-}"
HELM_VALUES_FILE="${HELM_VALUES_FILE:-}"
# parse args
while [ $# -gt 0 ]; do case "$1" in --kubeconfig) KUBECONFIG="$2"; shift 2;; --namespace) NAMESPACE="$2"; shift 2;; --image-pull-secret) IMAGE_PULL_SECRET="$2"; shift 2;; --helm-values) HELM_VALUES_FILE="$2"; shift 2;; --help) echo "See file header"; exit 0;; *) shift;; esac; done
set +e
command -v kubectl >/dev/null 2>&1 || { echo "kubectl missing"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "helm missing"; exit 1; }
set -e
echo "Ensuring namespace: $NAMESPACE"
kubectl --kubeconfig "$KUBECONFIG" create namespace "$NAMESPACE" 2>/dev/null || true
echo "Installing cert-manager (if missing)"
kubectl --kubeconfig "$KUBECONFIG" -n cert-manager get deployment cert-manager >/dev/null 2>&1 || helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1
if ! kubectl --kubeconfig "$KUBECONFIG" -n cert-manager get deploy cert-manager >/dev/null 2>&1; then
  helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set installCRDs=true --wait --timeout 5m
fi
echo "Installing ingress-nginx"
if ! kubectl --kubeconfig "$KUBECONFIG" -n ingress-nginx get deploy ingress-nginx-controller >/dev/null 2>&1; then
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1
  helm repo update >/dev/null 2>&1
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace --wait --timeout 5m
fi
echo "Installing Redis (helm bitnami)"
helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1
helm repo update >/dev/null 2>&1
helm upgrade --install aiagent-redis bitnami/redis --namespace "$NAMESPACE" --create-namespace --wait --timeout 5m
# prepare imagePullSecret
if [ -n "$IMAGE_PULL_SECRET" ]; then echo "Ensure imagePullSecret present in $NAMESPACE (must exist already)"; kubectl --kubeconfig "$KUBECONFIG" -n "$NAMESPACE" patch serviceaccount default -p "{\"imagePullSecrets\":[{\"name\":\"$IMAGE_PULL_SECRET\"}]}" || true; fi
# Deploy our Helm chart (from repo devops/helm/aiagent)
echo "Deploying aiagent helm chart"
CHART_DIR="$REPO_ROOT/devops/helm/aiagent"
EXTRA=""
[ -n "$HELM_VALUES_FILE" ] && EXTRA="-f $HELM_VALUES_FILE"
helm upgrade --install aiagent "$CHART_DIR" -n "$NAMESPACE" $EXTRA --wait --timeout 10m
echo "Waiting for pods..." 
kubectl --kubeconfig "$KUBECONFIG" -n "$NAMESPACE" rollout status deploy -l app.kubernetes.io/name=aiagent --timeout=600s || true
echo "Post-deploy smoke"
if [ -f "$REPO_ROOT/devops/tools/post_deploy_smoke.sh" ]; then bash "$REPO_ROOT/devops/tools/post_deploy_smoke.sh" "$NAMESPACE" "aiagent-web" "/healthz" 8000 120 || true; fi
echo "oneclick cluster install complete"
exit 0

