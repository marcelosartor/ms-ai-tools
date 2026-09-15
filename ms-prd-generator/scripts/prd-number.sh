#!/usr/bin/env bash
#
# Calcula, de forma determinística, o identificador que entra no nome do
# PRD (temp/prd/prd-<identificador>.md), sem gravar nada.
#
#   scripts/prd-number.sh --ticket 86ajrqjc7   # -> 86ajrqjc7
#   scripts/prd-number.sh --file "Fix Exemplo.md"  # -> fix-exemplo
#   scripts/prd-number.sh --text                # -> seq001 (ou o próximo da sequência)
#
# Prioridade de identificador (quando a origem do PRD já não deixa claro
# sozinha, ver SKILL.md): ticket de board > nome de arquivo > sequencial.
#
# Base do diretório temp/prd/ é $PRD_BASE_DIR ou o diretório atual.

set -euo pipefail

BASE_DIR="${PRD_BASE_DIR:-$PWD}"
PRD_DIR="$BASE_DIR/temp/prd"

usage() {
  echo "uso: prd-number.sh --ticket <id> | --file <caminho> | --text" >&2
}

MODE="${1:-}"
ARG="${2:-}"

case "$MODE" in
  --ticket)
    [ -n "$ARG" ] || { echo "informe o id do ticket" >&2; exit 2; }
    printf '%s' "$ARG" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\{2,\}/-/g; s/^-//; s/-$//'
    ;;
  --file)
    [ -n "$ARG" ] || { echo "informe o caminho do arquivo" >&2; exit 2; }
    base="$(basename "$ARG")"
    base="${base%.*}"
    printf '%s' "$base" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._-' '-' | sed 's/-\{2,\}/-/g; s/^-//; s/-$//'
    ;;
  --text)
    mkdir -p "$PRD_DIR"
    last=0
    for f in "$PRD_DIR"/prd-seq*.md; do
      [ -e "$f" ] || continue
      n="$(basename "$f" .md)"
      n="${n#prd-seq}"
      case "$n" in
        ''|*[!0-9]*) continue ;;
      esac
      n=$((10#$n))
      [ "$n" -le "$last" ] || last="$n"
    done
    printf 'seq%03d\n' "$((last + 1))"
    ;;
  *)
    usage
    exit 2
    ;;
esac
