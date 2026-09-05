#!/usr/bin/env bash
#
# Detecção determinística de quais checklists carregar, a partir do diff.
# Chamado pelo fetch-context.sh logo depois de buscar o PR; roda também
# sozinho para depurar:
#
#   scripts/detect-checklists.sh <alvo>
#
# Lê checklists/index.json — dado, não código: adicionar checklist não
# toca este script — e grava <base>/temp/cr/<alvo>/raw/checklists.json:
#
#   { "load": ["frontend-react"], "why": {"frontend-react": "paths: src/x.tsx"}, "security": false }
#
# "security" é preenchido pela extensão de segurança (F6); aqui sai sempre
# false.
#
# Semântica de cada entrada do índice: o checklist entra se qualquer
# "paths" casar com um arquivo do diff, ou qualquer "deps" estiver em
# dependencies/devDependencies do package.json da raiz e o diff tocar
# algum arquivo .ts/.tsx/.js/.jsx/.vue, ou qualquer "content" (regex ERE,
# case-insensitive) aparecer numa linha adicionada do diff.
#
# Glob sem find nem regex: "**/" na frente do padrão também casa sem
# nenhum prefixo de diretório (glob_match abaixo).

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_DIR="${CR_BASE_DIR:-$PWD}"
INDEX="$SKILL_DIR/checklists/index.json"

TARGET="${1:-}"
[ -n "$TARGET" ] || { echo "informe o número do PR ou o range de refs" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "'jq' não encontrado no PATH." >&2; exit 2; }

SLUG="$(printf '%s' "$TARGET" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\{2,\}/-/g; s/^-//; s/-$//')"
RAW="$BASE_DIR/temp/cr/$SLUG/raw"
mkdir -p "$RAW"
OUT="$RAW/checklists.json"

# ---------- base/head do diff: do PR já buscado, ou do range do alvo ----------
split_range() { # $1=alvo -> "base<TAB>head", vazio se não é um range
  case "$1" in
    *...*) printf '%s\t%s\n' "${1%%...*}" "${1##*...}" ;;
    *..*)  printf '%s\t%s\n' "${1%%..*}" "${1##*..}" ;;
  esac
}

BASE_SHA=""
HEAD_SHA=""
if [ -f "$RAW/pr.json" ]; then
  BASE_SHA="$(jq -r '.baseRefOid // empty' "$RAW/pr.json")"
  HEAD_SHA="$(jq -r '.headRefOid // empty' "$RAW/pr.json")"
else
  PAIR="$(split_range "$TARGET")"
  if [ -n "$PAIR" ]; then
    BASE_SHA="$(git -C "$BASE_DIR" rev-parse "${PAIR%%$'\t'*}" 2>/dev/null || true)"
    HEAD_SHA="$(git -C "$BASE_DIR" rev-parse "${PAIR#*$'\t'}" 2>/dev/null || true)"
  else
    HEAD_SHA="$(git -C "$BASE_DIR" rev-parse "$TARGET" 2>/dev/null || true)"
  fi
fi

DIFF_RANGE=""
if [ -n "$BASE_SHA" ] && [ -n "$HEAD_SHA" ]; then
  DIFF_RANGE="$BASE_SHA...$HEAD_SHA"
fi

# ---------- arquivos tocados ----------
FILES=()
if [ -f "$RAW/pr-files.tsv" ]; then
  while IFS=$'\t' read -r _ _ path; do
    [ -n "$path" ] && FILES+=("$path")
  done < "$RAW/pr-files.tsv"
elif [ -n "$DIFF_RANGE" ]; then
  while IFS= read -r path; do
    [ -n "$path" ] && FILES+=("$path")
  done < <(git -C "$BASE_DIR" diff --name-only "$DIFF_RANGE" 2>/dev/null || true)
fi

# ---------- linhas adicionadas (para "content") ----------
ADDED_LINES=""
if [ -n "$DIFF_RANGE" ]; then
  ADDED_LINES="$(git -C "$BASE_DIR" diff "$DIFF_RANGE" 2>/dev/null | grep -E '^\+[^+]' || true)"
fi

# ---------- dependências do package.json da raiz ----------
ROOT_PKG="$BASE_DIR/package.json"
HAS_JS_FILE=false
for f in "${FILES[@]}"; do
  case "$f" in
    *.ts|*.tsx|*.js|*.jsx|*.vue) HAS_JS_FILE=true; break ;;
  esac
done

dep_present() { # $1=nome da dependência
  [ -f "$ROOT_PKG" ] || return 1
  jq -e --arg d "$1" '((.dependencies // {}) + (.devDependencies // {})) | has($d)' "$ROOT_PKG" >/dev/null 2>&1
}

# ---------- glob sem find nem regex: case do bash ----------
glob_match() { # $1=pattern $2=caminho
  local pattern="$1" path="$2" stripped
  case "$path" in
    $pattern) return 0 ;;
  esac
  case "$pattern" in
    '**/'*)
      stripped="${pattern#\*\*/}"
      case "$path" in
        $stripped) return 0 ;;
      esac
      ;;
  esac
  return 1
}

# ---------- avaliação de cada checklist do índice ----------
MATCHES_FILE="$(mktemp)"
trap 'rm -f "$MATCHES_FILE"' EXIT

while IFS= read -r name; do
  [ -n "$name" ] || continue
  REASON_PARTS=()

  MATCHED_PATH=""
  while IFS= read -r pattern; do
    [ -n "$pattern" ] || continue
    for f in "${FILES[@]}"; do
      if glob_match "$pattern" "$f"; then MATCHED_PATH="$f"; break 2; fi
    done
  done < <(jq -r --arg n "$name" '.[$n].paths // [] | .[]' "$INDEX")
  [ -z "$MATCHED_PATH" ] || REASON_PARTS+=("paths: $MATCHED_PATH")

  if [ ${#REASON_PARTS[@]} -eq 0 ] && [ "$HAS_JS_FILE" = true ]; then
    MATCHED_DEP=""
    while IFS= read -r dep; do
      [ -n "$dep" ] || continue
      if dep_present "$dep"; then MATCHED_DEP="$dep"; break; fi
    done < <(jq -r --arg n "$name" '.[$n].deps // [] | .[]' "$INDEX")
    [ -z "$MATCHED_DEP" ] || REASON_PARTS+=("deps: $MATCHED_DEP")
  fi

  if [ ${#REASON_PARTS[@]} -eq 0 ] && [ -n "$ADDED_LINES" ]; then
    MATCHED_CONTENT=""
    while IFS= read -r cpattern; do
      [ -n "$cpattern" ] || continue
      if printf '%s\n' "$ADDED_LINES" | grep -qiE -- "$cpattern"; then
        MATCHED_CONTENT="$cpattern"
        break
      fi
    done < <(jq -r --arg n "$name" '.[$n].content // [] | .[]' "$INDEX")
    [ -z "$MATCHED_CONTENT" ] || REASON_PARTS+=("content: $MATCHED_CONTENT")
  fi

  if [ ${#REASON_PARTS[@]} -gt 0 ]; then
    WHY_TEXT="$(IFS='; '; echo "${REASON_PARTS[*]}")"
    jq -n -c --arg name "$name" --arg why "$WHY_TEXT" '{name:$name, why:$why}' >> "$MATCHES_FILE"
  fi
done < <(jq -r 'keys[]' "$INDEX")

jq -s '{load: map(.name), why: (map({(.name): .why}) | add // {}), security: false}' "$MATCHES_FILE" > "$OUT"

echo "checklists em: $OUT"
jq -r '"  load=\(if (.load|length)==0 then "-" else (.load|join(", ")) end)"' "$OUT"
