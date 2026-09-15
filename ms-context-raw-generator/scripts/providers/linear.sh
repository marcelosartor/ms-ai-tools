#!/usr/bin/env bash
#
# Provider Linear para fetch-raw-context.sh. Mesmo contrato dos demais.
#
# Diferente de ClickUp/Jira: a API do Linear é só GraphQL, sem endpoint REST
# por ticket — por isso linear_fetch usa http_post (definido em
# fetch-raw-context.sh) em vez de http_get.
#
# Anexo no Linear não tem um campo único e confiável como o attachment[] do
# Jira ou o attachments[] do ClickUp:
#   - a conexão `attachments` da issue é para link externo (PR do GitHub,
#     arquivo do Figma, thread do Slack) — não é arquivo para baixar, por
#     isso entra no dossiê como referência, não como candidato a extração;
#   - arquivo de verdade (screenshot colado, upload direto) vira link
#     embutido no markdown da descrição/comentário, formato
#     https://uploads.linear.app/<...>, sem metadado de tamanho/autor —
#     por isso é garimpado por regex, best effort, documentado aqui e no
#     README da ferramenta.
#
# Credenciais (do .env compartilhado do pool):
#   LINEAR_API_KEY   personal API key (Settings > Security & access > API)

LINEAR_API="${LINEAR_API_URL:-https://api.linear.app/graphql}"

linear_id_matches() {
  printf '%s' "$1" | grep -qE '^[A-Za-z][A-Za-z0-9]{1,9}-[0-9]+$'
}

linear_credentials() {
  local token="${LINEAR_API_KEY:-}"
  if [ -z "$token" ]; then
    REASON="LINEAR_API_KEY ausente; crie $CRED_FILE a partir do .env.example da skill"
    return 1
  fi
  AUTH_HEADER="$token"
}

LINEAR_QUERY='
query($id: String!) {
  issue(id: $id) {
    identifier
    title
    description
    url
    priorityLabel
    createdAt
    updatedAt
    state { name }
    assignee { name email }
    creator { name email }
    team { name key }
    project { name }
    labels { nodes { name } }
    parent { identifier }
    comments { nodes { body user { name } } }
    attachments { nodes { title url subtitle } }
  }
}'

linear_fetch() {
  local id="$1" code payload
  payload="$RAW/linear-query.json"
  jq -n --arg q "$LINEAR_QUERY" --arg id "$id" '{query: $q, variables: {id: $id}}' > "$payload"

  code="$(http_post "$LINEAR_API" "$payload" "$RAW/ticket.json")"
  if [ "$code" != "200" ]; then
    REASON="Linear devolveu HTTP $code para o ticket $id"
    return 1
  fi

  if jq -e '.errors' "$RAW/ticket.json" >/dev/null 2>&1; then
    REASON="Linear devolveu erro para o ticket $id: $(jq -r '.errors[0].message // "erro desconhecido"' "$RAW/ticket.json")"
    return 1
  fi
  if jq -e '.data.issue == null' "$RAW/ticket.json" >/dev/null 2>&1; then
    REASON="ticket $id não encontrado no Linear"
    return 1
  fi

  {
    jq -r '
      .data.issue as $i |
      "# " + ($i.title // "(sem título)"),
      "",
      "- board: Linear",
      "- id: " + ($i.identifier // "-"),
      "- url: " + ($i.url // "-"),
      "- status: " + ($i.state.name // "-") + " | prioridade: " + ($i.priorityLabel // "-"),
      "- time: " + ($i.team.name // "-") + " (" + ($i.team.key // "-") + ") | projeto: " + ($i.project.name // "-"),
      "- responsável: " + ($i.assignee.name // "(sem responsável)") + " | criador: " + ($i.creator.name // "-"),
      "- criado: " + ($i.createdAt // "-") + " | atualizado: " + ($i.updatedAt // "-"),
      "- labels: " + ((($i.labels.nodes // []) | map(.name) | join(", ")) | if . == "" then "(nenhuma)" else . end),
      "- épico/pai: " + ($i.parent.identifier // "-"),
      "",
      "## Descrição",
      "",
      ($i.description // "(vazia)"),
      ""
    ' "$RAW/ticket.json"
    if jq -e '(.data.issue.comments.nodes // []) | length > 0' "$RAW/ticket.json" >/dev/null 2>&1; then
      printf '## Comentários\n\n'
      jq -r '.data.issue.comments.nodes[] | "- **" + (.user.name // "?") + "**: " + ((.body // "") | gsub("\n"; " "))' "$RAW/ticket.json"
    fi
    if jq -e '(.data.issue.attachments.nodes // []) | length > 0' "$RAW/ticket.json" >/dev/null 2>&1; then
      printf '\n## Recursos vinculados\n\n'
      jq -r '.data.issue.attachments.nodes[] | "- [" + (.title // .url) + "](" + .url + ")" + (if .subtitle then " — " + .subtitle else "" end)' "$RAW/ticket.json"
    fi
  } > "$RAW/ticket.md"
}

linear_attachments() {
  # arquivo de verdade (não link externo) é garimpado por regex em
  # description + comentários; ver comentário no topo do arquivo.
  {
    jq -r '.data.issue.description // ""' "$RAW/ticket.json"
    jq -r '(.data.issue.comments.nodes // [])[].body // ""' "$RAW/ticket.json"
  } | grep -oE 'https://uploads\.linear\.app/[^ )\"'"'"']+' | sort -u \
    | jq -R -s '
        split("\n") | map(select(length > 0))
        | to_entries
        | map(
            (.value | (split("/") | last)) as $nome
            | {
                id: ("upload-" + ((.key + 1) | tostring)),
                titulo: $nome,
                extensao: (if ($nome | test("\\.")) then ($nome | split(".") | last | ascii_downcase) else "" end),
                tamanho: 0,
                data: null,
                autor: null,
                url: .value,
                auth: true
              }
          )
      ' > "$RAW/attachments.json" 2>/dev/null || echo '[]' > "$RAW/attachments.json"
}
