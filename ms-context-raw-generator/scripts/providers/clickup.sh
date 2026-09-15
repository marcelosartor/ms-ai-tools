#!/usr/bin/env bash
#
# Provider ClickUp para fetch-raw-context.sh. Mesmo contrato de
# id_matches/credentials/fetch do ms-codereview (scripts/providers/*.sh),
# mais `<p>_attachments`, que este contrato não tinha porque o
# ms-codereview nunca precisou de anexo — só de texto do ticket.
#
# Contrato:
#   <p>_id_matches <id>    0 se o id tem o formato deste board
#   <p>_credentials        0 se dá para autenticar; senão define REASON e devolve 1
#   <p>_fetch <id>         grava ticket.json/.md em $RAW; senão define REASON e devolve 1
#   <p>_attachments        lê $RAW/ticket.json, grava $RAW/attachments.json normalizado
#
# Credenciais (do .env compartilhado do pool):
#   CLICKUP_TOKEN    token pessoal (Settings > Apps > API Token)
#   CLICKUP_TEAM_ID  só para id customizado (ex.: DEV-123)

CLICKUP_API="${CLICKUP_API_URL:-https://api.clickup.com/api/v2}"

clickup_id_matches() {
  # id nativo do ClickUp: alfanumérico sem hífen (ex.: 86ajrqjc7)
  printf '%s' "$1" | grep -qE '^[A-Za-z0-9]{6,}$'
}

clickup_credentials() {
  local token="${CLICKUP_TOKEN:-${CLICKUP_API_TOKEN:-${TOKEN:-}}}"
  if [ -z "$token" ]; then
    REASON="CLICKUP_TOKEN ausente; crie $CRED_FILE a partir do .env.example da skill"
    return 1
  fi
  AUTH_HEADER="$token"
}

clickup_fetch() {
  local id="$1" code
  code="$(http_get "$CLICKUP_API/task/$id?include_subtasks=true" "$RAW/ticket.json")"

  if [ "$code" != "200" ] && [ -n "${CLICKUP_TEAM_ID:-}" ]; then
    code="$(http_get "$CLICKUP_API/task/$id?custom_task_ids=true&team_id=$CLICKUP_TEAM_ID&include_subtasks=true" "$RAW/ticket.json")"
  fi

  if [ "$code" != "200" ]; then
    REASON="ClickUp devolveu HTTP $code para o ticket $id"
    return 1
  fi

  http_get "$CLICKUP_API/task/$id/comment" "$RAW/ticket-comments.json" >/dev/null || true

  {
    jq -r '
      "# " + (.name // "(sem título)"),
      "",
      "- board: ClickUp",
      "- id: " + (.id // "-"),
      "- url: " + (.url // "-"),
      "- status: " + (.status.status // "-"),
      "- lista: " + (.list.name // "-") + " / projeto: " + (.project.name // "-"),
      "- responsáveis: " + ((.assignees // []) | map(.username // .email // "?") | join(", ")),
      "- criado: " + (.date_created // "-") + " | atualizado: " + (.date_updated // "-"),
      "",
      "## Descrição",
      "",
      (.description // .text_content // "(vazia)"),
      "",
      "## Campos personalizados",
      ""
    ' "$RAW/ticket.json"
    jq -r '
      (.custom_fields // [])
      | map(select(.value != null and .value != ""))
      | if length == 0 then "(nenhum preenchido)"
        else .[] | "- " + (.name // "?") + ": " + (.value | tostring)
        end
    ' "$RAW/ticket.json"
    if [ -s "$RAW/ticket-comments.json" ]; then
      printf '\n## Comentários\n\n'
      jq -r '
        (.comments // [])
        | if length == 0 then "(nenhum)"
          else .[] | "- **" + (.user.username // "?") + "**: " + ((.comment_text // "") | gsub("\n"; " "))
          end
      ' "$RAW/ticket-comments.json" 2>/dev/null || echo "(não foi possível ler os comentários)"
    fi
  } > "$RAW/ticket.md"
}

clickup_attachments() {
  # URL do anexo já vem assinada: mandar Authorization pode invalidar a
  # assinatura, por isso auth:false.
  jq '[ (.attachments // [])[] | {
    id: (.id | tostring),
    titulo: (.title // (.id | tostring) // "anexo"),
    extensao: ((.extension // "") | ascii_downcase),
    tamanho: (.size // 0 | if type == "string" then (tonumber? // 0) else . end),
    data: (.date // null),
    autor: (.user.username // .user.email // null),
    url: (.url // .url_w_query // null),
    auth: false
  } ]' "$RAW/ticket.json" > "$RAW/attachments.json"
}
