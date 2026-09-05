#!/usr/bin/env bash
#
# Harness de testes dos scripts da skill ms-codereview. Bash puro, sem
# framework: monta fixtures em diretório temporário, roda o script real e
# afirma exit code e campos do JSON com jq.
#
#   bash ms-codereview/tests/run.sh
#
# Sai 0 se tudo passou, 1 se algum caso falhou.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$TESTS_DIR/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# jq/curl são exigidos pelos scripts testados; se não estiverem no PATH do
# sistema, usa o binário que o instalador do pool já tenha baixado.
if ! command -v jq >/dev/null 2>&1; then
  POOL_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/ms-ai-tools"
  [ -x "$POOL_CONFIG/bin/jq" ] && export PATH="$POOL_CONFIG/bin:$PATH"
fi

# Isola cada teste das credenciais reais do usuário: aponta para um .env
# vazio dentro do diretório de trabalho, a menos que o teste queira outra
# coisa.
export MS_AI_TOOLS_CONFIG_DIR="$WORK/config"
mkdir -p "$MS_AI_TOOLS_CONFIG_DIR"

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf '  ok   - %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL - %s\n' "$1"; [ -z "${2:-}" ] || printf '         %s\n' "$2"; }

assert_eq() { # $1=descrição $2=esperado $3=obtido
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$1" "esperado <$2> obtido <$3>"; fi
}

assert_exit() { # $1=descrição $2=exit esperado -- resto = comando
  local desc="$1" expected="$2" out rc
  shift 2
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" = "$expected" ]; then ok "$desc"; else fail "$desc" "exit esperado $expected, obtido $rc — saída: $out"; fi
}

new_repo() { # $1=diretório
  git init -q "$1"
  git -C "$1" config user.email test@example.com
  git -C "$1" config user.name "Teste"
}

status_file_for() { # $1=diretório do repo -> caminho do context-status.json (um alvo por fixture)
  find "$1/temp/cr" -name context-status.json 2>/dev/null | head -1
}

echo "=== ms-codereview: tests/run.sh ==="

for f in "$TESTS_DIR"/f*.sh; do
  [ -f "$f" ] || continue
  # shellcheck disable=SC1090
  . "$f"
done

echo
echo "$PASS ok, $FAIL falhas"
[ "$FAIL" -eq 0 ]
