#!/usr/bin/env bash
#
# Coleta determinística de contexto bruto de um ticket de board para a
# skill ms-context-raw-generator.
#
#   scripts/fetch-raw-context.sh <ticket>                    # descobre o board pelo formato do id
#   scripts/fetch-raw-context.sh <ticket> --provider jira     # força o board
#   scripts/fetch-raw-context.sh <ticket> --refresh            # ignora cache e busca de novo
#
# Grava tudo em <base>/temp/<ticket>/context-raw/raw/ (base = $CRG_BASE_DIR
# ou o diretório atual): ticket.json, ticket.md, attachments.json,
# attachments/<id>.<ext> (baixados), attachments-manifest.md. Não decide
# reaproveitar ou regenerar sozinho — quem chama (a skill) pergunta ao
# usuário e passa --refresh quando for o caso; sem a flag, achar
# raw/ticket.md já existente é o script saindo cedo, sem tocar a rede.
#
# Não imprime credencial em nenhuma hipótese.
#
# Códigos de saída:
#   0  contexto coletado (novo ou reaproveitado do cache)
#   2  erro de uso
#   3  id não corresponde ao formato de nenhum board com credencial configurada
#   4  credencial do board ausente
#   5  a API do board recusou ou não devolveu o ticket

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_DIR="${CRG_BASE_DIR:-$PWD}"

CONFIG_DIR="${MS_AI_TOOLS_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/ms-ai-tools}"
CRED_FILE="$CONFIG_DIR/.env"
if [ -d "$CONFIG_DIR/bin" ]; then PATH="$CONFIG_DIR/bin:$PATH"; fi

usage() {
  sed -n '3,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

TICKET=""
PROVIDER_OVERRIDE=""
REFRESH=false
while [ $# -gt 0 ]; do
  case "$1" in
    --provider) PROVIDER_OVERRIDE="${2:-}"; shift 2 ;;
    --refresh) REFRESH=true; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "opção desconhecida: $1" >&2; usage >&2; exit 2 ;;
    *) TICKET="$1"; shift ;;
  esac
done

[ -n "$TICKET" ] || { echo "informe o id do ticket" >&2; usage >&2; exit 2; }

for bin in jq curl; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "'$bin' não encontrado no PATH." >&2
    echo "  npx github:marcelosartor/ms-ai-tools --deps   # baixa o jq verificado" >&2
    echo "  ou instale pelo sistema (ex.: sudo apt install $bin)" >&2
    exit 2; }
done

SLUG="$(printf '%s' "$TICKET" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\{2,\}/-/g; s/^-//; s/-$//')"
CTX_DIR="$BASE_DIR/temp/$SLUG/context-raw"
RAW="$CTX_DIR/raw"
mkdir -p "$RAW"

# ---------- manter temp/ fora do versionamento ----------
# Idempotente: só escreve se o caminho ainda não estiver ignorado por algum
# .gitignore (local, do repo ou global). CRG_SKIP_GITIGNORE=1 desliga.
ensure_gitignore() {
  [ -z "${CRG_SKIP_GITIGNORE:-}" ] || return 0
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
    [ -z "$(tail -c1 "$file")" ] || printf '\n' >> "$file"
    printf '\n' >> "$file"
  fi
  printf '# contexto bruto (skill ms-context-raw-generator)\n%s/\n' "$rel" >> "$file"
  echo "adicionado '$rel/' a $file"
}
ensure_gitignore

# ---------- cache: sem --refresh, ticket.md já existente encerra aqui ----------
if [ "$REFRESH" != true ] && [ -f "$RAW/ticket.md" ]; then
  echo "cache em: $RAW (use --refresh para buscar de novo)"
  exit 0
fi

STATUS_FILE="$RAW/context-status.json"
PROVIDER=""
REASON=""

write_status() {
  jq -n \
    --arg ticket "$TICKET" \
    --arg raw "$RAW" \
    --arg provider "$PROVIDER" \
    --arg reason "$REASON" \
    --arg generated_at "$(date -Iseconds)" \
    '{ticket:$ticket, raw_dir:$raw,
      provider:(if $provider=="" then null else $provider end),
      reason:(if $reason=="" then null else $reason end), generated_at:$generated_at}' \
    > "$STATUS_FILE"
}

# ---------- credenciais ----------
# Compartilhadas com as demais ferramentas do pool: o .env fica fora da
# pasta da skill de propósito, para sobreviver a reinstalação e ser lido
# igual por qualquer ferramenta que precise de board.
for envfile in "$CRED_FILE" "$SKILL_DIR/.env"; do
  [ -f "$envfile" ] || continue
  set -a
  # shellcheck disable=SC1091
  . "$envfile"
  set +a
done

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

http_post() { # $1 = url  $2 = arquivo com o corpo  $3 = arquivo de saída -> imprime o http_code
  {
    printf 'silent\nshow-error\nlocation\n'
    printf 'header = "Accept: application/json"\n'
    printf 'header = "Content-Type: application/json"\n'
    [ -z "$AUTH_HEADER" ] || printf 'header = "Authorization: %s"\n' "$AUTH_HEADER"
    printf 'url = "%s"\n' "$1"
    printf 'data-binary = "@%s"\n' "$2"
    printf 'output = "%s"\n' "$3"
    printf 'write-out = "%%{http_code}"\n'
  } | curl --config - 2>>"$RAW/http-error.log" || echo "000"
}

# shellcheck disable=SC1091
. "$SKILL_DIR/scripts/providers/clickup.sh"
# shellcheck disable=SC1091
. "$SKILL_DIR/scripts/providers/jira.sh"
# shellcheck disable=SC1091
. "$SKILL_DIR/scripts/providers/linear.sh"
# shellcheck disable=SC1091
. "$SKILL_DIR/scripts/extract-attachments.sh"

PROVIDERS="clickup jira linear"

PROVIDER="${PROVIDER_OVERRIDE:-auto}"
if [ "$PROVIDER" != "auto" ]; then
  case " $PROVIDERS " in
    *" $PROVIDER "*) ;;
    *) echo "board desconhecido: $PROVIDER (use: $PROVIDERS)" >&2; exit 2 ;;
  esac
fi

if [ "$PROVIDER" = "auto" ]; then
  MATCHED=""
  for p in $PROVIDERS; do
    if "${p}_id_matches" "$TICKET"; then MATCHED="$MATCHED $p"; fi
  done
  MATCHED="${MATCHED# }"

  if [ -z "$MATCHED" ]; then
    REASON="id '$TICKET' não corresponde ao formato de nenhum board conhecido ($PROVIDERS); rode de novo com --provider <$(printf '%s' "$PROVIDERS" | tr ' ' '|')>"
    write_status
    exit 3
  fi

  # id ambíguo entre jira/linear (mesmo formato CHAVE-123): usa o primeiro
  # com credencial configurada, na ordem declarada em $PROVIDERS.
  for p in $PROVIDERS; do
    case " $MATCHED " in *" $p "*)
      if "${p}_credentials" >/dev/null 2>&1; then PROVIDER="$p"; break; fi
    ;; esac
  done

  if [ "$PROVIDER" = "auto" ]; then
    PROVIDER="$(printf '%s' "$MATCHED" | awk '{print $1}')"
  fi
fi

if ! "${PROVIDER}_credentials"; then
  write_status
  exit 4
fi

if ! "${PROVIDER}_fetch" "$TICKET"; then
  write_status
  exit 5
fi

"${PROVIDER}_attachments"
extract_attachments "$RAW"

write_status
echo "contexto bruto em: $RAW"
