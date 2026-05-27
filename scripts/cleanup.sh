#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

CLUSTER_NAME="k8s-security-lab"
LAB_CONTEXT="kind-k8s-security-lab"
DELETE_CLUSTER="false"

usage() {
  cat <<'EOF'
Uso:
  bash scripts/cleanup.sh [--manifests-only] [--delete-cluster]

Opcoes:
  --manifests-only   Limpa apenas os manifests do laboratorio (padrao).
  --delete-cluster   Alem de limpar manifests, solicita confirmacao para remover
                     o cluster kind k8s-security-lab.
  -h, --help         Exibe esta ajuda.
EOF
}

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
    echo "[ERRO] Para evitar remocoes no cluster errado, use o contexto '${LAB_CONTEXT}'." >&2
    echo "[ERRO] Comando sugerido: kubectl config use-context ${LAB_CONTEXT}" >&2
    echo "[ERRO] Se voce realmente quiser ignorar essa protecao, use ALLOW_NON_LAB_CONTEXT=true." >&2
    exit 1
  fi
}

delete_manifest_if_exists() {
  local file="$1"
  if [[ -f "${file}" ]]; then
    echo "  - Removendo ${file}"
    kubectl delete --ignore-not-found -f "${file}" >/dev/null
  fi
}

delete_lab_manifests() {
  echo "[INFO] Limpando recursos do laboratorio via manifests..."

  # Ordem reversa para minimizar dependencias entre objetos.
  local files=(
    "manifests/06-admission/pod-violates-restricted.yaml"
    "manifests/06-admission/pod-compliant-restricted.yaml"
    "manifests/05-network-policy/allow-dns-egress.yaml"
    "manifests/05-network-policy/allow-observability-to-backend-api.yaml"
    "manifests/05-network-policy/allow-frontend-to-backend-api.yaml"
    "manifests/05-network-policy/default-deny-backend.yaml"
    "manifests/05-network-policy/observability-client.yaml"
    "manifests/05-network-policy/frontend-client-denied.yaml"
    "manifests/05-network-policy/frontend-client-allowed.yaml"
    "manifests/05-network-policy/backend-api-service.yaml"
    "manifests/05-network-policy/backend-api-deployment.yaml"
    "manifests/04-registry-auth/deployment-with-imagepullsecret-example.yaml"
    "manifests/04-registry-auth/registry-secret-example.yaml"
    "manifests/03-rbac/admin-clusterrolebinding-demo.yaml"
    "manifests/03-rbac/kube-board-readonly-demo.yaml"
    "manifests/03-rbac/restricted-rolebinding.yaml"
    "manifests/03-rbac/restricted-role.yaml"
    "manifests/03-rbac/readonly-rolebinding.yaml"
    "manifests/03-rbac/readonly-role.yaml"
    "manifests/02-service-account/serviceaccount-token-secret-demo.yaml"
    "manifests/02-service-account/pod-reader-serviceaccount.yaml"
    "manifests/02-service-account/app-serviceaccount.yaml"
    "manifests/01-security-context/pod-insecure-example.yaml"
    "manifests/01-security-context/pod-secure-example.yaml"
    "manifests/01-security-context/app-secure-service.yaml"
    "manifests/01-security-context/app-secure-deployment.yaml"
    "manifests/06-admission/restricted-namespace-example.yaml"
    "manifests/00-namespaces/namespace-insecure-demo.yaml"
    "manifests/00-namespaces/namespace-observability.yaml"
    "manifests/00-namespaces/namespace-backend.yaml"
    "manifests/00-namespaces/namespace-frontend.yaml"
    "manifests/00-namespaces/namespace-security-lab.yaml"
  )

  for file in "${files[@]}"; do
    delete_manifest_if_exists "${file}"
  done

  echo "[OK] Recursos do laboratorio removidos (quando existentes)."
}

for arg in "$@"; do
  case "$arg" in
    --manifests-only)
      DELETE_CLUSTER="false"
      ;;
    --delete-cluster)
      DELETE_CLUSTER="true"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERRO] Opcao invalida: $arg" >&2
      usage
      exit 1
      ;;
  esac
done

require_cmd kubectl
require_lab_context
delete_lab_manifests

if [[ "${DELETE_CLUSTER}" == "true" ]]; then
  require_cmd kind
  if kind get clusters | grep -qx "${CLUSTER_NAME}"; then
    echo
    read -r -p "Confirmar remocao do cluster '${CLUSTER_NAME}'? Digite DELETE_CLUSTER para confirmar: " confirm
    if [[ "${confirm}" == "DELETE_CLUSTER" ]]; then
      echo "[INFO] Removendo cluster ${CLUSTER_NAME}..."
      kind delete cluster --name "${CLUSTER_NAME}"
      echo "[OK] Cluster ${CLUSTER_NAME} removido."
    else
      echo "[INFO] Confirmacao nao fornecida. Cluster mantido."
    fi
  else
    echo "[INFO] Cluster ${CLUSTER_NAME} nao existe. Nada a remover no kind."
  fi
else
  echo "[INFO] Modo manifests-only: cluster nao foi removido."
  echo "[INFO] Para remover tambem o cluster, execute:"
  echo "  bash scripts/cleanup.sh --delete-cluster"
fi
