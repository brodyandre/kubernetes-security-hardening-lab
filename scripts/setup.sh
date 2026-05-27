#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="k8s-security-lab"
CALICO_VERSION="${CALICO_VERSION:-v3.32.0}"
CALICO_MANIFEST_URL="https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
KIND_CONFIG="${REPO_ROOT}/kind/cluster-calico.yaml"
KUBECONTEXT="kind-${CLUSTER_NAME}"

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "[ERRO] Comando obrigatorio nao encontrado: ${cmd}" >&2
    exit 1
  fi
}

wait_kube_system_running() {
  local timeout_seconds=600
  local interval=5
  local elapsed=0

  echo "[INFO] Aguardando pods do kube-system ficarem Running..."
  while true; do
    local not_running
    not_running="$(kubectl --context "${KUBECONTEXT}" get pods -n kube-system --no-headers \
      | awk '$3 != "Running" {print $1 " (" $3 ")"}' || true)"

    if [[ -z "${not_running}" ]]; then
      echo "[OK] Todos os pods do kube-system estao Running."
      break
    fi

    if (( elapsed >= timeout_seconds )); then
      echo "[ERRO] Timeout aguardando kube-system Running." >&2
      echo "${not_running}" >&2
      exit 1
    fi

    echo "[INFO] Ainda nao Running:"
    echo "${not_running}"
    sleep "${interval}"
    elapsed=$((elapsed + interval))
  done
}

echo "[INFO] Verificando pre-requisitos..."
require_cmd kind
require_cmd kubectl
require_cmd docker

if ! docker info >/dev/null 2>&1; then
  echo "[ERRO] Docker nao esta acessivel. Inicie o Docker Desktop/daemon e tente novamente." >&2
  exit 1
fi

if [[ ! -f "${KIND_CONFIG}" ]]; then
  echo "[ERRO] Arquivo de configuracao nao encontrado: ${KIND_CONFIG}" >&2
  exit 1
fi

if kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  echo "[INFO] Cluster ${CLUSTER_NAME} ja existe. Nenhum cluster sera removido."
else
  echo "[INFO] Criando cluster ${CLUSTER_NAME} com ${KIND_CONFIG}..."
  kind create cluster --name "${CLUSTER_NAME}" --config "${KIND_CONFIG}" --wait 180s
fi

echo "[INFO] Definindo contexto kubectl: ${KUBECONTEXT}"
kubectl config use-context "${KUBECONTEXT}" >/dev/null

echo "[INFO] Instalando Calico (${CALICO_VERSION}) usando manifesto oficial..."
kubectl --context "${KUBECONTEXT}" apply -f "${CALICO_MANIFEST_URL}"

echo "[INFO] Aguardando recursos principais do Calico..."
kubectl --context "${KUBECONTEXT}" -n kube-system rollout status daemonset/calico-node --timeout=300s
kubectl --context "${KUBECONTEXT}" -n kube-system rollout status deployment/calico-kube-controllers --timeout=300s
kubectl --context "${KUBECONTEXT}" -n kube-system rollout status deployment/coredns --timeout=300s
kubectl --context "${KUBECONTEXT}" -n kube-system rollout status daemonset/kube-proxy --timeout=300s

wait_kube_system_running

echo "[INFO] Estado final do cluster:"
kubectl --context "${KUBECONTEXT}" get nodes
kubectl --context "${KUBECONTEXT}" get pods -A

echo
echo "[OK] Ambiente pronto para testes de NetworkPolicy com Calico."
echo "[INFO] Comandos uteis:"
echo "  kubectl config use-context ${KUBECONTEXT}"
echo "  kubectl get nodes -o wide"
echo "  kubectl -n kube-system get pods -o wide"
echo "  kubectl get networkpolicy -A"
