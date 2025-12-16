install_kube_mode() {
    title "AI-Agent Kubernetes Deployment (Helm Mode)"
    assert_cmd kubectl
    assert_cmd helm

    NAMESPACE="${NAMESPACE:-aiagent}"
    RELEASE_NAME="${RELEASE_NAME:-aiagent}"
    CHART_PATH="${CHART_PATH:-./devops/helm/aiagent-web}"  # default web entrypoint
    VALUES_FILE="${VALUES_FILE:-./devops/helm/aiagent-web/values-production.yaml}"

    info "Namespace         = $NAMESPACE"
    info "Release Name      = $RELEASE_NAME"
    info "Chart Path        = $CHART_PATH"
    info "Values File       = $VALUES_FILE"

    spinner_start "Ensuring namespace"
    kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE"
    spinner_stop
    ok "Namespace OK"

    spinner_start "Installing Helm dependencies (cert-manager, nginx-ingress, redis)"
    install_cert_manager
    install_ingress_nginx
    install_redis
    spinner_stop

    spinner_start "Deploying AI-Agent helm chart"
    helm upgrade --install "$RELEASE_NAME" "$CHART_PATH" \
        -n "$NAMESPACE" -f "$VALUES_FILE"
    spinner_stop
    ok "Helm deployment finished"

    title "Running Smoke Tests"
    post_deploy_smoke "$NAMESPACE" "$RELEASE_NAME" "/healthz" 8000 60 \
        || warn "Smoke test failure (app may still be starting)"
}

