#!/usr/bin/env bash
#
# Publica no GitHub o review inline gerado pela skill em
# temp/cr/<pr>/review-<sha7>.json. A skill nunca chama este script
# sozinha — só o usuário, quando decidir publicar.
#
#   scripts/post-review.sh <pr>                 # usa o review-<sha7>.json mais recente
#   scripts/post-review.sh <pr> --sha <sha7>    # força uma rodada específica
#
# Valida o JSON, confere que commit_id ainda é o head atual do PR (recusa
# se divergir — o PR mudou desde que o review foi escrito) e posta com
# gh api .../reviews.
#
# Códigos de saída:
#   0  publicado
#   2  erro de uso: sem PR numérico, review-*.json ausente, ou JSON inválido
#   3  commit_id do review diverge do head atual do PR — revisar de novo
#   4  gh recusou a publicação

set -euo pipefail

BASE_DIR="${CR_BASE_DIR:-$PWD}"

usage() {
  sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

TARGET=""
SHA_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sha) SHA_OVERRIDE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "opção desconhecida: $1" >&2; usage >&2; exit 2 ;;
    *) TARGET="$1"; shift ;;
  esac
done

[ -n "$TARGET" ] || { echo "informe o número do PR" >&2; exit 2; }
printf '%s' "$TARGET" | grep -qE '^[0-9]+$' \
  || { echo "post-review.sh só publica em PR numérico (recebido: $TARGET)" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || { echo "'jq' não encontrado no PATH." >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { echo "'gh' não encontrado no PATH." >&2; exit 2; }

REPORT_DIR="$BASE_DIR/temp/cr/$TARGET"

if [ -n "$SHA_OVERRIDE" ]; then
  REVIEW_FILE="$REPORT_DIR/review-$SHA_OVERRIDE.json"
  [ -f "$REVIEW_FILE" ] || { echo "não encontrado: $REVIEW_FILE" >&2; exit 2; }
else
  REVIEW_FILE=""
  for rf in "$REPORT_DIR"/review-*.json; do
    [ -e "$rf" ] || continue
    if [ -z "$REVIEW_FILE" ] || [ "$rf" -nt "$REVIEW_FILE" ]; then REVIEW_FILE="$rf"; fi
  done
  [ -n "$REVIEW_FILE" ] || { echo "nenhum review-*.json em $REPORT_DIR — rode a revisão primeiro" >&2; exit 2; }
fi

# ---------- validação do JSON ----------
jq -e 'has("commit_id") and (.commit_id | type == "string") and (.commit_id != "")' \
  "$REVIEW_FILE" >/dev/null 2>&1 \
  || { echo "$REVIEW_FILE: commit_id ausente ou vazio" >&2; exit 2; }

jq -e '(.event // "") as $e | ["APPROVE","COMMENT","REQUEST_CHANGES"] | index($e) != null' \
  "$REVIEW_FILE" >/dev/null 2>&1 \
  || { echo "$REVIEW_FILE: event ausente ou inválido (precisa ser APPROVE, COMMENT ou REQUEST_CHANGES)" >&2; exit 2; }

jq -e 'has("body") and (.body | type == "string")' "$REVIEW_FILE" >/dev/null 2>&1 \
  || { echo "$REVIEW_FILE: body ausente" >&2; exit 2; }

jq -e '(.comments // []) | (type == "array") and all(.[]; has("path") and has("line") and has("body"))' \
  "$REVIEW_FILE" >/dev/null 2>&1 \
  || { echo "$REVIEW_FILE: comments malformado (cada item precisa de path, line e body)" >&2; exit 2; }

# ---------- commit_id ainda é o head do PR? ----------
COMMIT_ID="$(jq -r '.commit_id' "$REVIEW_FILE")"
CURRENT_HEAD="$(gh pr view "$TARGET" --json headRefOid -q .headRefOid 2>/dev/null || true)"
[ -n "$CURRENT_HEAD" ] || { echo "não foi possível ler o head atual do PR $TARGET pelo gh" >&2; exit 2; }

if [ "$COMMIT_ID" != "$CURRENT_HEAD" ]; then
  echo "commit_id do review ($COMMIT_ID) diverge do head atual do PR ($CURRENT_HEAD)." >&2
  echo "o PR mudou desde que este review foi escrito — revise de novo antes de publicar." >&2
  exit 3
fi

# ---------- publica ----------
if ! gh api "repos/{owner}/{repo}/pulls/$TARGET/reviews" --method POST --input "$REVIEW_FILE" >/dev/null; then
  echo "gh recusou a publicação do review em $REVIEW_FILE" >&2
  exit 4
fi

echo "review publicado no PR $TARGET a partir de $REVIEW_FILE"
