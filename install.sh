#!/usr/bin/env bash
#
# Atalho para quem clonou o repositório. A implementação do instalador é
# única e vive em bin/cli.js — este script só a chama, para não haver duas
# versões da mesma lógica divergindo com o tempo.
#
#   ./install.sh                  # instala todas as ferramentas
#   ./install.sh ms-codereview    # instala só as indicadas
#   ./install.sh --list
#
# Sem clonar, o mesmo instalador roda por npx:
#   npx github:marcelosartor/ms-ai-tools

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  cat >&2 <<'MSG'
node não encontrado no PATH — o instalador precisa dele (>= 18).

Instale o Node, ou copie a skill à mão:
  mkdir -p ~/.claude/skills && cp -r ms-codereview ~/.claude/skills/
  # e ponha as credenciais em ~/.config/ms-ai-tools/.env
MSG
  exit 2
fi

exec node "$ROOT/bin/cli.js" "$@"
