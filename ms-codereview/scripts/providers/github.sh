#!/usr/bin/env bash
#
# Provider GitHub Issues para fetch-context.sh. Diferente dos demais: não
# tem variável de credencial própria — usa o `gh` já autenticado que busca
# o PR. Entra em PROVIDERS depois de clickup e jira, para não roubar id de
# quem já tem tracker configurado; só é candidato automático quando `gh`
# está autenticado.
#
# Contrato (compartilhado por todos os providers):
#   <p>_extract <strong|weak>  lê texto no stdin e imprime o id do ticket
#   <p>_id_matches <id>        0 se o id tem o formato deste tracker
#   <p>_credentials            0 se dá para autenticar; senão define REASON e devolve 1
#   <p>_fetch <id>             grava ticket.json/.md em $RAW; senão define REASON e devolve 1

GITHUB_HAS_ISSUES_CACHE=""
github_repo_has_issues() {
  if [ -z "$GITHUB_HAS_ISSUES_CACHE" ]; then
    if command -v gh >/dev/null 2>&1; then
      GITHUB_HAS_ISSUES_CACHE="$(cd "$BASE_DIR" && gh repo view --json hasIssuesEnabled -q .hasIssuesEnabled 2>/dev/null || echo false)"
    else
      GITHUB_HAS_ISSUES_CACHE="false"
    fi
    [ -n "$GITHUB_HAS_ISSUES_CACHE" ] || GITHUB_HAS_ISSUES_CACHE="false"
  fi
  [ "$GITHUB_HAS_ISSUES_CACHE" = "true" ]
}

github_extract() {
  local text
  text="$(cat)"
  case "$1" in
    strong)
      # closingIssuesReferences (PR "Closes #123") vence; senão #123,
      # owner/repo#123 ou "fixes #123" no corpo do PR.
      local from_pr=""
      if [ -f "$RAW/pr.json" ]; then
        from_pr="$(jq -r '(.closingIssuesReferences // [])[0].number // empty' "$RAW/pr.json" 2>/dev/null)"
      fi
      if [ -n "$from_pr" ]; then
        printf '%s\n' "$from_pr"
        return 0
      fi
      printf '%s\n' "$text" \
        | grep -oiE '[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+|#[0-9]+' \
        | head -1 \
        | sed 's/^#//'
      ;;
    weak)
      # slug de branch tipo 123-corrige-refund, só se o repo tiver issues.
      github_repo_has_issues || return 0
      printf '%s\n' "$text" | grep -oE '^[0-9]+-' | head -1 | tr -d '-'
      ;;
  esac
}

github_id_matches() {
  printf '%s' "$1" | grep -qE '^[0-9]+$|^[^/[:space:]]+/[^/[:space:]]+#[0-9]+$'
}

github_credentials() {
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    AUTH_HEADER=""
    return 0
  fi
  REASON="gh não está autenticado (gh auth login) — provider github não usa variável de .env"
  return 1
}

github_fetch() {
  local id="$1"
  local issue_num="$id"
  local repo_arg=()
  case "$id" in
    */*'#'*)
      repo_arg=(--repo "${id%%#*}")
      issue_num="${id##*#}"
      ;;
  esac
  if ! (cd "$BASE_DIR" && gh issue view "$issue_num" "${repo_arg[@]}" \
        --json number,title,body,state,labels,comments,url) > "$RAW/ticket.json" 2>"$RAW/gh-issue-error.log"; then
    REASON="gh issue view falhou para #$issue_num: $(tail -c 200 "$RAW/gh-issue-error.log" | tr '\n' ' ')"
    return 1
  fi
  rm -f "$RAW/gh-issue-error.log"

  {
    jq -r '
      "# " + (.title // "(sem título)"),
      "",
      "- tracker: GitHub Issues",
      "- id: #" + ((.number // 0) | tostring),
      "- url: " + (.url // "-"),
      "- status: " + (.state // "-"),
      "- labels: " + ((.labels // []) | map(.name) | join(", ")),
      "",
      "## Descrição",
      "",
      (.body // "(vazia)"),
      ""
    ' "$RAW/ticket.json"
    if jq -e '(.comments // []) | length > 0' "$RAW/ticket.json" >/dev/null 2>&1; then
      printf '## Comentários\n\n'
      jq -r '.comments[] | "- **" + (.author.login // "?") + "**: " + ((.body // "") | gsub("\n"; " "))' "$RAW/ticket.json"
    fi
  } > "$RAW/ticket.md"
}
