#!/usr/bin/env bash
set -euo pipefail

# Wrapper de compatibilidade para nome antigo.
# Fluxo oficial: scripts/apply-all.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/apply-all.sh"
