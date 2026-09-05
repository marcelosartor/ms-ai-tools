#!/usr/bin/env bash
#
# Roda o que for barato antes do relatório: typecheck e os testes que o
# diff tocou. Chamado pelo SKILL.md entre "ler os testes" e "aplicar os
# checklists":
#
#   scripts/run-checks.sh <alvo>
#
# Cria um worktree isolado no head_sha (não mexe no working tree do
# usuário), reaproveita o node_modules já instalado quando o diff não
# altera dependências (nunca roda npm install), detecta typecheck/lint/
# test em package.json e o runner (vitest ou jest) em node_modules/.bin, e
# roda só os arquivos de teste que o diff tocou — mais os que importam
# algum arquivo tocado.
#
# Grava raw/checks-result.md (legível, com a saída de quem falhou) e
# raw/checks.json (estruturado).
#
# Códigos de saída:
#   0  tudo que rodou passou (inclusive se nada rodou)
#   1  alguma verificação falhou
#   2  erro de uso, ou não foi possível criar/mover o worktree

set -uo pipefail
# Sem -e de propósito: cada verificação pode falhar e o script continua
# para as próximas, registrando o resultado — não aborta na primeira.

BASE_DIR="${CR_BASE_DIR:-$PWD}"

TARGET="${1:-}"
[ -n "$TARGET" ] || { echo "informe o número do PR ou o range de refs" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "'jq' não encontrado no PATH." >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "'git' não encontrado no PATH." >&2; exit 2; }

SLUG="$(printf '%s' "$TARGET" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\{2,\}/-/g; s/^-//; s/-$//')"
RAW="$BASE_DIR/temp/cr/$SLUG/raw"
WT="$BASE_DIR/temp/cr/$SLUG/wt"
STATUS_FILE="$RAW/context-status.json"

[ -f "$STATUS_FILE" ] || { echo "$STATUS_FILE não existe — rode fetch-context.sh primeiro" >&2; exit 2; }

HEAD_SHA="$(jq -r '.head_sha // empty' "$STATUS_FILE")"
BASE_SHA="$(jq -r '.base_sha // empty' "$STATUS_FILE")"
[ -n "$HEAD_SHA" ] || { echo "head_sha ausente em $STATUS_FILE — nada para rodar" >&2; exit 2; }

# ---------- arquivos tocados: do PR já buscado, ou do diff do range ----------
FILES=()
if [ -f "$RAW/pr-files.tsv" ]; then
  while IFS=$'\t' read -r _ _ path; do
    [ -n "${path:-}" ] && FILES+=("$path")
  done < "$RAW/pr-files.tsv"
elif [ -n "$BASE_SHA" ]; then
  while IFS= read -r path; do
    [ -n "$path" ] && FILES+=("$path")
  done < <(git -C "$BASE_DIR" diff --name-only "$BASE_SHA...$HEAD_SHA" 2>/dev/null || true)
fi

# ---------- 1. worktree isolado no head_sha ----------
mkdir -p "$(dirname "$WT")"
WORKTREE_ERR="$RAW/checks-worktree-error.log"
if [ -d "$WT" ]; then
  git -C "$WT" checkout --detach "$HEAD_SHA" >/dev/null 2>"$WORKTREE_ERR"
  WT_RC=$?
else
  git -C "$BASE_DIR" worktree add --detach "$WT" "$HEAD_SHA" >/dev/null 2>"$WORKTREE_ERR"
  WT_RC=$?
fi
if [ "$WT_RC" -ne 0 ]; then
  echo "não foi possível colocar o worktree em $HEAD_SHA:" >&2
  cat "$WORKTREE_ERR" >&2
  exit 2
fi
rm -f "$WORKTREE_ERR"

cleanup() { git -C "$BASE_DIR" worktree remove --force "$WT" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# ---------- 2. dependências: reaproveita, nunca instala ----------
DEPS_STATUS="ok"
DEPS_REASON=""
TOUCHES_DEPS=false
for f in "${FILES[@]}"; do
  case "$(basename "$f")" in
    package.json|package-lock.json|pnpm-lock.yaml|yarn.lock) TOUCHES_DEPS=true; break ;;
  esac
done

if [ "$TOUCHES_DEPS" = true ]; then
  DEPS_STATUS="indisponível"
  DEPS_REASON="PR altera dependências"
elif [ -d "$BASE_DIR/node_modules" ]; then
  ln -s ../../../../node_modules "$WT/node_modules" 2>/dev/null
  if [ ! -e "$WT/node_modules" ]; then
    DEPS_STATUS="indisponível"
    DEPS_REASON="não foi possível criar o symlink de node_modules"
  fi
else
  DEPS_STATUS="indisponível"
  DEPS_REASON="node_modules não existe na raiz do repositório"
fi

# ---------- 3. typecheck / lint / test: detecção e execução ----------
TYPECHECK_STATUS="não rodou"; TYPECHECK_REASON="sem script typecheck nem tsc"; TYPECHECK_OUTPUT=""
LINT_STATUS="não rodou"; LINT_REASON="sem script lint"; LINT_OUTPUT=""
TEST_STATUS="não rodou"; TEST_REASON="nenhum arquivo de teste tocado pelo diff"; TEST_OUTPUT=""
OVERALL_RC=0
TEST_FILES=()

if [ "$DEPS_STATUS" != "ok" ]; then
  TYPECHECK_REASON="dependências indisponíveis: $DEPS_REASON"
  LINT_REASON="dependências indisponíveis: $DEPS_REASON"
  TEST_REASON="dependências indisponíveis: $DEPS_REASON"
else
  PKG="$WT/package.json"
  TYPECHECK_CMD=""
  if [ -f "$PKG" ] && jq -e '.scripts.typecheck' "$PKG" >/dev/null 2>&1; then
    TYPECHECK_CMD="npm run typecheck --silent"
  elif [ -f "$WT/tsconfig.json" ] && [ -x "$WT/node_modules/.bin/tsc" ]; then
    TYPECHECK_CMD="node_modules/.bin/tsc --noEmit -p tsconfig.json"
  fi

  LINT_CMD=""
  if [ -f "$PKG" ] && jq -e '.scripts.lint' "$PKG" >/dev/null 2>&1; then
    LINT_CMD="npm run lint --silent"
  fi

  # arquivos de teste tocados diretamente...
  for f in "${FILES[@]}"; do
    case "$f" in
      *.spec.*|*.test.*|*/__tests__/*|__tests__/*) TEST_FILES+=("$f") ;;
    esac
  done
  # ...mais os que importam algum arquivo tocado que não é teste em si,
  # pelo nome do módulo (cap de 50 arquivos no total).
  for f in "${FILES[@]}"; do
    [ ${#TEST_FILES[@]} -lt 50 ] || break
    case "$f" in
      *.spec.*|*.test.*|*/__tests__/*|__tests__/*) continue ;;
    esac
    MODULE="$(basename "$f")"; MODULE="${MODULE%.*}"
    [ -n "$MODULE" ] || continue
    while IFS= read -r match; do
      [ -n "$match" ] || continue
      case " ${TEST_FILES[*]-} " in
        *" $match "*) ;;
        *) TEST_FILES+=("$match") ;;
      esac
      [ ${#TEST_FILES[@]} -lt 50 ] || break
    done < <(cd "$WT" && grep -rlE "$MODULE" --include='*.spec.*' --include='*.test.*' . 2>/dev/null | sed 's#^\./##')
  done

  RUNNER=""
  RUNNER_BIN=""
  if [ -x "$WT/node_modules/.bin/vitest" ]; then
    RUNNER="vitest"; RUNNER_BIN="node_modules/.bin/vitest"
  elif [ -x "$WT/node_modules/.bin/jest" ]; then
    RUNNER="jest"; RUNNER_BIN="node_modules/.bin/jest"
  fi

  # ---- typecheck ----
  if [ -n "$TYPECHECK_CMD" ]; then
    TC_OUT="$(cd "$WT" && timeout 300 bash -c "$TYPECHECK_CMD" 2>&1)"; TC_RC=$?
    if [ "$TC_RC" -eq 0 ]; then
      TYPECHECK_STATUS="ok"
    else
      TYPECHECK_STATUS="falhou"; TYPECHECK_OUTPUT="$TC_OUT"; OVERALL_RC=1
      [ "$TC_RC" -ne 124 ] || TYPECHECK_REASON="timeout de 300s"
    fi
  fi

  # ---- lint ----
  if [ -n "$LINT_CMD" ]; then
    LINT_OUT="$(cd "$WT" && timeout 300 bash -c "$LINT_CMD" 2>&1)"; LINT_RC=$?
    if [ "$LINT_RC" -eq 0 ]; then
      LINT_STATUS="ok"
    else
      LINT_STATUS="falhou"; LINT_OUTPUT="$LINT_OUT"
      [ "$LINT_RC" -ne 124 ] || LINT_REASON="timeout de 300s"
    fi
  fi

  # ---- testes ----
  if [ -z "$RUNNER" ]; then
    TEST_REASON="nenhum runner (vitest/jest) em node_modules/.bin"
  elif [ ${#TEST_FILES[@]} -eq 0 ]; then
    TEST_REASON="nenhum arquivo de teste tocado pelo diff"
  else
    if [ "$RUNNER" = "vitest" ]; then
      TEST_OUT="$(cd "$WT" && timeout 300 "$RUNNER_BIN" run "${TEST_FILES[@]}" 2>&1)"; TEST_RC=$?
    else
      TEST_OUT="$(cd "$WT" && timeout 300 "$RUNNER_BIN" "${TEST_FILES[@]}" 2>&1)"; TEST_RC=$?
    fi
    if [ "$TEST_RC" -eq 0 ]; then
      TEST_STATUS="ok"
    else
      TEST_STATUS="falhou"; TEST_OUTPUT="$TEST_OUT"; OVERALL_RC=1
      [ "$TEST_RC" -ne 124 ] || TEST_REASON="timeout de 300s"
    fi
  fi
fi

# ---------- 4. grava resultado ----------
section() { # $1=título $2=status $3=motivo $4=saída
  case "$2" in
    ok) printf '## %s: ok\n\n' "$1" ;;
    falhou) printf '## %s: falhou\n\n```\n%s\n```\n\n' "$1" "$(printf '%s' "$4" | tail -n 60)" ;;
    *) printf '## %s: não rodou (%s)\n\n' "$1" "$3" ;;
  esac
}

{
  printf '# Verificações\n\n'
  section "typecheck" "$TYPECHECK_STATUS" "$TYPECHECK_REASON" "$TYPECHECK_OUTPUT"
  section "lint" "$LINT_STATUS" "$LINT_REASON" "$LINT_OUTPUT"
  section "testes" "$TEST_STATUS" "$TEST_REASON" "$TEST_OUTPUT"
} > "$RAW/checks-result.md"

TEST_FILES_JSON="$(printf '%s\n' "${TEST_FILES[@]-}" | jq -R . | jq -s 'map(select(length > 0))')"

jq -n \
  --arg deps_status "$DEPS_STATUS" --arg deps_reason "$DEPS_REASON" \
  --arg tc_status "$TYPECHECK_STATUS" --arg tc_reason "$TYPECHECK_REASON" \
  --arg lint_status "$LINT_STATUS" --arg lint_reason "$LINT_REASON" \
  --arg test_status "$TEST_STATUS" --arg test_reason "$TEST_REASON" \
  --argjson test_files "$TEST_FILES_JSON" \
  '{
    deps: {status: $deps_status, reason: (if $deps_reason=="" then null else $deps_reason end)},
    typecheck: {status: $tc_status, reason: (if $tc_reason=="" then null else $tc_reason end)},
    lint: {status: $lint_status, reason: (if $lint_reason=="" then null else $lint_reason end)},
    test: {status: $test_status, reason: (if $test_reason=="" then null else $test_reason end), files: $test_files}
  }' > "$RAW/checks.json"

echo "verificações em: $RAW/checks-result.md"
jq -r '"  deps=\(.deps.status)  typecheck=\(.typecheck.status)  lint=\(.lint.status)  test=\(.test.status)"' "$RAW/checks.json"

exit "$OVERALL_RC"
