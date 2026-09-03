#!/usr/bin/env bash
#
# Provider Jira para fetch-context.sh. Mesmo contrato do clickup.sh.
#
# Credenciais (do .env da skill):
#   JIRA_BASE_URL     https://empresa.atlassian.net  (ou o host do Server/DC)
#   JIRA_EMAIL        e-mail da conta            } Cloud: Basic
#   JIRA_API_TOKEN    token de id.atlassian.com  }
#   JIRA_TOKEN        Personal Access Token      -> Server/DC: Bearer
#   JIRA_API_VERSION  3 (Cloud, padrão) ou 2 (Server/DC); inferido pela URL

# Prefixos de conventional commit não são chave de projeto: sem isso,
# `fix/123-algo` viraria o ticket FIX-123.
JIRA_NOT_A_KEY='^(feat|feature|fix|hotfix|bugfix|chore|refactor|docs|test|tests|build|ci|perf|style|revert|release|wip)-'

jira_extract() {
  case "$1" in
    strong)
      # .../browse/ABC-123 e ...?selectedIssue=ABC-123
      grep -oiE '(browse/|selectedIssue=|issues/)[A-Za-z][A-Za-z0-9]{1,9}-[0-9]+' \
        | head -1 \
        | sed -E 's#^[^=/]*[=/]##' \
        | tr 'a-z' 'A-Z'
      ;;
    weak)
      # chave solta no corpo do PR ou no nome da branch (feat/ABC-123-titulo)
      grep -oE '\b[A-Za-z][A-Za-z0-9]{1,9}-[0-9]+\b' \
        | grep -viE "$JIRA_NOT_A_KEY" \
        | head -1 \
        | tr 'a-z' 'A-Z'
      ;;
  esac
}

jira_id_matches() {
  printf '%s' "$1" | grep -qE '^[A-Za-z][A-Za-z0-9]{1,9}-[0-9]+$'
}

jira_credentials() {
  if [ -z "${JIRA_BASE_URL:-}" ]; then
    REASON="JIRA_BASE_URL ausente; crie $SKILL_DIR/.env a partir do .env.example"
    return 1
  fi
  JIRA_BASE_URL="${JIRA_BASE_URL%/}"

  if [ -n "${JIRA_EMAIL:-}" ] && [ -n "${JIRA_API_TOKEN:-}" ]; then
    AUTH_HEADER="Basic $(printf '%s:%s' "$JIRA_EMAIL" "$JIRA_API_TOKEN" | base64 | tr -d '\n')"
  elif [ -n "${JIRA_TOKEN:-}" ]; then
    AUTH_HEADER="Bearer $JIRA_TOKEN"
  else
    REASON="credencial do Jira ausente; defina JIRA_EMAIL + JIRA_API_TOKEN (Cloud) ou JIRA_TOKEN (Server/DC) em $SKILL_DIR/.env"
    return 1
  fi

  if [ -z "${JIRA_API_VERSION:-}" ]; then
    case "$JIRA_BASE_URL" in
      *atlassian.net*|*jira-dev.com*) JIRA_API_VERSION=3 ;;
      *) JIRA_API_VERSION=2 ;;
    esac
  fi
}

# Descrição e comentários do Jira Cloud vêm em ADF (JSON), não em texto.
# Achata a árvore preservando parágrafo, lista, título e bloco de código.
JIRA_ADF_JQ='
def adf:
  if type == "array" then map(adf) | join("")
  elif type != "object" then ""
  elif type == "object" and (.type | not) then ""
  else
    (.type) as $t | (.content // []) as $c
    | if   $t == "text"        then (.text // "")
      elif $t == "hardBreak"   then "\n"
      elif $t == "mention"     then ((.attrs.text // .attrs.id // "") | if startswith("@") then . else "@" + . end)
      elif $t == "emoji"       then (.attrs.text // .attrs.shortName // "")
      elif $t == "inlineCard"  then (.attrs.url // "")
      elif $t == "rule"        then "\n---\n\n"
      elif $t == "paragraph"   then ($c | adf) + "\n\n"
      elif $t == "heading"     then (("#" * (((.attrs.level // 2) + 1))) + " " + ($c | adf) + "\n\n")
      elif $t == "codeBlock"   then "```" + (.attrs.language // "") + "\n" + (($c | adf) | sub("\n+$"; "")) + "\n```\n\n"
      elif $t == "blockquote"  then "> " + (($c | adf) | sub("\n+$"; "")) + "\n\n"
      elif $t == "listItem"    then "- " + (($c | adf) | sub("\n+$"; "") | gsub("\n"; "\n  ")) + "\n"
      elif $t == "taskItem"    then "- [" + (if .attrs.state == "DONE" then "x" else " " end) + "] " + ($c | adf) + "\n"
      elif ($t | test("List$")) then ($c | adf) + "\n"
      elif $t == "tableCell" or $t == "tableHeader" then (($c | adf) | sub("\n+$"; "")) + " | "
      elif $t == "tableRow"    then "| " + (($c | adf) | sub(" \\| $"; " |")) + "\n"
      elif $t == "table"       then ($c | adf) + "\n"
      elif $t == "media" or $t == "mediaSingle" or $t == "mediaGroup" then "(anexo)\n"
      else ($c | adf)
      end
  end;
def rich:
  if . == null then ""
  elif type == "string" then .
  elif type == "number" or type == "boolean" then tostring
  elif type == "array" then (map(rich) | map(select(. != "")) | join(", "))
  elif type == "object" then
    (if .type then adf
     elif has("value") then (.value | rich)
     elif has("displayName") then .displayName
     elif has("name") then .name
     else "" end)
  else "" end;
'

jira_fetch() {
  local id="$1" api code
  api="$JIRA_BASE_URL/rest/api/$JIRA_API_VERSION"

  code="$(http_get "$api/issue/$id" "$RAW/ticket.json")"
  if [ "$code" != "200" ]; then
    REASON="Jira devolveu HTTP $code para o ticket $id"
    return 1
  fi

  http_get "$api/issue/$id/comment?orderBy=created" "$RAW/ticket-comments.json" >/dev/null || true

  # nomes dos campos personalizados: sem isso o relatório sai com
  # "customfield_10014" no lugar de "Story points"
  http_get "$api/field" "$RAW/jira-fields.json" >/dev/null || true
  jq -e 'type == "array"' "$RAW/jira-fields.json" >/dev/null 2>&1 || echo '[]' > "$RAW/jira-fields.json"

  {
    jq -r "$JIRA_ADF_JQ"'
      "# " + (.fields.summary // "(sem título)"),
      "",
      "- tracker: Jira",
      "- id: " + (.key // "-"),
      "- url: " + $base + "/browse/" + (.key // ""),
      "- tipo: " + (.fields.issuetype.name // "-") + " | status: " + (.fields.status.name // "-") + " | prioridade: " + (.fields.priority.name // "-"),
      "- projeto: " + (.fields.project.name // "-") + " (" + (.fields.project.key // "-") + ")",
      "- responsável: " + (.fields.assignee.displayName // "(sem responsável)") + " | relator: " + (.fields.reporter.displayName // "-"),
      "- criado: " + (.fields.created // "-") + " | atualizado: " + (.fields.updated // "-"),
      "- labels: " + (((.fields.labels // []) | join(", ")) | if . == "" then "(nenhuma)" else . end),
      "- épico/pai: " + (.fields.parent.key // "-"),
      "",
      "## Descrição",
      "",
      ((.fields.description | rich) | if (. | gsub("\\s"; "")) == "" then "(vazia)" else . end),
      "",
      "## Campos personalizados",
      "",
      (($fields[0] // []) | map({key: .id, value: (.name // .id)}) | from_entries) as $names
      | ([.fields | to_entries[] | select(.key | startswith("customfield_")) | select(.value != null)
         | (.value | rich) as $v | select(($v | gsub("\\s"; "")) != "")
         | "- " + ($names[.key] // .key) + ": " + ($v | gsub("\n+"; " "))]
         | if length == 0 then "(nenhum preenchido)" else join("\n") end)
    ' --arg base "$JIRA_BASE_URL" --slurpfile fields "$RAW/jira-fields.json" "$RAW/ticket.json"

    if [ -s "$RAW/ticket-comments.json" ]; then
      printf '\n## Comentários\n\n'
      jq -r "$JIRA_ADF_JQ"'
        (.comments // [])
        | if length == 0 then "(nenhum)"
          else .[] | "- **" + (.author.displayName // "?") + "**: " + ((.body | rich) | gsub("\n+"; " "))
          end
      ' "$RAW/ticket-comments.json" 2>/dev/null || echo "(não foi possível ler os comentários)"
    fi
  } > "$RAW/ticket.md"
}
