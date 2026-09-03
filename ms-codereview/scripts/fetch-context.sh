#!/usr/bin/env bash
#
# Coleta determinística de contexto para a skill ms-codereview.
#
#   scripts/fetch-context.sh <pr>                      # PR do GitHub + ticket do tracker
#   scripts/fetch-context.sh <pr> --task ABC-123       # força o id do ticket
#   scripts/fetch-context.sh <pr> --provider jira      # força o tracker
#   scripts/fetch-context.sh main...HEAD               # sem PR; só tenta o ticket pela branch
#
# Grava tudo em <base>/temp/cr/<pr>/raw/ (base = $CR_BASE_DIR ou o diretório atual).
# O ticket sai sempre nos mesmos arquivos, seja qual for o tracker:
# raw/ticket.md, raw/ticket.json, raw/ticket-comments.json.
# Não imprime credencial em nenhuma hipótese.
#
# Códigos de saída:
#   0  contexto completo (PR e/ou ticket obtidos)
#   2  erro de uso
#   3  não foi possível descobrir o id do ticket
#   4  credencial do tracker ausente (crie o .env na raiz da skill)
#   5  a API do tracker recusou ou não devolveu o ticket
#
# 3, 4 e 5 são "faltou dado", não "deu ruim": quem chama decide o que fazer.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_DIR="${CR_BASE_DIR:-$PWD}"

# Diretório do pool: guarda as credenciais e as dependências que o instalador
# baixou (hoje o jq). Entra na frente do PATH para que o binário verificado
# pelo instalador seja o usado.
CONFIG_DIR="${MS_AI_TOOLS_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/ms-ai-tools}"
CRED_FILE="$CONFIG_DIR/.env"
if [ -d "$CONFIG_DIR/bin" ]; then PATH="$CONFIG_DIR/bin:$PATH"; fi

usage() {
  sed -n '3,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

TARGET=""
TASK_OVERRIDE=""
PROVIDER_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --task) TASK_OVERRIDE="${2:-}"; shift 2 ;;
    --provider) PROVIDER_OVERRIDE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "opção desconhecida: $1" >&2; usage >&2; exit 2 ;;
    *) TARGET="$1"; shift ;;
  esac
done

[ -n "$TARGET" ] || { echo "informe o número do PR ou o range de refs" >&2; exit 2; }

for bin in jq curl; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "'$bin' não encontrado no PATH." >&2
    echo "  npx github:marcelosartor/ms-ai-tools --deps   # baixa o jq verificado" >&2
    echo "  ou instale pelo sistema (ex.: sudo apt install $bin)" >&2
    exit 2; }
done

SLUG="$(printf '%s' "$TARGET" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\{2,\}/-/g; s/^-//; s/-$//')"
RAW="$BASE_DIR/temp/cr/$SLUG/raw"
mkdir -p "$RAW"

# ---------- 0. manter temp/ fora do versionamento ----------
# Idempotente: só escreve se o caminho ainda não estiver ignorado por algum
# .gitignore (local, do repo ou global). CR_SKIP_GITIGNORE=1 desliga.
ensure_gitignore() {
  [ -z "${CR_SKIP_GITIGNORE:-}" ] || return 0
  command -v git >/dev/null 2>&1 || return 0

  local root rel file
  root="$(git -C "$BASE_DIR" rev-parse --show-toplevel 2>/dev/null)" || return 0
  [ -n "$root" ] || return 0

  git -C "$root" check-ignore -q "$BASE_DIR/temp" 2>/dev/null && return 0

  rel="$(realpath --relative-to="$root" "$BASE_DIR/temp" 2>/dev/null || echo temp)"
  file="$root/.gitignore"

  if [ -e "$file" ] && [ ! -w "$file" ]; then
    echo "aviso: $file não é gravável; adicione '$rel/' manualmente" >&2
    return 0
  fi

  if [ -s "$file" ]; then
    # tail -c1 vem vazio quando o arquivo já termina em quebra de linha
    [ -z "$(tail -c1 "$file")" ] || printf '\n' >> "$file"
    printf '\n' >> "$file"
  fi
  printf '# contexto de code review (skill ms-codereview)\n%s/\n' "$rel" >> "$file"
  echo "adicionado '$rel/' a $file"
}
ensure_gitignore

STATUS_FILE="$RAW/context-status.json"
PR_OK=false
TASK_OK=false
TASK_ID=""
PROVIDER=""
REASON=""

write_status() {
  jq -n \
    --arg target "$TARGET" \
    --arg raw "$RAW" \
    --arg provider "$PROVIDER" \
    --arg task_id "$TASK_ID" \
    --arg reason "$REASON" \
    --arg generated_at "$(date -Iseconds)" \
    --argjson pr_ok "$PR_OK" \
    --argjson task_ok "$TASK_OK" \
    '{target:$target, raw_dir:$raw, pr_fetched:$pr_ok,
      provider:(if $provider=="" then null else $provider end),
      task_id:(if $task_id=="" then null else $task_id end),
      task_fetched:$task_ok, reason:(if $reason=="" then null else $reason end), generated_at:$generated_at}' \
    > "$STATUS_FILE"
  echo "contexto em: $RAW"
  jq -r '"  pr_fetched=\(.pr_fetched)  provider=\(.provider // "-")  task_id=\(.task_id // "-")  task_fetched=\(.task_fetched)  reason=\(.reason // "-")"' "$STATUS_FILE"
}

# ---------- 1. credenciais ----------
# Carregadas antes de tudo: o .env é quem diz qual tracker está configurado.
#
# Ficam fora do diretório da skill para sobreviver a reinstalação e a
# atualização automática. O .env local, quando existe, vence o compartilhado:
# o mais específico ganha.
for envfile in "$CRED_FILE" "$SKILL_DIR/.env"; do
  [ -f "$envfile" ] || continue
  set -a
  # shellcheck disable=SC1091
  . "$envfile"
  set +a
done

# GET autenticado sem passar credencial por argv: a config vai por stdin,
# que não aparece em `ps`. AUTH_HEADER é definido pelo provider.
AUTH_HEADER=""
http_get() { # $1 = url  $2 = arquivo de saída -> imprime o http_code
  {
    printf 'silent\nshow-error\nlocation\n'
    printf 'header = "Accept: application/json"\n'
    [ -z "$AUTH_HEADER" ] || printf 'header = "Authorization: %s"\n' "$AUTH_HEADER"
    printf 'url = "%s"\n' "$1"
    printf 'output = "%s"\n' "$2"
    printf 'write-out = "%%{http_code}"\n'
  } | curl --config - 2>>"$RAW/http-error.log" || echo "000"
}

# shellcheck disable=SC1091
. "$SKILL_DIR/scripts/providers/clickup.sh"
# shellcheck disable=SC1091
. "$SKILL_DIR/scripts/providers/jira.sh"

PROVIDERS="clickup jira"

# ---------- 2. PR do GitHub ----------
if printf '%s' "$TARGET" | grep -qE '^[0-9]+$' && command -v gh >/dev/null 2>&1; then
  if gh pr view "$TARGET" \
       --json number,title,url,state,isDraft,author,baseRefName,headRefName,body,additions,deletions,changedFiles,files,labels,createdAt,mergedAt,closedAt \
       > "$RAW/pr.json" 2>"$RAW/gh-error.log"; then
    jq -r '.body // ""' "$RAW/pr.json" > "$RAW/pr-body.md"
    jq -r '.files[] | "\(.additions)\t\(.deletions)\t\(.path)"' "$RAW/pr.json" > "$RAW/pr-files.tsv" 2>/dev/null || true
    gh pr view "$TARGET" --comments > "$RAW/pr-comments.md" 2>/dev/null || true
    rm -f "$RAW/gh-error.log"
    PR_OK=true
  fi
fi

# ---------- 3. tracker e id do ticket ----------
context_text() {
  [ ! -f "$RAW/pr.json" ] || jq -r '(.body // "") + "\n" + (.headRefName // "")' "$RAW/pr.json"
  git -C "$BASE_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true
}

PROVIDER="${PROVIDER_OVERRIDE:-${TRACKER_PROVIDER:-auto}}"

if [ "$PROVIDER" != "auto" ]; then
  case " $PROVIDERS " in
    *" $PROVIDER "*) ;;
    *) echo "tracker desconhecido: $PROVIDER (use: $PROVIDERS)" >&2; exit 2 ;;
  esac
fi

if [ -n "$TASK_OVERRIDE" ]; then
  TASK_ID="$TASK_OVERRIDE"
  if [ "$PROVIDER" = "auto" ]; then
    for p in $PROVIDERS; do
      if "${p}_id_matches" "$TASK_ID"; then PROVIDER="$p"; break; fi
    done
  fi
else
  TEXT="$(context_text)"
  # Duas passagens: sinal forte (url/badge do tracker) antes do fraco (chave
  # solta no texto, slug de branch), para não confundir os formatos.
  for pass in strong weak; do
    [ -z "$TASK_ID" ] || break
    for p in $PROVIDERS; do
      [ "$PROVIDER" = "auto" ] || [ "$PROVIDER" = "$p" ] || continue
      TASK_ID="$(printf '%s' "$TEXT" | "${p}_extract" "$pass" || true)"
      if [ -n "$TASK_ID" ]; then PROVIDER="$p"; break; fi
    done
  done
fi

if [ -z "$TASK_ID" ]; then
  [ "$PROVIDER" != "auto" ] || PROVIDER=""
  REASON="nenhum id de ticket encontrado no corpo do PR nem no nome da branch; rode de novo com --task <id> [--provider <$(printf '%s' "$PROVIDERS" | tr ' ' '|')>]"
  write_status
  exit 3
fi

if [ "$PROVIDER" = "auto" ]; then
  PROVIDER=""
  REASON="id '$TASK_ID' não corresponde ao formato de nenhum tracker suportado; rode de novo com --provider <$(printf '%s' "$PROVIDERS" | tr ' ' '|')>"
  write_status
  exit 3
fi

# ---------- 4. credencial do tracker ----------
if ! "${PROVIDER}_credentials"; then
  write_status
  exit 4
fi

# ---------- 5. ticket ----------
if ! "${PROVIDER}_fetch" "$TASK_ID"; then
  write_status
  exit 5
fi

TASK_OK=true
write_status
