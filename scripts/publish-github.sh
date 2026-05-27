#!/usr/bin/env bash
set -euo pipefail

REPO_NAME="${REPO_NAME:-kubernetes-security-hardening-lab}"
VISIBILITY="${VISIBILITY:-public}" # public | private
COMMIT_MESSAGE="${COMMIT_MESSAGE:-chore: publish lab updates}"
WORKFLOW_NAME="${WORKFLOW_NAME:-Validate Kubernetes YAML}"
SKIP_WORKFLOW_WATCH="${SKIP_WORKFLOW_WATCH:-false}"
OPEN_REPO_PAGE="${OPEN_REPO_PAGE:-false}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "[ERRO] Comando obrigatorio nao encontrado: ${cmd}" >&2
    exit 1
  fi
}

ensure_git_repo() {
  if [[ ! -d ".git" ]]; then
    echo "[INFO] Inicializando repositorio git local..."
    git init
    git branch -M main
  else
    echo "[INFO] Repositorio git local detectado."
    git rev-parse --is-inside-work-tree >/dev/null
  fi
}

ensure_main_branch() {
  local current_branch
  current_branch="$(git rev-parse --abbrev-ref HEAD)"
  if [[ "${current_branch}" != "main" ]]; then
    echo "[INFO] Trocando branch para main..."
    git checkout -B main
  fi
}

ensure_commit() {
  if [[ -z "$(git status --porcelain)" ]]; then
    echo "[INFO] Sem alteracoes pendentes para commit."
    return
  fi

  echo "[INFO] Adicionando alteracoes ao indice..."
  git add .
  echo "[INFO] Criando commit..."
  git commit -m "${COMMIT_MESSAGE}"
}

ensure_gh_auth() {
  if ! gh auth status >/dev/null 2>&1; then
    echo "[ERRO] GitHub CLI sem autenticacao. Execute 'gh auth login' e rode novamente." >&2
    exit 1
  fi
}

ensure_remote_and_push() {
  local origin_url
  origin_url="$(git remote get-url origin 2>/dev/null || true)"
  if [[ -n "${origin_url}" ]]; then
    echo "[INFO] Remote origin detectado (${origin_url}). Fazendo push para main..."
    git push -u origin main
    return
  fi

  local owner full_name
  owner="$(gh api user --jq .login)"
  full_name="${owner}/${REPO_NAME}"

  if gh repo view "${full_name}" >/dev/null 2>&1; then
    echo "[INFO] Repositorio remoto ${full_name} ja existe. Vinculando origin e fazendo push..."
    git remote add origin "https://github.com/${full_name}.git"
    git push -u origin main
  else
    echo "[INFO] Criando repositorio remoto ${full_name} e fazendo push..."
    gh repo create "${REPO_NAME}" --"${VISIBILITY}" --source . --remote origin --push
  fi
}

watch_workflow() {
  if [[ "${SKIP_WORKFLOW_WATCH}" == "true" ]]; then
    echo "[INFO] Monitoramento do workflow desabilitado por variavel SKIP_WORKFLOW_WATCH=true."
    return
  fi

  echo "[INFO] Aguardando disparo do workflow '${WORKFLOW_NAME}'..."
  sleep 8

  local run_id
  run_id="$(gh run list --workflow "${WORKFLOW_NAME}" --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)"
  if [[ -z "${run_id}" || "${run_id}" == "null" ]]; then
    echo "[WARN] Nenhum run encontrado ainda para '${WORKFLOW_NAME}'."
    return
  fi

  echo "[INFO] Acompanhando run ID ${run_id}..."
  gh run watch "${run_id}" --exit-status
}

require_cmd git
require_cmd gh

echo "[INFO] Publicacao automatizada iniciada."
echo "[INFO] Diretorio: ${REPO_ROOT}"

if [[ "${VISIBILITY}" != "public" && "${VISIBILITY}" != "private" ]]; then
  echo "[ERRO] VISIBILITY invalido. Use 'public' ou 'private'." >&2
  exit 1
fi

ensure_git_repo
ensure_main_branch
ensure_commit
ensure_gh_auth
ensure_remote_and_push
watch_workflow

if [[ "${OPEN_REPO_PAGE}" == "true" ]]; then
  echo "[INFO] Abrindo repositorio no navegador..."
  gh repo view --web
fi

echo "[OK] Publicacao concluida."
echo "[INFO] Se o workflow estiver verde, gere o print: 11-github-actions-validate-passed.png"
