#!/usr/bin/env bash
#
# Provider Linear para fetch-context.sh. Mesmo contrato dos demais.
#
# Diferente de ClickUp/Jira: a API do Linear é só GraphQL, sem endpoint REST
# por ticket — por isso linear_fetch usa http_post (definido em
# fetch-context.sh) em vez de http_get. A API aceita o campo `id` da query
# `issue` como UUID ou como o identificador legível (ex.: ENG-123), então
# não precisa de uma busca separada para resolver o id em UUID.
#
# Credenciais (do .env da skill):
#   LINEAR_API_KEY   personal API key (Settings > Security & access > API)
#
# Contrato (compartilhado por todos os providers):
#   <p>_extract <strong|weak>  lê texto no stdin e imprime o id do ticket
#   <p>_id_matches <id>        0 se o id tem o formato deste tracker
#   <p>_credentials            0 se dá para autenticar; senão define REASON e devolve 1
#   <p>_fetch <id>             grava ticket.json/.md em $RAW; senão define REASON e devolve 1

LINEAR_API="${LINEAR_API_URL:-https://api.linear.app/graphql}"

# Identificador do Linear tem a mesma cara de uma chave do Jira (CHAVE-123).
# Prefixo de conventional commit não é chave de projeto, mesma exclusão do
# jira.sh — duplicada aqui para o provider não depender da ordem de source.
LINEAR_NOT_A_KEY='^(feat|feature|fix|hotfix|bugfix|chore|refactor|docs|test|tests|build|ci|perf|style|revert|release|wip)-'

linear_extract() {
  case "$1" in
    strong)
      # linear.app/<workspace>/issue/CHAVE-123[/slug]
      grep -oiE 'linear\.app/[A-Za-z0-9_-]+/issue/[A-Za-z][A-Za-z0-9]{1,9}-[0-9]+' \
        | head -1 \
        | grep -oiE '[A-Za-z][A-Za-z0-9]{1,9}-[0-9]+$' \
        | tr 'a-z' 'A-Z'
      ;;
    weak)
      # chave solta no corpo do PR ou no nome da branch (feat/ENG-123-titulo)
      grep -oE '\b[A-Za-z][A-Za-z0-9]{1,9}-[0-9]+\b' \
        | grep -viE "$LINEAR_NOT_A_KEY" \
        | head -1 \
        | tr 'a-z' 'A-Z'
      ;;
  esac
}

linear_id_matches() {
  printf '%s' "$1" | grep -qE '^[A-Za-z][A-Za-z0-9]{1,9}-[0-9]+$'
}

linear_credentials() {
  local token="${LINEAR_API_KEY:-}"
  if [ -z "$token" ]; then
    REASON="LINEAR_API_KEY ausente; crie $CRED_FILE a partir do .env.example da skill"
    return 1
  fi
  # personal API key: vai crua no header, sem prefixo Bearer (assim que o
  # Linear documenta a autenticação por chave pessoal).
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
      "- tracker: Linear",
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
  } > "$RAW/ticket.md"
}
