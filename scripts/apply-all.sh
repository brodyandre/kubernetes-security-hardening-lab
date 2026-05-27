#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

LAB_CONTEXT="kind-k8s-security-lab"

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "[ERRO] Comando obrigatorio nao encontrado: ${cmd}" >&2
    exit 1
  fi
}

require_lab_context() {
  local current_context
  current_context="$(kubectl config current-context 2>/dev/null || true)"
  if [[ "${current_context}" != "${LAB_CONTEXT}" ]]; then
    if [[ "${ALLOW_NON_LAB_CONTEXT:-}" == "true" ]]; then
      echo "[WARN] Contexto atual '${current_context}' diferente de '${LAB_CONTEXT}', seguindo por override ALLOW_NON_LAB_CONTEXT=true."
      return
    fi
    echo "[ERRO] Contexto atual do kubectl: '${current_context}'." >&2
    echo "[ERRO] Para evitar aplicar manifests no cluster errado, use o contexto '${LAB_CONTEXT}'." >&2
    echo "[ERRO] Comando sugerido: kubectl config use-context ${LAB_CONTEXT}" >&2
    echo "[ERRO] Se voce realmente quiser ignorar essa protecao, use ALLOW_NON_LAB_CONTEXT=true." >&2
    exit 1
  fi
}

apply_file() {
  local file="$1"
  if [[ ! -f "${file}" ]]; then
    echo "[ERRO] Manifesto nao encontrado: ${file}" >&2
    exit 1
  fi
  kubectl apply -f "${file}"
}

apply_stage() {
  local title="$1"
  shift
  echo "[INFO] ${title}"
  for file in "$@"; do
    echo "  - Aplicando ${file}"
    apply_file "${file}"
  done
}

echo "[INFO] Iniciando aplicacao do laboratorio (modo seguro)."
require_cmd kubectl
require_lab_context

apply_stage "1/7 - Namespaces" \
  "manifests/00-namespaces/namespace-security-lab.yaml" \
  "manifests/00-namespaces/namespace-frontend.yaml" \
  "manifests/00-namespaces/namespace-backend.yaml" \
  "manifests/00-namespaces/namespace-observability.yaml" \
  "manifests/00-namespaces/namespace-insecure-demo.yaml"

apply_stage "2/7 - ServiceAccounts" \
  "manifests/02-service-account/app-serviceaccount.yaml" \
  "manifests/02-service-account/pod-reader-serviceaccount.yaml" \
  "manifests/02-service-account/serviceaccount-token-secret-demo.yaml"

apply_stage "3/7 - RBAC seguro (menor privilegio)" \
  "manifests/03-rbac/readonly-role.yaml" \
  "manifests/03-rbac/readonly-rolebinding.yaml" \
  "manifests/03-rbac/restricted-role.yaml" \
  "manifests/03-rbac/restricted-rolebinding.yaml" \
  "manifests/03-rbac/kube-board-readonly-demo.yaml"

apply_stage "4/7 - SecurityContext seguro" \
  "manifests/01-security-context/app-secure-deployment.yaml" \
  "manifests/01-security-context/app-secure-service.yaml" \
  "manifests/01-security-context/pod-secure-example.yaml"

apply_stage "5/7 - Workloads para testes de NetworkPolicy" \
  "manifests/05-network-policy/backend-api-deployment.yaml" \
  "manifests/05-network-policy/backend-api-service.yaml" \
  "manifests/05-network-policy/frontend-client-allowed.yaml" \
  "manifests/05-network-policy/frontend-client-denied.yaml" \
  "manifests/05-network-policy/observability-client.yaml"

apply_stage "6/7 - NetworkPolicies" \
  "manifests/05-network-policy/default-deny-backend.yaml" \
  "manifests/05-network-policy/allow-frontend-to-backend-api.yaml" \
  "manifests/05-network-policy/allow-observability-to-backend-api.yaml" \
  "manifests/05-network-policy/allow-dns-egress.yaml"

apply_stage "7/7 - Admissao (somente manifestos seguros)" \
  "manifests/06-admission/restricted-namespace-example.yaml" \
  "manifests/06-admission/pod-compliant-restricted.yaml"

echo "[INFO] Aguardando disponibilidade dos deployments principais..."
kubectl -n k8s-security-lab rollout status deployment/security-lab-app --timeout=240s
kubectl -n security-backend rollout status deployment/backend-api --timeout=240s

echo "[OK] Aplicacao concluida."
echo "[INFO] Manifestos propositalmente NAO aplicados neste fluxo:"
echo "  - manifests/01-security-context/pod-insecure-example.yaml"
echo "  - manifests/03-rbac/admin-clusterrolebinding-demo.yaml"
echo "  - manifests/04-registry-auth/deployment-with-imagepullsecret-example.yaml"
echo "  - manifests/06-admission/pod-violates-restricted.yaml"
