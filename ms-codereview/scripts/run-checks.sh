#!/usr/bin/env bash
#
# Roda o que for barato antes do relatório: typecheck e os testes que o
# diff tocou, por pacote (monorepo: um pacote por package.json mais
# próximo dos arquivos tocados), com baseline contra a base_sha para não
# culpar o PR por erro pré-existente. Chamado pelo SKILL.md entre "ler os
# testes" e "aplicar os checklists":
#
#   scripts/run-checks.sh <alvo> [--keep]
#
# Cria um worktree isolado no head_sha (não mexe no working tree do
# usuário), reaproveita o node_modules já instalado quando o diff não
# altera dependências (nunca roda npm install), detecta typecheck/lint/
# test em cada package.json tocado (ou herdado do mais próximo) e o
# runner (vitest ou jest) em node_modules/.bin, e roda só os arquivos de
# teste que o diff tocou — mais os que importam algum arquivo tocado pelo
# caminho relativo.
#
# --keep mantém o worktree do head depois do script sair (caminho vai em
# checks.json.worktree); sem a flag, é removido ao final. O worktree da
# base (usado só para a baseline) é sempre removido pelo próprio script.
#
# Grava raw/checks-result.md (legível, com a saída de quem falhou) e
# raw/checks.json (estruturado): campos agregados no topo (deps,
# typecheck, lint, test — compatibilidade com quem lê só o resumo) e o
# detalhe por pacote em `packages: [{dir, typecheck, lint, test}]`.
#
# Códigos de saída:
#   0  tudo que rodou passou (inclusive se nada rodou, ou stack fora do Node)
#   1  alguma verificação falhou (descontada a baseline)
#   2  erro de uso, ou não foi possível criar/mover o worktree do head

set -uo pipefail
# Sem -e de propósito: cada verificação pode falhar e o script continua
# para as próximas, registrando o resultado — não aborta na primeira.

BASE_DIR="${CR_BASE_DIR:-$PWD}"

TARGET="${1:-}"
KEEP=false
shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --keep) KEEP=true ;;
  esac
  shift
done

[ -n "$TARGET" ] || { echo "informe o número do PR ou o range de refs" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "'jq' não encontrado no PATH." >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "'git' não encontrado no PATH." >&2; exit 2; }

SLUG="$(printf '%s' "$TARGET" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\{2,\}/-/g; s/^-//; s/-$//')"
RAW="$BASE_DIR/temp/cr/$SLUG/raw"
WT="$BASE_DIR/temp/cr/$SLUG/wt"
WT_BASE="$BASE_DIR/temp/cr/$SLUG/wt-base"
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

WT_BASE_MOUNTED=false
cleanup() {
  if [ "$KEEP" != true ]; then
    git -C "$BASE_DIR" worktree remove --force "$WT" >/dev/null 2>&1 || true
  fi
  if [ "$WT_BASE_MOUNTED" = true ]; then
    git -C "$BASE_DIR" worktree remove --force "$WT_BASE" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# ---------- 2. manifesto mais próximo de cada arquivo (monorepo) ----------
declare -A MANIFEST_CACHE
nearest_manifest() { # $1=raiz (worktree) $2=arquivo relativo -> imprime caminho absoluto do package.json
  local root="$1" file="$2" dir cache_key cached candidate
  dir="$(dirname "$file")"
  while :; do
    cache_key="$root|$dir"
    if [ -n "${MANIFEST_CACHE[$cache_key]+x}" ]; then
      cached="${MANIFEST_CACHE[$cache_key]}"
    else
      if [ "$dir" = "." ]; then candidate="$root/package.json"; else candidate="$root/$dir/package.json"; fi
      cached=""
      [ -f "$candidate" ] && cached="$candidate"
      MANIFEST_CACHE["$cache_key"]="$cached"
    fi
    if [ -n "$cached" ]; then printf '%s\n' "$cached"; return 0; fi
    [ "$dir" != "." ] || return 1
    dir="$(dirname "$dir")"
  done
}

nearest_jvm_manifest() { # $1=raiz $2=arquivo -> imprime "maven"/"gradle"; exit 1 se nenhum
  local root="$1" file="$2" dir
  dir="$(dirname "$file")"
  while :; do
    if [ "$dir" = "." ]; then base="$root"; else base="$root/$dir"; fi
    if [ -f "$base/pom.xml" ]; then printf 'maven\n'; return 0; fi
    if [ -f "$base/build.gradle" ] || [ -f "$base/build.gradle.kts" ] \
       || [ -f "$base/settings.gradle" ] || [ -f "$base/settings.gradle.kts" ]; then
      printf 'gradle\n'; return 0
    fi
    [ "$dir" != "." ] || return 1
    dir="$(dirname "$dir")"
  done
}

PKG_DIRS=()
GROUPS_DIR="$(mktemp -d)"
NO_MANIFEST_FILES=()
for f in "${FILES[@]}"; do
  manifest="$(nearest_manifest "$WT" "$f" || true)"
  if [ -z "$manifest" ]; then
    NO_MANIFEST_FILES+=("$f")
    continue
  fi
  pkgdir="${manifest%/package.json}"
  pkgdir="${pkgdir#$WT}"
  pkgdir="${pkgdir#/}"
  [ -n "$pkgdir" ] || pkgdir="."
  key="$(printf '%s' "$pkgdir" | tr '/' '_')"
  [ -n "$key" ] || key="_root_"
  echo "$f" >> "$GROUPS_DIR/$key.files"
  case " ${PKG_DIRS[*]-} " in
    *" $pkgdir "*) ;;
    *) PKG_DIRS+=("$pkgdir") ;;
  esac
done

STACK_OUT_OF_NODE=""
if [ ${#PKG_DIRS[@]} -eq 0 ] && [ ${#FILES[@]} -gt 0 ]; then
  for f in "${FILES[@]}"; do
    jvm="$(nearest_jvm_manifest "$WT" "$f" || true)"
    if [ -n "$jvm" ]; then STACK_OUT_OF_NODE="$jvm"; break; fi
  done
fi

# ---------- 3. symlink de node_modules: por pacote, senão o da raiz ----------
link_node_modules() { # $1=diretório dentro do worktree (head ou base) onde criar o link
  local dir="$1" rel real root
  case "$dir" in
    "$WT"|"$WT"/*) root="$WT" ;;
    "$WT_BASE"|"$WT_BASE"/*) root="$WT_BASE" ;;
    *) root="$dir" ;;
  esac
  rel="${dir#$root}"; rel="${rel#/}"
  if [ -n "$rel" ] && [ -d "$BASE_DIR/$rel/node_modules" ]; then
    real="$BASE_DIR/$rel/node_modules"
  elif [ -d "$BASE_DIR/node_modules" ]; then
    real="$BASE_DIR/node_modules"
  else
    return 1
  fi
  [ -e "$dir/node_modules" ] || ln -s "$real" "$dir/node_modules" 2>/dev/null
  [ -e "$dir/node_modules" ]
}

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
fi

# ---------- discovery de teste pelo caminho relativo importado ----------
GENERIC_BASENAMES="index utils util helpers types constants config"
is_generic_basename() {
  case " $GENERIC_BASENAMES " in *" $1 "*) return 0 ;; esac
  return 1
}

discover_tests() { # $1=raiz de busca $2..=arquivos do pacote -> preenche TEST_FILES (array já declarado pelo chamador)
  local root="$1"; shift
  local f
  for f in "$@"; do
    case "$f" in
      *.spec.*|*.test.*|*/__tests__/*|__tests__/*)
        case " ${TEST_FILES[*]-} " in *" $f "*) ;; *) TEST_FILES+=("$f") ;; esac
        ;;
    esac
  done
  for f in "$@"; do
    [ ${#TEST_FILES[@]} -lt 50 ] || break
    case "$f" in
      *.spec.*|*.test.*|*/__tests__/*|__tests__/*) continue ;;
    esac
    local stem parentdir grep_args=()
    stem="$(basename "$f")"; stem="${stem%.*}"
    parentdir="$(basename "$(dirname "$f")")"
    [ -n "$stem" ] || continue
    grep_args=(-e "${parentdir}/${stem}'" -e "${parentdir}/${stem}\"" -e "${parentdir}/${stem}.js'")
    is_generic_basename "$stem" || grep_args+=(-e "/${stem}'")
    while IFS= read -r match; do
      [ -n "$match" ] || continue
      case " ${TEST_FILES[*]-} " in
        *" $match "*) ;;
        *) TEST_FILES+=("$match") ;;
      esac
      [ ${#TEST_FILES[@]} -lt 50 ] || break
    done < <(cd "$root" && grep -rlF "${grep_args[@]}" --include='*.spec.*' --include='*.test.*' . 2>/dev/null | sed 's#^\./##')
  done
}

detect_runner() { # $1=diretório absoluto -> imprime "runner<TAB>bin relativo ao diretório"; exit 1 se nenhum
  local dir="$1"
  if [ -x "$dir/node_modules/.bin/vitest" ]; then printf 'vitest\tnode_modules/.bin/vitest\n'; return 0; fi
  if [ -x "$dir/node_modules/.bin/jest" ]; then printf 'jest\tnode_modules/.bin/jest\n'; return 0; fi
  return 1
}

run_one_test_file() { # $1=diretório $2=runner $3=bin(rel) $4=arquivo -> grava saída em stdout, retorna rc do runner
  local dir="$1" runner="$2" bin="$3" file="$4"
  if [ "$runner" = "vitest" ]; then
    ( cd "$dir" && timeout 300 "./$bin" run "$file" 2>&1 )
  else
    ( cd "$dir" && timeout 300 "./$bin" "$file" 2>&1 )
  fi
}

tsc_normalize() { # stdin -> uma linha normalizada por erro (sem número de linha/coluna)
  grep -E '\([0-9]+,[0-9]+\): error TS[0-9]+' | sed -E 's/\(([0-9]+,[0-9]+)\)/()/'
}

# ---------- baseline: monta o worktree da base sob demanda, uma vez ----------
BASELINE_UNAVAILABLE_REASON=""
ensure_base_worktree() {
  [ "$WT_BASE_MOUNTED" = true ] && return 0
  if [ -z "$BASE_SHA" ]; then
    BASELINE_UNAVAILABLE_REASON="base_sha ausente"
    return 1
  fi
  mkdir -p "$(dirname "$WT_BASE")"
  local err="$RAW/checks-worktree-base-error.log"
  local rc
  if [ -d "$WT_BASE" ]; then
    git -C "$WT_BASE" checkout --detach "$BASE_SHA" >/dev/null 2>"$err"; rc=$?
  else
    git -C "$BASE_DIR" worktree add --detach "$WT_BASE" "$BASE_SHA" >/dev/null 2>"$err"; rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    BASELINE_UNAVAILABLE_REASON="não foi possível montar o worktree em ${BASE_SHA:0:7}: $(tail -c 200 "$err" | tr '\n' ' ')"
    return 1
  fi
  rm -f "$err"
  WT_BASE_MOUNTED=true
  return 0
}

# ---------- 4. roda cada pacote ----------
PACKAGES_JSON="[]"
PKG_RESULTS_FILE="$(mktemp)"
OVERALL_RC=0
ALL_TEST_FILES=()
AGG_TC_STATUS="não rodou"; AGG_LINT_STATUS="não rodou"; AGG_TEST_STATUS="não rodou"
AGG_TC_REASON="sem script typecheck nem tsc"; AGG_LINT_REASON="sem script lint"; AGG_TEST_REASON="nenhum arquivo de teste tocado pelo diff"
RESULT_SECTIONS=()

if [ -n "$STACK_OUT_OF_NODE" ]; then
  MSG="não rodou (stack fora do Node: $STACK_OUT_OF_NODE)"
  AGG_TC_STATUS="não rodou"; AGG_TC_REASON="stack fora do Node: $STACK_OUT_OF_NODE"
  AGG_LINT_STATUS="não rodou"; AGG_LINT_REASON="stack fora do Node: $STACK_OUT_OF_NODE"
  AGG_TEST_STATUS="não rodou"; AGG_TEST_REASON="stack fora do Node: $STACK_OUT_OF_NODE"
  RESULT_SECTIONS+=("$MSG")
elif [ "$TOUCHES_DEPS" = true ]; then
  AGG_TC_REASON="dependências indisponíveis: $DEPS_REASON"
  AGG_LINT_REASON="dependências indisponíveis: $DEPS_REASON"
  AGG_TEST_REASON="dependências indisponíveis: $DEPS_REASON"
elif [ ${#PKG_DIRS[@]} -eq 0 ]; then
  : # nada a rodar: nenhum arquivo tocado tem manifesto Node no caminho
else
  ANY_TC_OK=false; ANY_TC_FAIL=false; ANY_TC_RAN=false
  ANY_LINT_OK=false; ANY_LINT_FAIL=false
  ANY_TEST_OK=false; ANY_TEST_FAIL=false; ANY_TEST_RAN=false
  ANY_DEPS_OK=false; DEPS_FAIL_REASON=""

  for pkgdir in "${PKG_DIRS[@]}"; do
    key="$(printf '%s' "$pkgdir" | tr '/' '_')"
    [ -n "$key" ] || key="_root_"
    PKG_FILES=()
    while IFS= read -r f; do [ -n "$f" ] && PKG_FILES+=("$f"); done < "$GROUPS_DIR/$key.files"

    if [ "$pkgdir" = "." ]; then ABS_DIR="$WT"; REL_DIR="."; else ABS_DIR="$WT/$pkgdir"; REL_DIR="$pkgdir"; fi

    PKG="$ABS_DIR/package.json"
    P_TC_STATUS="não rodou"; P_TC_REASON="sem script typecheck nem tsc"; P_TC_OUT=""; P_TC_NEW=0; P_TC_PRE=0
    P_LINT_STATUS="não rodou"; P_LINT_REASON="sem script lint"; P_LINT_OUT=""
    P_TEST_STATUS="não rodou"; P_TEST_REASON="nenhum arquivo de teste tocado pelo diff"; P_TEST_OUT=""
    P_TEST_NEW=0; P_TEST_PRE=0

    if ! link_node_modules "$ABS_DIR"; then
      DEPS_FAIL_REASON="node_modules não encontrado (nem em $REL_DIR nem na raiz)"
      P_TC_REASON="dependências indisponíveis: $DEPS_FAIL_REASON"
      P_LINT_REASON="dependências indisponíveis: $DEPS_FAIL_REASON"
      P_TEST_REASON="dependências indisponíveis: $DEPS_FAIL_REASON"
      RESULT_SECTIONS+=("### pacote: $REL_DIR

- typecheck: não rodou ($P_TC_REASON)
- lint: não rodou ($P_LINT_REASON)
- testes: não rodou ($P_TEST_REASON)")
      jq -n -c --arg dir "$REL_DIR" --arg reason "$P_TC_REASON" \
        '{dir:$dir,
          typecheck:{status:"não rodou", reason:$reason, new:0, preexisting:0},
          lint:{status:"não rodou", reason:$reason},
          test:{status:"não rodou", reason:$reason, new:0, preexisting:0}}' \
        >> "$PKG_RESULTS_FILE"
      continue
    fi
    ANY_DEPS_OK=true

    TC_CMD=""
    if jq -e '.scripts.typecheck' "$PKG" >/dev/null 2>&1; then
      TC_CMD="npm run typecheck --silent"
    elif [ -f "$ABS_DIR/tsconfig.json" ] && [ -x "$ABS_DIR/node_modules/.bin/tsc" ]; then
      TC_CMD="node_modules/.bin/tsc --noEmit -p tsconfig.json"
    fi
    LINT_CMD=""
    jq -e '.scripts.lint' "$PKG" >/dev/null 2>&1 && LINT_CMD="npm run lint --silent"

    # ---- typecheck ----
    if [ -n "$TC_CMD" ]; then
      ANY_TC_RAN=true
      TC_RAW="$(cd "$ABS_DIR" && timeout 300 bash -c "$TC_CMD" 2>&1)"; TC_RC=$?
      if [ "$TC_RC" -eq 0 ]; then
        P_TC_STATUS="ok"; ANY_TC_OK=true
      else
        ANY_TC_FAIL=true
        HEAD_ERR_LINES="$(printf '%s\n' "$TC_RAW" | grep -E '\([0-9]+,[0-9]+\): error TS[0-9]+' || true)"
        HEAD_NORM="$(printf '%s\n' "$HEAD_ERR_LINES" | tsc_normalize || true)"
        BASE_NORM=""
        if [ -n "$HEAD_ERR_LINES" ] && ensure_base_worktree; then
          BASE_ABS_DIR="$WT_BASE"; [ "$pkgdir" = "." ] || BASE_ABS_DIR="$WT_BASE/$pkgdir"
          if [ -f "$BASE_ABS_DIR/package.json" ]; then
            link_node_modules "$BASE_ABS_DIR" || true
            BASE_TC_CMD=""
            if jq -e '.scripts.typecheck' "$BASE_ABS_DIR/package.json" >/dev/null 2>&1; then
              BASE_TC_CMD="npm run typecheck --silent"
            elif [ -f "$BASE_ABS_DIR/tsconfig.json" ] && [ -x "$BASE_ABS_DIR/node_modules/.bin/tsc" ]; then
              BASE_TC_CMD="node_modules/.bin/tsc --noEmit -p tsconfig.json"
            fi
            if [ -n "$BASE_TC_CMD" ]; then
              BASE_TC_RAW="$(cd "$BASE_ABS_DIR" && timeout 300 bash -c "$BASE_TC_CMD" 2>&1)"
              BASE_NORM="$(printf '%s\n' "$BASE_TC_RAW" | tsc_normalize || true)"
            fi
          fi
        fi
        NEW_LINES=""
        while IFS= read -r hline; do
          [ -n "$hline" ] || continue
          hnorm="$(printf '%s\n' "$hline" | tsc_normalize || true)"
          if [ -n "$BASE_NORM" ] && printf '%s\n' "$BASE_NORM" | grep -qxF "$hnorm"; then
            P_TC_PRE=$((P_TC_PRE + 1))
          else
            P_TC_NEW=$((P_TC_NEW + 1))
            NEW_LINES="$NEW_LINES$hline"$'\n'
          fi
        done < <(printf '%s\n' "$HEAD_ERR_LINES")
        if [ "$P_TC_NEW" -gt 0 ]; then
          P_TC_STATUS="falhou"; P_TC_OUT="$NEW_LINES"; OVERALL_RC=1
        else
          P_TC_STATUS="ok"; ANY_TC_OK=true; ANY_TC_FAIL=false
        fi
        [ "$TC_RC" -ne 124 ] || P_TC_REASON="timeout de 300s"
      fi
    fi

    # ---- lint ----
    if [ -n "$LINT_CMD" ]; then
      ANY_LINT_RAN=true
      LINT_OUT_RAW="$(cd "$ABS_DIR" && timeout 300 bash -c "$LINT_CMD" 2>&1)"; LINT_RC=$?
      if [ "$LINT_RC" -eq 0 ]; then
        P_LINT_STATUS="ok"; ANY_LINT_OK=true
      else
        P_LINT_STATUS="falhou"; P_LINT_OUT="$LINT_OUT_RAW"; ANY_LINT_FAIL=true
        [ "$LINT_RC" -ne 124 ] || P_LINT_REASON="timeout de 300s"
      fi
    fi

    # ---- testes ----
    RUNNER_LINE="$(detect_runner "$ABS_DIR" || true)"
    TEST_FILES=()
    discover_tests "$ABS_DIR" "${PKG_FILES[@]}"
    for tf in "${TEST_FILES[@]}"; do
      case " ${ALL_TEST_FILES[*]-} " in
        *" $tf "*) ;;
        *) ALL_TEST_FILES+=("$tf") ;;
      esac
    done

    if [ -z "$RUNNER_LINE" ]; then
      P_TEST_REASON="nenhum runner (vitest/jest) em node_modules/.bin"
    elif [ ${#TEST_FILES[@]} -eq 0 ]; then
      P_TEST_REASON="nenhum arquivo de teste tocado pelo diff"
    else
      ANY_TEST_RAN=true
      RUNNER="${RUNNER_LINE%%$'\t'*}"; RUNNER_BIN="${RUNNER_LINE#*$'\t'}"
      FAILED_OUT=""
      for tf in "${TEST_FILES[@]}"; do
        [ -f "$ABS_DIR/$tf" ] || continue
        OUT="$(run_one_test_file "$ABS_DIR" "$RUNNER" "$RUNNER_BIN" "$tf")"; RC=$?
        if [ "$RC" -eq 0 ]; then continue; fi
        # falhou no head: é pré-existente se o arquivo já existia e já
        # falhava na base; senão é novo.
        IS_PRE=false
        if ensure_base_worktree; then
          BASE_ABS_DIR="$WT_BASE"; [ "$pkgdir" = "." ] || BASE_ABS_DIR="$WT_BASE/$pkgdir"
          if [ -f "$BASE_ABS_DIR/$tf" ]; then
            link_node_modules "$BASE_ABS_DIR" || true
            BASE_RUNNER_LINE="$(detect_runner "$BASE_ABS_DIR" || true)"
            if [ -n "$BASE_RUNNER_LINE" ]; then
              B_RUNNER="${BASE_RUNNER_LINE%%$'\t'*}"; B_BIN="${BASE_RUNNER_LINE#*$'\t'}"
              run_one_test_file "$BASE_ABS_DIR" "$B_RUNNER" "$B_BIN" "$tf" >/dev/null; B_RC=$?
              [ "$B_RC" -eq 0 ] || IS_PRE=true
            fi
          fi
        fi
        if [ "$IS_PRE" = true ]; then
          P_TEST_PRE=$((P_TEST_PRE + 1))
        else
          P_TEST_NEW=$((P_TEST_NEW + 1))
          FAILED_OUT="$FAILED_OUT### $tf"$'\n'"$OUT"$'\n\n'
        fi
      done
      if [ "$P_TEST_NEW" -gt 0 ]; then
        P_TEST_STATUS="falhou"; P_TEST_OUT="$FAILED_OUT"; OVERALL_RC=1; ANY_TEST_FAIL=true
      else
        P_TEST_STATUS="ok"; ANY_TEST_OK=true
      fi
    fi

    RESULT_SECTIONS+=("### pacote: $REL_DIR

- typecheck: $P_TC_STATUS$([ "$P_TC_STATUS" = "não rodou" ] && printf ' (%s)' "$P_TC_REASON")$([ "$P_TC_PRE" -gt 0 ] && printf ' — %d pré-existente(s)' "$P_TC_PRE")
$([ -z "$P_TC_OUT" ] || printf '\`\`\`\n%s\n\`\`\`\n' "$(printf '%s' "$P_TC_OUT" | tail -n 60)")
- lint: $P_LINT_STATUS$([ "$P_LINT_STATUS" = "não rodou" ] && printf ' (%s)' "$P_LINT_REASON")
$([ -z "$P_LINT_OUT" ] || printf '\`\`\`\n%s\n\`\`\`\n' "$(printf '%s' "$P_LINT_OUT" | tail -n 60)")
- testes: $P_TEST_STATUS$([ "$P_TEST_STATUS" = "não rodou" ] && printf ' (%s)' "$P_TEST_REASON")$([ "$P_TEST_PRE" -gt 0 ] && printf ' — %d pré-existente(s)' "$P_TEST_PRE")
$([ -z "$P_TEST_OUT" ] || printf '\`\`\`\n%s\n\`\`\`\n' "$(printf '%s' "$P_TEST_OUT" | tail -n 60)")")

    jq -n -c \
      --arg dir "$REL_DIR" \
      --arg tc_status "$P_TC_STATUS" --arg tc_reason "$P_TC_REASON" --argjson tc_new "$P_TC_NEW" --argjson tc_pre "$P_TC_PRE" \
      --arg lint_status "$P_LINT_STATUS" --arg lint_reason "$P_LINT_REASON" \
      --arg test_status "$P_TEST_STATUS" --arg test_reason "$P_TEST_REASON" --argjson test_new "$P_TEST_NEW" --argjson test_pre "$P_TEST_PRE" \
      '{dir:$dir,
        typecheck:{status:$tc_status, reason:(if $tc_reason=="" then null else $tc_reason end), new:$tc_new, preexisting:$tc_pre},
        lint:{status:$lint_status, reason:(if $lint_reason=="" then null else $lint_reason end)},
        test:{status:$test_status, reason:(if $test_reason=="" then null else $test_reason end), new:$test_new, preexisting:$test_pre}}' \
      >> "$PKG_RESULTS_FILE"
  done

  if [ "$ANY_TC_FAIL" = true ]; then AGG_TC_STATUS="falhou"; AGG_TC_REASON=""
  elif [ "$ANY_TC_OK" = true ]; then AGG_TC_STATUS="ok"; AGG_TC_REASON=""
  fi
  if [ "${ANY_LINT_FAIL:-false}" = true ]; then AGG_LINT_STATUS="falhou"; AGG_LINT_REASON=""
  elif [ "$ANY_LINT_OK" = true ]; then AGG_LINT_STATUS="ok"; AGG_LINT_REASON=""
  fi
  if [ "$ANY_TEST_FAIL" = true ]; then AGG_TEST_STATUS="falhou"; AGG_TEST_REASON=""
  elif [ "$ANY_TEST_OK" = true ]; then AGG_TEST_STATUS="ok"; AGG_TEST_REASON=""
  fi
  if [ "$ANY_DEPS_OK" = true ]; then
    DEPS_STATUS="ok"; DEPS_REASON=""
  else
    DEPS_STATUS="indisponível"; DEPS_REASON="$DEPS_FAIL_REASON"
  fi

  PACKAGES_JSON="$(jq -s -c . "$PKG_RESULTS_FILE")"
fi
rm -rf "$GROUPS_DIR" "$PKG_RESULTS_FILE"

if [ -n "$BASELINE_UNAVAILABLE_REASON" ]; then
  RESULT_SECTIONS+=("baseline: indisponível ($BASELINE_UNAVAILABLE_REASON)")
fi

# ---------- 5. grava resultado ----------
{
  printf '# Verificações\n\n'
  if [ ${#RESULT_SECTIONS[@]} -eq 0 ]; then
    printf '## typecheck: %s\n\n## lint: %s\n\n## testes: %s\n\n' \
      "$([ "$AGG_TC_STATUS" = "não rodou" ] && printf 'não rodou (%s)' "$AGG_TC_REASON" || printf '%s' "$AGG_TC_STATUS")" \
      "$([ "$AGG_LINT_STATUS" = "não rodou" ] && printf 'não rodou (%s)' "$AGG_LINT_REASON" || printf '%s' "$AGG_LINT_STATUS")" \
      "$([ "$AGG_TEST_STATUS" = "não rodou" ] && printf 'não rodou (%s)' "$AGG_TEST_REASON" || printf '%s' "$AGG_TEST_STATUS")"
  else
    for s in "${RESULT_SECTIONS[@]}"; do printf '%s\n\n' "$s"; done
  fi
} > "$RAW/checks-result.md"

TEST_FILES_JSON="$(printf '%s\n' "${ALL_TEST_FILES[@]-}" | jq -R . | jq -s 'map(select(length > 0))')"
WORKTREE_JSON="null"
[ "$KEEP" != true ] || WORKTREE_JSON="$(jq -n --arg w "$WT" '$w')"

jq -n \
  --arg deps_status "$DEPS_STATUS" --arg deps_reason "$DEPS_REASON" \
  --arg tc_status "$AGG_TC_STATUS" --arg tc_reason "$AGG_TC_REASON" \
  --arg lint_status "$AGG_LINT_STATUS" --arg lint_reason "$AGG_LINT_REASON" \
  --arg test_status "$AGG_TEST_STATUS" --arg test_reason "$AGG_TEST_REASON" \
  --argjson test_files "$TEST_FILES_JSON" \
  --argjson packages "$PACKAGES_JSON" \
  --argjson worktree "$WORKTREE_JSON" \
  '{
    deps: {status: $deps_status, reason: (if $deps_reason=="" then null else $deps_reason end)},
    typecheck: {status: $tc_status, reason: (if $tc_reason=="" then null else $tc_reason end)},
    lint: {status: $lint_status, reason: (if $lint_reason=="" then null else $lint_reason end)},
    test: {status: $test_status, reason: (if $test_reason=="" then null else $test_reason end), files: $test_files},
    packages: $packages,
    worktree: $worktree
  }' > "$RAW/checks.json"

echo "verificações em: $RAW/checks-result.md"
jq -r '"  deps=\(.deps.status)  typecheck=\(.typecheck.status)  lint=\(.lint.status)  test=\(.test.status)  pacotes=\(.packages|length)"' "$RAW/checks.json"

exit "$OVERALL_RC"
