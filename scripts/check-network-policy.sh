#!/usr/bin/env bash
set -euo pipefail

TARGET_URL="http://backend-api.security-backend.svc.cluster.local:8080/health"
LAB_CONTEXT="kind-k8s-security-lab"

require_lab_context() {
  local current_context
  current_context="$(kubectl config current-context 2>/dev/null || true)"
  if [[ "${current_context}" != "${LAB_CONTEXT}" ]]; then
    if [[ "${ALLOW_NON_LAB_CONTEXT:-}" == "true" ]]; then
      echo "[WARN] Contexto atual '${current_context}' diferente de '${LAB_CONTEXT}', seguindo por override ALLOW_NON_LAB_CONTEXT=true."
      return
    fi
    echo "[ERRO] Contexto atual do kubectl: '${current_context}'." >&2
    echo "[ERRO] Para evitar testes no cluster errado, use o contexto '${LAB_CONTEXT}'." >&2
    echo "[ERRO] Comando sugerido: kubectl config use-context ${LAB_CONTEXT}" >&2
    echo "[ERRO] Se voce realmente quiser ignorar essa protecao, use ALLOW_NON_LAB_CONTEXT=true." >&2
    exit 1
  fi
}

wait_pod() {
  local namespace="$1"
  local pod="$2"
  kubectl -n "${namespace}" wait --for=condition=ready "pod/${pod}" --timeout=180s >/dev/null
}

test_access() {
  local namespace="$1"
  local pod="$2"
  local expected="$3" # allow|deny
  local result=""

  if kubectl -n "${namespace}" exec "pod/${pod}" -- sh -c "curl -fsS --max-time 3 ${TARGET_URL} >/dev/null"; then
    result="allow"
  else
    result="deny"
  fi

  if [[ "${result}" == "${expected}" ]]; then
    echo "[OK] ${namespace}/${pod}: ${result} (esperado: ${expected})"
  else
    echo "[ERRO] ${namespace}/${pod}: ${result} (esperado: ${expected})"
    exit 1
  fi
}

echo "[INFO] Aguardando pods de teste"
require_lab_context
wait_pod "security-frontend" "frontend-client-allowed"
wait_pod "security-frontend" "frontend-client-denied"
wait_pod "security-observability" "observability-client"
kubectl -n security-backend rollout status deployment/backend-api --timeout=180s >/dev/null

echo "[INFO] Validando regras de acesso"
test_access "security-frontend" "frontend-client-allowed" "allow"
test_access "security-frontend" "frontend-client-denied" "deny"
test_access "security-observability" "observability-client" "allow"

echo "[OK] Comportamento de NetworkPolicy validado."
