#!/usr/bin/env bash
set -euo pipefail

# Wrapper de compatibilidade.
# Mantido para quem ainda usa o nome antigo do script.
# Fluxo oficial: scripts/setup.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/setup.sh"
