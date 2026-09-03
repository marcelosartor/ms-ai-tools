#!/usr/bin/env bash
#
# Instala as ferramentas do ms-ai-tools como skills do Claude Code.
#
#   ./install.sh                  # instala todas
#   ./install.sh ms-codereview    # instala só as indicadas
#   ./install.sh --list           # mostra o que existe e o que já está instalado
#
# Cada ferramenta é uma pasta na raiz deste repositório contendo um SKILL.md.
# A instalação copia a pasta para ~/.claude/skills/ (ou $CLAUDE_SKILLS_DIR).
# O .env de cada ferramenta é preservado: nunca é copiado nem sobrescrito.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

discover() { # imprime o nome de cada ferramenta, uma por linha
  local d
  for d in "$ROOT"/*/; do
    [ -f "$d/SKILL.md" ] || continue
    basename "$d"
  done
}

list() {
  local t
  for t in $(discover); do
    if [ -d "$DEST/$t" ]; then printf '  %-20s instalada em %s\n' "$t" "$DEST/$t"
    else printf '  %-20s não instalada\n' "$t"; fi
  done
}

install_one() {
  local tool="$1" src="$ROOT/$1" target="$DEST/$1"

  if [ ! -f "$src/SKILL.md" ]; then
    echo "ferramenta desconhecida: $tool (rode --list)" >&2
    return 1
  fi

  mkdir -p "$DEST"
  # --exclude do rsync não existe em cp; copia para um staging sem o .env
  rm -rf "$target.tmp"
  cp -r "$src" "$target.tmp"
  rm -f "$target.tmp/.env"

  # preserva credenciais já configuradas
  if [ -f "$target/.env" ]; then
    cp "$target/.env" "$target.tmp/.env"
    echo "  $tool: .env existente preservado"
  fi

  rm -rf "$target"
  mv "$target.tmp" "$target"
  find "$target/scripts" -name '*.sh' -exec chmod +x {} + 2>/dev/null || true

  if [ -f "$target/.env.example" ] && [ ! -f "$target/.env" ]; then
    echo "  $tool: instalada. Configure as credenciais em $target/.env (modelo: .env.example)"
  else
    echo "  $tool: instalada em $target"
  fi
}

case "${1:-}" in
  -h|--help) sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
  -l|--list) echo "ferramentas em $ROOT:"; list; exit 0 ;;
esac

TOOLS=("$@")
if [ ${#TOOLS[@]} -eq 0 ]; then
  mapfile -t TOOLS < <(discover)
fi

if [ ${#TOOLS[@]} -eq 0 ]; then
  echo "nenhuma ferramenta encontrada em $ROOT" >&2
  exit 1
fi

echo "instalando em $DEST:"
rc=0
for tool in "${TOOLS[@]}"; do
  install_one "$tool" || rc=1
done

echo
echo "verifique com /skills numa sessão do Claude Code."
exit "$rc"
