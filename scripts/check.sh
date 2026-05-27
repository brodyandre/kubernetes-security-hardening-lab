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
    echo "[ERRO] Para evitar testes no cluster errado, use o contexto '${LAB_CONTEXT}'." >&2
    echo "[ERRO] Comando sugerido: kubectl config use-context ${LAB_CONTEXT}" >&2
    echo "[ERRO] Se voce realmente quiser ignorar essa protecao, use ALLOW_NON_LAB_CONTEXT=true." >&2
    exit 1
  fi
}

run_step() {
  local number="$1"
  local title="$2"
  echo
  echo "[${number}/10] ${title}"
}

assert_can_i() {
  local description="$1"
  local expected="$2"
  shift 2
  local result
  result="$(kubectl auth can-i "$@" | tr -d '\r' | tr '[:upper:]' '[:lower:]')"
  echo "  ${description}: ${result} (esperado: ${expected})"
  if [[ "${result}" != "${expected}" ]]; then
    echo "[ERRO] Resultado inesperado para: ${description}" >&2
    exit 1
  fi
}

test_np_access() {
  local namespace="$1"
  local pod="$2"
  local expected="$3" # allow|deny
  local url="http://backend-api.security-backend.svc.cluster.local:8080/health"
  local actual

  if kubectl -n "${namespace}" exec "pod/${pod}" -- sh -c "curl -fsS --max-time 5 ${url} >/dev/null"; then
    actual="allow"
  else
    actual="deny"
  fi

  echo "  ${namespace}/${pod}: ${actual} (esperado: ${expected})"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "[ERRO] Validacao de NetworkPolicy falhou para ${namespace}/${pod}" >&2
    exit 1
  fi
}

require_cmd kubectl
require_cmd curl
require_lab_context

run_step 1 "kubectl get nodes"
kubectl get nodes

run_step 2 "kubectl get ns"
kubectl get ns

run_step 3 "kubectl get pods -A"
kubectl get pods -A

run_step 4 "kubectl get deploy,svc -n k8s-security-lab"
kubectl get deploy,svc -n k8s-security-lab

run_step 5 "RBAC: pod-reader-sa pode listar pods"
assert_can_i \
  "pod-reader-sa list pods" \
  "yes" \
  list pods --as=system:serviceaccount:k8s-security-lab:pod-reader-sa -n k8s-security-lab

run_step 6 "RBAC: pod-reader-sa NAO pode deletar pods"
assert_can_i \
  "pod-reader-sa delete pods" \
  "no" \
  delete pods --as=system:serviceaccount:k8s-security-lab:pod-reader-sa -n k8s-security-lab

run_step 7 "Endpoint /security via port-forward"
kubectl -n k8s-security-lab rollout status deployment/security-lab-app --timeout=240s
PF_LOG="${TMPDIR:-/tmp}/k8s-security-lab-portforward.log"
kubectl -n k8s-security-lab port-forward svc/security-lab-app 18080:8080 --address 127.0.0.1 >"${PF_LOG}" 2>&1 &
PF_PID=$!

cleanup_pf() {
  if [[ -n "${PF_PID:-}" ]] && kill -0 "${PF_PID}" 2>/dev/null; then
    kill "${PF_PID}" >/dev/null 2>&1 || true
    wait "${PF_PID}" 2>/dev/null || true
  fi
}
trap cleanup_pf EXIT

ready="false"
for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:18080/health" >/dev/null 2>&1; then
    ready="true"
    break
  fi
  sleep 1
done

if [[ "${ready}" != "true" ]]; then
  echo "[ERRO] Port-forward para security-lab-app nao ficou disponivel." >&2
  echo "[INFO] Log do port-forward:"
  cat "${PF_LOG}" >&2 || true
  exit 1
fi

security_response="$(curl -fsS "http://127.0.0.1:18080/security")"
echo "${security_response}"

run_step 8 "Endpoint /write-test"
write_response="$(curl -fsS "http://127.0.0.1:18080/write-test")"
echo "${write_response}"

write_compact="$(echo "${write_response}" | tr -d '[:space:]')"
if [[ "${write_compact}" != *'"path":"/data/write-test.txt","success":true'* ]]; then
  echo "[ERRO] /data/write-test.txt deveria ter sucesso." >&2
  exit 1
fi
if [[ "${write_compact}" != *'"path":"/tmp/tmp-test.txt","success":true'* ]]; then
  echo "[ERRO] /tmp/tmp-test.txt deveria ter sucesso." >&2
  exit 1
fi
if [[ "${write_compact}" != *'"path":"/app/blocked-test.txt","success":false'* ]]; then
  echo "[ERRO] /app/blocked-test.txt deveria falhar com readOnlyRootFilesystem." >&2
  exit 1
fi

run_step 9 "NetworkPolicy: acessos permitidos e negados"
kubectl -n security-backend rollout status deployment/backend-api --timeout=240s
kubectl -n security-frontend wait --for=condition=Ready pod/frontend-client-allowed --timeout=180s
kubectl -n security-frontend wait --for=condition=Ready pod/frontend-client-denied --timeout=180s
kubectl -n security-observability wait --for=condition=Ready pod/observability-client --timeout=180s
test_np_access "security-frontend" "frontend-client-allowed" "allow"
test_np_access "security-frontend" "frontend-client-denied" "deny"
test_np_access "security-observability" "observability-client" "allow"

run_step 10 "Dry-run server do pod-violates-restricted (falha esperada)"
if dryrun_output="$(kubectl apply --dry-run=server -f manifests/06-admission/pod-violates-restricted.yaml 2>&1)"; then
  echo "[ERRO] O dry-run server deveria falhar no namespace restricted." >&2
  echo "${dryrun_output}" >&2
  exit 1
else
  echo "[OK] Falha esperada confirmada."
  echo "${dryrun_output}"
fi

echo
echo "[OK] Validacoes concluidas com sucesso."
