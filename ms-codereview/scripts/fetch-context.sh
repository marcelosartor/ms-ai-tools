#!/usr/bin/env bash
#
# Coleta determinística de contexto para a skill ms-codereview.
#
#   scripts/fetch-context.sh <pr>                      # PR do GitHub + ticket do tracker
#   scripts/fetch-context.sh <pr> --task ABC-123       # força o id do ticket
#   scripts/fetch-context.sh <pr> --provider jira      # força o tracker
#   scripts/fetch-context.sh <pr> --spec-file docs/specs/checkout.md  # sem tracker: usa este arquivo como contexto
#   scripts/fetch-context.sh main...HEAD               # sem PR; só tenta o ticket pela branch
#
# Grava tudo em <base>/temp/cr/<pr>/raw/ (base = $CR_BASE_DIR ou o diretório atual).
# O ticket sai sempre nos mesmos arquivos, seja qual for a fonte (tracker ou
# --spec-file): raw/ticket.md, raw/ticket.json, raw/ticket-comments.json.
# Não imprime credencial em nenhuma hipótese.
#
# --spec-file só roda quando passado explicitamente: sem ele, este passo nem
# existe. Não pode ser combinado com --task/--provider. Providers de tracker
# sem credencial configurada nem são tentados no modo automático.
#
# Códigos de saída:
#   0  contexto completo (PR e/ou ticket obtidos)
#   2  erro de uso
#   3  não foi possível descobrir o id do ticket
#   4  credencial do tracker ausente (crie o .env na raiz da skill), ou
#      nenhum tracker configurado
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
  sed -n '3,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

TARGET=""
TASK_OVERRIDE=""
PROVIDER_OVERRIDE=""
SPEC_FILE_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --task) TASK_OVERRIDE="${2:-}"; shift 2 ;;
    --provider) PROVIDER_OVERRIDE="${2:-}"; shift 2 ;;
    --spec-file) SPEC_FILE_OVERRIDE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "opção desconhecida: $1" >&2; usage >&2; exit 2 ;;
    *) TARGET="$1"; shift ;;
  esac
done

[ -n "$TARGET" ] || { echo "informe o número do PR ou o range de refs" >&2; exit 2; }

if [ -n "$SPEC_FILE_OVERRIDE" ] && { [ -n "$TASK_OVERRIDE" ] || [ -n "$PROVIDER_OVERRIDE" ]; }; then
  echo "--spec-file não pode ser combinado com --task/--provider" >&2
  exit 2
fi

if [ -n "$SPEC_FILE_OVERRIDE" ] && [ ! -r "$SPEC_FILE_OVERRIDE" ]; then
  echo "arquivo de --spec-file não encontrado ou sem permissão de leitura: $SPEC_FILE_OVERRIDE" >&2
  exit 2
fi

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
MECHANICAL=false
MECHANICAL_KIND=""
DIFF_BASE_SHA=""
DIFF_HEAD_SHA=""

# ---------- revisão anterior (F3: re-review incremental) ----------
# Report de rodada anterior vive em temp/cr/<alvo>/ (irmão de raw/, não
# dentro), nomeado report-<sha7>.md. Calculado cedo — não depende de PR
# nem de ticket — para entrar em toda escrita de status.
REPORT_DIR="$BASE_DIR/temp/cr/$SLUG"
PREVIOUS_REPORT=""
PREVIOUS_SHA=""
for rf in "$REPORT_DIR"/report-*.md; do
  [ -e "$rf" ] || continue
  if [ -z "$PREVIOUS_REPORT" ] || [ "$rf" -nt "$PREVIOUS_REPORT" ]; then
    PREVIOUS_REPORT="$rf"
  fi
done
if [ -n "$PREVIOUS_REPORT" ]; then
  PREVIOUS_SHA="$(basename "$PREVIOUS_REPORT" .md)"
  PREVIOUS_SHA="${PREVIOUS_SHA#report-}"
fi

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
    --argjson mechanical "$MECHANICAL" \
    --arg mechanical_kind "$MECHANICAL_KIND" \
    --arg base_sha "$DIFF_BASE_SHA" \
    --arg head_sha "$DIFF_HEAD_SHA" \
    --arg previous_report "$PREVIOUS_REPORT" \
    --arg previous_sha "$PREVIOUS_SHA" \
    --argjson previous_is_ancestor "$PREVIOUS_IS_ANCESTOR" \
    --arg previous_base_sha "$PREVIOUS_BASE_SHA" \
    --argjson base_moved "$BASE_MOVED" \
    '{target:$target, raw_dir:$raw, pr_fetched:$pr_ok,
      provider:(if $provider=="" then null else $provider end),
      task_id:(if $task_id=="" then null else $task_id end),
      task_fetched:$task_ok,
      mechanical:$mechanical,
      mechanical_kind:(if $mechanical_kind=="" then null else $mechanical_kind end),
      base_sha:(if $base_sha=="" then null else $base_sha end),
      head_sha:(if $head_sha=="" then null else $head_sha end),
      previous_report:(if $previous_report=="" then null else $previous_report end),
      previous_sha:(if $previous_sha=="" then null else $previous_sha end),
      previous_is_ancestor:$previous_is_ancestor,
      previous_base_sha:(if $previous_base_sha=="" then null else $previous_base_sha end),
      base_moved:$base_moved,
      reason:(if $reason=="" then null else $reason end), generated_at:$generated_at}' \
    > "$STATUS_FILE"
  echo "contexto em: $RAW"
  jq -r '"  pr_fetched=\(.pr_fetched)  provider=\(.provider // "-")  task_id=\(.task_id // "-")  task_fetched=\(.task_fetched)  mechanical=\(.mechanical)\(if .mechanical_kind then " ("+.mechanical_kind+")" else "" end)  previous_sha=\(.previous_sha // "-")  reason=\(.reason // "-")"' "$STATUS_FILE"
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
# shellcheck disable=SC1091
. "$SKILL_DIR/scripts/providers/github.sh"

# github por último: não deve roubar id de quem já tem clickup/jira
# configurado — só entra como candidato automático se `gh` estiver
# autenticado (github_credentials).
PROVIDERS="clickup jira github"

# ---------- 2. PR do GitHub ----------
if printf '%s' "$TARGET" | grep -qE '^[0-9]+$' && command -v gh >/dev/null 2>&1; then
  if gh pr view "$TARGET" \
       --json number,title,url,state,isDraft,author,baseRefName,headRefName,baseRefOid,headRefOid,body,additions,deletions,changedFiles,files,labels,createdAt,mergedAt,closedAt,closingIssuesReferences \
       > "$RAW/pr.json" 2>"$RAW/gh-error.log"; then
    jq -r '.body // ""' "$RAW/pr.json" > "$RAW/pr-body.md"
    jq -r '.files[] | "\(.additions)\t\(.deletions)\t\(.path)"' "$RAW/pr.json" > "$RAW/pr-files.tsv" 2>/dev/null || true
    gh pr view "$TARGET" --comments > "$RAW/pr-comments.md" 2>/dev/null || true
    rm -f "$RAW/gh-error.log"
    PR_OK=true

    # ---------- 2.1 CI (F5) ----------
    if gh pr checks "$TARGET" --json name,state,link > "$RAW/ci.json" 2>/dev/null; then
      {
        printf '# CI\n\n'
        if jq -e 'length == 0' "$RAW/ci.json" >/dev/null 2>&1; then
          printf '(nenhum check configurado)\n'
        else
          jq -r '.[] | "- \(.state): \(.name) — \(.link // "-")"' "$RAW/ci.json"
        fi
      } > "$RAW/ci.md"
    else
      printf '# CI\n\n(não foi possível consultar `gh pr checks`)\n' > "$RAW/ci.md"
      printf '[]\n' > "$RAW/ci.json"
    fi
  fi
fi

# ---------- 2.5 detecção de checklists (independe de ticket/mecânico) ----------
"$SKILL_DIR/scripts/detect-checklists.sh" "$TARGET" >/dev/null || echo "aviso: detecção de checklists falhou" >&2

# ---------- 2.6 classificação de PR mecânico ----------
# Bump de dependência, formatação, rename e doc não têm ticket e não
# precisam: a própria mudança é a spec. base/head do diff vêm do PR (quando
# há) ou do range passado como alvo (ex.: main...HEAD); alvo que não é um
# range e não resolve como commit único deixa a classificação vazia.
split_range() { # $1=alvo -> "base<TAB>head", vazio se não é um range
  case "$1" in
    *...*) printf '%s\t%s\n' "${1%%...*}" "${1##*...}" ;;
    *..*)  printf '%s\t%s\n' "${1%%..*}" "${1##*..}" ;;
  esac
}

if [ "$PR_OK" = true ]; then
  DIFF_BASE_SHA="$(jq -r '.baseRefOid // empty' "$RAW/pr.json")"
  DIFF_HEAD_SHA="$(jq -r '.headRefOid // empty' "$RAW/pr.json")"
else
  RANGE_PAIR="$(split_range "$TARGET")"
  if [ -n "$RANGE_PAIR" ]; then
    RANGE_BASE="${RANGE_PAIR%%$'\t'*}"
    RANGE_HEAD="${RANGE_PAIR#*$'\t'}"
    DIFF_BASE_SHA="$(git -C "$BASE_DIR" rev-parse "$RANGE_BASE" 2>/dev/null || true)"
    DIFF_HEAD_SHA="$(git -C "$BASE_DIR" rev-parse "$RANGE_HEAD" 2>/dev/null || true)"
  else
    DIFF_HEAD_SHA="$(git -C "$BASE_DIR" rev-parse "$TARGET" 2>/dev/null || true)"
  fi
fi

# ---------- previous_is_ancestor / previous_base_sha / base_moved (F1) ----------
# previous_is_ancestor diz se o sha da rodada anterior ainda é ancestral do
# head atual: false ou null indica rebase/force-push, e nesse caso o delta
# previous_sha..head_sha incluiria commits que não são deste PR — a skill não
# entra em modo incremental. null é "não dá para saber" (sem previous_sha, ou
# o commit não existe mais no repo, ex.: force-push que descartou o commit).
PREVIOUS_IS_ANCESTOR="null"
if [ -n "$PREVIOUS_SHA" ] && [ -n "$DIFF_HEAD_SHA" ]; then
  if git -C "$BASE_DIR" cat-file -e "${PREVIOUS_SHA}^{commit}" 2>/dev/null; then
    if git -C "$BASE_DIR" merge-base --is-ancestor "$PREVIOUS_SHA" "$DIFF_HEAD_SHA" 2>/dev/null; then
      PREVIOUS_IS_ANCESTOR="true"
    else
      PREVIOUS_IS_ANCESTOR="false"
    fi
  fi
fi

# previous_base_sha vem do bloco <!-- meta --> gravado pela rodada anterior
# (relatórios antigos, de antes do F1, não têm o bloco: fica vazio). Difere
# do base_sha atual quando a branch base recebeu merge/rebase entre rodadas.
PREVIOUS_BASE_SHA=""
if [ -n "$PREVIOUS_REPORT" ] && [ -f "$PREVIOUS_REPORT" ]; then
  PREVIOUS_BASE_SHA="$(sed -n '/<!-- meta/,/-->/{/^base_sha:/{s/^base_sha: *//p}}' "$PREVIOUS_REPORT" | head -1)"
fi
BASE_MOVED="null"
if [ -n "$PREVIOUS_BASE_SHA" ] && [ -n "$DIFF_BASE_SHA" ]; then
  if [ "$PREVIOUS_BASE_SHA" != "$DIFF_BASE_SHA" ]; then
    BASE_MOVED="true"
  else
    BASE_MOVED="false"
  fi
fi

if [ -n "$DIFF_BASE_SHA" ] && [ -n "$DIFF_HEAD_SHA" ]; then
  DIFF_RANGE="$DIFF_BASE_SHA...$DIFF_HEAD_SHA"
  NAME_STATUS="$(git -C "$BASE_DIR" diff --name-status -M90% "$DIFF_RANGE" 2>/dev/null || true)"

  if [ -n "$NAME_STATUS" ]; then
    DIFF_PATHS=()
    while IFS= read -r diff_path; do
      [ -n "$diff_path" ] && DIFF_PATHS+=("$diff_path")
    done < <(printf '%s\n' "$NAME_STATUS" | awk -F'\t' '{print $NF}')

    # deps: só arquivo de dependência, e no package.json só mudou valor
    # dentro de dependencies/devDependencies/peerDependencies (comparação
    # estrutural via jq, não por linha — sobrevive a reformatação).
    IS_DEPS=true
    for f in "${DIFF_PATHS[@]}"; do
      case "$(basename "$f")" in
        package.json|package-lock.json|pnpm-lock.yaml|yarn.lock) ;;
        *) IS_DEPS=false; break ;;
      esac
    done
    if [ "$IS_DEPS" = true ]; then
      for f in "${DIFF_PATHS[@]}"; do
        [ "$(basename "$f")" = "package.json" ] || continue
        BASE_PKG_JSON="$(git -C "$BASE_DIR" show "$DIFF_BASE_SHA:$f" 2>/dev/null || echo '{}')"
        HEAD_PKG_JSON="$(git -C "$BASE_DIR" show "$DIFF_HEAD_SHA:$f" 2>/dev/null || echo '{}')"
        if ! jq -n -e \
             --argjson a "$BASE_PKG_JSON" --argjson b "$HEAD_PKG_JSON" \
             '($a | del(.dependencies,.devDependencies,.peerDependencies)) ==
              ($b | del(.dependencies,.devDependencies,.peerDependencies))' \
             >/dev/null 2>&1; then
          IS_DEPS=false; break
        fi
      done
    fi

    if [ "$IS_DEPS" = true ]; then
      MECHANICAL=true; MECHANICAL_KIND="deps"
    elif [ -z "$(git -C "$BASE_DIR" diff -w --numstat "$DIFF_RANGE" 2>/dev/null)" ]; then
      MECHANICAL=true; MECHANICAL_KIND="format"
    elif ! printf '%s\n' "$NAME_STATUS" | awk -F'\t' '{print $1}' | grep -qvE '^R'; then
      MECHANICAL=true; MECHANICAL_KIND="rename"
    else
      IS_DOCS=true
      for f in "${DIFF_PATHS[@]}"; do
        case "$f" in
          *.md|*.mdx|*.txt|docs/*) ;;
          *) IS_DOCS=false; break ;;
        esac
      done
      if [ "$IS_DOCS" = true ]; then MECHANICAL=true; MECHANICAL_KIND="docs"; fi
    fi

    # ---------- 2.7 advisories (F4) ----------
    # Para cada dependência nova ou com versão alterada em manifesto
    # tocado, consulta o GitHub Advisory Database. Nunca bloqueia a
    # coleta: sem gh, ou com erro da API, grava o motivo e segue.
    ADVISORIES_FILE="$RAW/advisories.md"
    npm_changed_deps() { # $1=conteúdo base $2=conteúdo head -> "pacote<TAB>versão" por linha, só novo/alterado
      jq -r -n \
        --argjson a "$(printf '%s' "${1:-\{\}}" | jq -c '.' 2>/dev/null || echo '{}')" \
        --argjson b "$(printf '%s' "${2:-\{\}}" | jq -c '.' 2>/dev/null || echo '{}')" \
        '(($a.dependencies // {}) + ($a.devDependencies // {})) as $before
         | (($b.dependencies // {}) + ($b.devDependencies // {})) as $after
         | ($after | to_entries[] | select(($before[.key] // null) != .value) | "\(.key)\t\(.value)")' 2>/dev/null || true
    }
    maven_new_coords() { # $1=conteúdo base $2=conteúdo head -> "grupo:artefato" por linha, só o que é novo
      comm -13 \
        <(printf '%s' "$1" | grep -oE '<artifactId>[^<]+</artifactId>' | sed -E 's#</?artifactId>##g' | sort -u) \
        <(printf '%s' "$2" | grep -oE '<artifactId>[^<]+</artifactId>' | sed -E 's#</?artifactId>##g' | sort -u) 2>/dev/null || true
    }
    if command -v gh >/dev/null 2>&1 && [ "${CR_NO_GH:-}" != "1" ]; then
      ADV_COUNT=0
      for f in "${DIFF_PATHS[@]}"; do
        [ "$ADV_COUNT" -lt 30 ] || break
        ECO=""
        case "$(basename "$f")" in
          package.json) ECO="npm" ;;
          pom.xml|build.gradle|build.gradle.kts) ECO="maven" ;;
        esac
        [ -n "$ECO" ] || continue
        BASE_MF="$(git -C "$BASE_DIR" show "$DIFF_BASE_SHA:$f" 2>/dev/null || true)"
        HEAD_MF="$(git -C "$BASE_DIR" show "$DIFF_HEAD_SHA:$f" 2>/dev/null || true)"
        [ -n "$HEAD_MF" ] || continue
        if [ "$ECO" = "npm" ]; then
          while IFS=$'\t' read -r pkg ver; do
            [ -n "$pkg" ] || continue
            ADV_COUNT=$((ADV_COUNT + 1)); [ "$ADV_COUNT" -le 30 ] || break
            ADV_JSON="$(gh api "advisories?ecosystem=npm&affects=$pkg@$ver" --paginate 2>/dev/null || true)"
            [ -n "$ADV_JSON" ] || continue
            printf '%s' "$ADV_JSON" | jq -r --arg pkg "$pkg" --arg ver "$ver" \
              '.[]? | "- **\(.ghsa_id)** (\(.severity)) — \($pkg)@\($ver): \(.vulnerabilities[0].vulnerable_version_range // "?") — corrigido em \(.vulnerabilities[0].first_patched_version // "?")"' \
              2>/dev/null >> "$ADVISORIES_FILE" || true
          done < <(npm_changed_deps "$BASE_MF" "$HEAD_MF")
        else
          while IFS= read -r artifact; do
            [ -n "$artifact" ] || continue
            ADV_COUNT=$((ADV_COUNT + 1)); [ "$ADV_COUNT" -le 30 ] || break
            ADV_JSON="$(gh api "advisories?ecosystem=maven&affects=$artifact" --paginate 2>/dev/null || true)"
            [ -n "$ADV_JSON" ] || continue
            printf '%s' "$ADV_JSON" | jq -r --arg a "$artifact" \
              '.[]? | "- **\(.ghsa_id)** (\(.severity)) — \($a): \(.vulnerabilities[0].vulnerable_version_range // "?") — corrigido em \(.vulnerabilities[0].first_patched_version // "?")"' \
              2>/dev/null >> "$ADVISORIES_FILE" || true
          done < <(maven_new_coords "$BASE_MF" "$HEAD_MF")
        fi
      done
      [ -s "$ADVISORIES_FILE" ] || printf 'nenhum advisory encontrado\n' > "$ADVISORIES_FILE"
    else
      printf 'não consultado (gh ausente no PATH)\n' > "$ADVISORIES_FILE"
    fi
  fi
fi
[ -f "$RAW/advisories.md" ] || printf 'não consultado (sem range de diff)\n' > "$RAW/advisories.md"

if [ "$MECHANICAL" = true ]; then
  PROVIDER=""
  TASK_ID=""
  REASON="PR mecânico ($MECHANICAL_KIND): a própria mudança é a spec"
  write_status
  exit 0
fi

# ---------- 3. contexto do "ticket": --spec-file, ou tracker ----------

# Fonte explícita: só roda quando --spec-file é passado. Sem tracker, sem
# autodetecção de id — o arquivo indicado é o contexto, ponto final.
if [ -n "$SPEC_FILE_OVERRIDE" ]; then
  PROVIDER="local"
  TASK_ID="$SPEC_FILE_OVERRIDE"
  {
    printf '# Contexto local\n\n'
    printf -- '- tracker: arquivo local\n'
    printf -- '- caminho: %s\n\n' "$SPEC_FILE_OVERRIDE"
    printf '## Conteúdo\n\n'
    cat "$SPEC_FILE_OVERRIDE"
  } > "$RAW/ticket.md"
  TASK_OK=true
  write_status
  exit 0
fi

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

# Sem credencial, nem tenta: no modo automático, restringe a busca do id aos
# providers com credencial configurada. Um --provider explícito é pedido
# direto do usuário e é sempre tentado, mesmo sem credencial — aí o erro
# específico sai no passo 4.
if [ "$PROVIDER" = "auto" ]; then
  CANDIDATES=""
  for p in $PROVIDERS; do
    if "${p}_credentials" >/dev/null 2>&1; then
      CANDIDATES="$CANDIDATES $p"
    fi
  done
  CANDIDATES="${CANDIDATES# }"
  REASON=""

  if [ -z "$CANDIDATES" ]; then
    PROVIDER=""
    REASON="nenhum tracker configurado (nenhuma credencial em $CRED_FILE); configure um provider ou force com --provider <$(printf '%s' "$PROVIDERS" | tr ' ' '|')>"
    write_status
    exit 4
  fi
else
  CANDIDATES="$PROVIDER"
fi

if [ -n "$TASK_OVERRIDE" ]; then
  TASK_ID="$TASK_OVERRIDE"
  if [ "$PROVIDER" = "auto" ]; then
    for p in $CANDIDATES; do
      if "${p}_id_matches" "$TASK_ID"; then PROVIDER="$p"; break; fi
    done
  fi
else
  TEXT="$(context_text)"
  # Duas passagens: sinal forte (url/badge do tracker) antes do fraco (chave
  # solta no texto, slug de branch), para não confundir os formatos.
  for pass in strong weak; do
    [ -z "$TASK_ID" ] || break
    for p in $CANDIDATES; do
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
  REASON="id '$TASK_ID' não corresponde ao formato de nenhum tracker com credencial configurada; rode de novo com --provider <$(printf '%s' "$PROVIDERS" | tr ' ' '|')>"
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
