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
#   { "load": ["frontend-react"], "why": {"frontend-react": "paths: src/x.tsx"},
#     "variants": {"backend-node": ["nest", "fastify"]},
#     "security": true, "security_why": "caminho: src/auth/login.ts (**/auth/**)" }
#
# Semântica de cada entrada do índice: o checklist entra se qualquer "paths"
# casar com um arquivo do diff; ou qualquer "deps" estiver em
# dependencies/devDependencies do manifesto (package.json) MAIS PRÓXIMO de
# algum arquivo .ts/.tsx/.js/.jsx/.vue tocado (monorepo: cada arquivo usa o
# manifesto do seu próprio diretório, subindo até achar um); ou "manifest"
# ({files, pattern, ext}) casar — arquivo tocado com extensão em "ext" cujo
# manifesto mais próximo (primeiro nome de "files" encontrado) contém
# "pattern"; ou "always":true, que carrega sempre que o diff tiver ao menos
# um arquivo; ou qualquer "content" (regex ERE, case-insensitive) aparecer
# numa linha adicionada do diff. "variants" ({<nome>: {deps?/manifest?/
# paths?/content?}}) não muda se o checklist carrega — só diz quais seções
# dele aplicar, e entra na saída em "variants.<checklist>" quando casar.
# "paths_require_manifest": true faz "paths" só contar quando "manifest"
# também casar (ex.: "**/*.kts" sozinho não deve carregar um checklist
# Android num projeto Gradle Kotlin qualquer).
#
# "security" (independente dos checklists de stack) sai true quando: um
# caminho do diff casa um padrão sensível (auth/sessão/token/cripto/senha/
# upload/middleware/guard); uma linha adicionada bate um padrão de API
# perigosa (exec/eval, innerHTML, child_process, jwt/bcrypt/crypto, cors,
# etc.); ou o package.json ganhou uma dependência nova. "security_why" traz
# a primeira condição que casou.
#
# Glob sem find nem regex: "**/" na frente do padrão também casa sem
# nenhum prefixo de diretório (glob_match abaixo). O padrão de conteúdo de
# "security" é regex ERE de verdade (grep -E), assim como "content" acima.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_DIR="${CR_BASE_DIR:-$PWD}"
# Override só usado pelos testes, para exercitar chaves do índice (manifest,
# always, variants) sem depender de checklist real já existir.
INDEX="${CR_CHECKLISTS_INDEX:-$SKILL_DIR/checklists/index.json}"

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

# ---------- manifesto mais próximo (F3: monorepo) ----------
# Sobe diretórios a partir do arquivo até achar um dos nomes em $2, sem
# passar de BASE_DIR. Cache por (diretório, nomes) para não reler o mesmo
# manifesto várias vezes.
declare -A MANIFEST_CACHE
nearest_manifest() { # $1=arquivo (relativo a BASE_DIR) $2=nomes separados por espaço -> imprime caminho absoluto
  local file="$1" names="$2" dir cache_key cached name candidate
  dir="$(dirname "$file")"
  while :; do
    cache_key="$dir|$names"
    if [ -n "${MANIFEST_CACHE[$cache_key]+x}" ]; then
      cached="${MANIFEST_CACHE[$cache_key]}"
    else
      cached=""
      for name in $names; do
        if [ "$dir" = "." ]; then candidate="$BASE_DIR/$name"; else candidate="$BASE_DIR/$dir/$name"; fi
        if [ -f "$candidate" ]; then cached="$candidate"; break; fi
      done
      MANIFEST_CACHE["$cache_key"]="$cached"
    fi
    if [ -n "$cached" ]; then printf '%s\n' "$cached"; return 0; fi
    [ "$dir" != "." ] || return 1
    dir="$(dirname "$dir")"
  done
}

# ---------- leitura de uma chave do índice, do checklist ou de uma variante ----------
idx_get() { # $1=nome do checklist $2=variante ("" = nenhuma) $3=filtro jq relativo
  local name="$1" variant="$2" filter="$3"
  if [ -n "$variant" ]; then
    jq -r --arg n "$name" --arg v "$variant" ".[\$n].variants[\$v]$filter" "$INDEX"
  else
    jq -r --arg n "$name" ".[\$n]$filter" "$INDEX"
  fi
}

is_js_file() { # $1=caminho -> exit 0 se a extensão é JS/TS/Vue
  case "$1" in
    *.ts|*.tsx|*.js|*.jsx|*.vue) return 0 ;;
    *) return 1 ;;
  esac
}

match_paths() { # $1=nome $2=variante -> imprime o arquivo que casou; exit 1 se nenhum
  local name="$1" variant="$2" pattern f
  while IFS= read -r pattern; do
    [ -n "$pattern" ] || continue
    for f in "${FILES[@]}"; do
      if glob_match "$pattern" "$f"; then printf '%s\n' "$f"; return 0; fi
    done
  done < <(idx_get "$name" "$variant" '.paths // [] | .[]')
  return 1
}

match_deps() { # $1=nome $2=variante -> imprime a dependência que casou; exit 1 se nenhuma
  # deps é açúcar de manifest com files:["package.json"]: casa se QUALQUER
  # arquivo JS tocado tem a dependência no SEU manifesto mais próximo.
  local name="$1" variant="$2" dep f manifest
  while IFS= read -r dep; do
    [ -n "$dep" ] || continue
    for f in "${FILES[@]}"; do
      is_js_file "$f" || continue
      manifest="$(nearest_manifest "$f" "package.json" || true)"
      [ -n "$manifest" ] || continue
      if jq -e --arg d "$dep" '((.dependencies // {}) + (.devDependencies // {})) | has($d)' "$manifest" >/dev/null 2>&1; then
        printf '%s\n' "$dep"
        return 0
      fi
    done
  done < <(idx_get "$name" "$variant" '.deps // [] | .[]')
  return 1
}

match_manifest() { # $1=nome $2=variante -> imprime o basename do manifesto que casou; exit 1 se nenhum
  local name="$1" variant="$2" names_list pattern exts f ext manifest matched_ext
  names_list="$(idx_get "$name" "$variant" '.manifest.files // [] | join(" ")')"
  [ -n "$names_list" ] || return 1
  pattern="$(idx_get "$name" "$variant" '.manifest.pattern // empty')"
  exts="$(idx_get "$name" "$variant" '.manifest.ext // [] | join(" ")')"
  for f in "${FILES[@]}"; do
    matched_ext=false
    for ext in $exts; do
      case "$f" in *"$ext") matched_ext=true; break ;; esac
    done
    [ "$matched_ext" = true ] || continue
    manifest="$(nearest_manifest "$f" "$names_list" || true)"
    [ -n "$manifest" ] || continue
    if [ -z "$pattern" ] || grep -qiE -- "$pattern" "$manifest"; then
      printf '%s\n' "$(basename "$manifest")"
      return 0
    fi
  done
  return 1
}

match_content() { # $1=nome $2=variante -> imprime a regex que casou; exit 1 se nenhuma
  local name="$1" variant="$2" cpattern
  [ -n "$ADDED_LINES" ] || return 1
  while IFS= read -r cpattern; do
    [ -n "$cpattern" ] || continue
    if printf '%s\n' "$ADDED_LINES" | grep -qiE -- "$cpattern"; then
      printf '%s\n' "$cpattern"
      return 0
    fi
  done < <(idx_get "$name" "$variant" '.content // [] | .[]')
  return 1
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

  IS_ALWAYS="$(idx_get "$name" "" '.always // false')"
  if [ "$IS_ALWAYS" = "true" ] && [ ${#FILES[@]} -gt 0 ]; then
    REASON_PARTS+=("always")
  fi

  if [ ${#REASON_PARTS[@]} -eq 0 ]; then
    m="$(match_paths "$name" "" || true)"
    if [ -n "$m" ]; then
      REQUIRES_MANIFEST="$(idx_get "$name" "" '.paths_require_manifest // false')"
      if [ "$REQUIRES_MANIFEST" = "true" ]; then
        mf_guard="$(match_manifest "$name" "" || true)"
        [ -z "$mf_guard" ] || REASON_PARTS+=("paths: $m")
      else
        REASON_PARTS+=("paths: $m")
      fi
    fi
  fi
  if [ ${#REASON_PARTS[@]} -eq 0 ]; then
    d="$(match_deps "$name" "" || true)"
    [ -z "$d" ] || REASON_PARTS+=("deps: $d")
  fi
  if [ ${#REASON_PARTS[@]} -eq 0 ]; then
    mf="$(match_manifest "$name" "" || true)"
    [ -z "$mf" ] || REASON_PARTS+=("manifest: $mf")
  fi
  if [ ${#REASON_PARTS[@]} -eq 0 ]; then
    c="$(match_content "$name" "" || true)"
    [ -z "$c" ] || REASON_PARTS+=("content: $c")
  fi

  if [ ${#REASON_PARTS[@]} -gt 0 ]; then
    WHY_TEXT="$(IFS='; '; echo "${REASON_PARTS[*]}")"

    VARIANT_MATCHES=()
    while IFS= read -r vname; do
      [ -n "$vname" ] || continue
      if match_paths "$name" "$vname" >/dev/null \
         || match_deps "$name" "$vname" >/dev/null \
         || match_manifest "$name" "$vname" >/dev/null \
         || match_content "$name" "$vname" >/dev/null; then
        VARIANT_MATCHES+=("$vname")
      fi
    done < <(idx_get "$name" "" '.variants // {} | keys[]')

    VARIANTS_JSON="[]"
    if [ ${#VARIANT_MATCHES[@]} -gt 0 ]; then
      VARIANTS_JSON="$(printf '%s\n' "${VARIANT_MATCHES[@]}" | jq -R . | jq -s -c .)"
    fi

    jq -n -c --arg name "$name" --arg why "$WHY_TEXT" --argjson variants "$VARIANTS_JSON" \
      '{name:$name, why:$why, variants:$variants}' >> "$MATCHES_FILE"
  fi
done < <(jq -r 'keys[]' "$INDEX")

# ---------- passagem de segurança (F4/F6) ----------
SECURITY=false
SECURITY_WHY=""

SECURITY_PATH_PATTERNS='**/auth/** **/*auth.* **/*.guard.* **/*session* **/*jwt* **/*crypt* **/*password* **/*secret* **/upload* **/middleware/** **/*permission* **/*.policy.* **/*.strategy.* .github/workflows/** **/AndroidManifest.xml **/network_security_config.xml **/SecurityConfig*.java **/*Security*.kt'
for pattern in $SECURITY_PATH_PATTERNS; do
  for f in "${FILES[@]}"; do
    if glob_match "$pattern" "$f"; then
      SECURITY=true
      SECURITY_WHY="caminho: $f ($pattern)"
      break 2
    fi
  done
done

if [ "$SECURITY" = false ] && [ -n "$ADDED_LINES" ]; then
  SECURITY_CONTENT_RE='eval\(|dangerouslySetInnerHTML|\.raw\(|\.query\(.*\$\{|child_process|execSync|spawn(Sync)?\(|execFile|fs\.(read|write)|jwt|bcrypt|crypto\.|cors|helmet|multer|Access-Control|set-cookie|innerHTML|new Function|redirect\(|Location:|res\.cookie|Set-Cookie|sameSite|httpOnly|__proto__|prototype\[|yaml\.load|deserialize|ObjectInputStream|pull_request_target|addJavascriptInterface|setJavaScriptEnabled|exported="true"|permitAll|csrf\(\)\.disable|@PreAuthorize|rawQuery|WebSettings'
  MATCH_LINE="$(printf '%s\n' "$ADDED_LINES" | grep -iE "$SECURITY_CONTENT_RE" | head -1 || true)"
  if [ -n "$MATCH_LINE" ]; then
    SECURITY=true
    SECURITY_WHY="conteúdo suspeito: $(printf '%s' "$MATCH_LINE" | cut -c1-120)"
  fi
fi

# dependência nova em qualquer manifesto tocado (npm, Maven, Gradle) — a
# coordenada não existe na versão base do próprio arquivo.
security_dep_keys() { # $1=tipo do manifesto -- lê conteúdo do stdin, imprime uma coordenada por linha
  case "$1" in
    package.json)
      jq -r '((.dependencies // {}) + (.devDependencies // {}) + (.peerDependencies // {})) | keys[]' 2>/dev/null ;;
    pom.xml)
      grep -oE '<artifactId>[^<]+</artifactId>' | sed -E 's#</?artifactId>##g' ;;
    build.gradle|build.gradle.kts)
      grep -oE "[\"'][A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+:[A-Za-z0-9_.+-]+[\"']" | tr -d "\"'" ;;
    libs.versions.toml)
      grep -oE '^[A-Za-z0-9_-]+[[:space:]]*=' | sed -E 's/[[:space:]]*=$//' ;;
  esac
}

if [ "$SECURITY" = false ] && [ -n "$BASE_SHA" ] && [ -n "$HEAD_SHA" ]; then
  for f in "${FILES[@]}"; do
    MTYPE=""
    case "$(basename "$f")" in
      package.json) MTYPE="package.json" ;;
      pom.xml) MTYPE="pom.xml" ;;
      build.gradle) MTYPE="build.gradle" ;;
      build.gradle.kts) MTYPE="build.gradle.kts" ;;
      libs.versions.toml) MTYPE="libs.versions.toml" ;;
      *) continue ;;
    esac
    BASE_CONTENT="$(git -C "$BASE_DIR" show "$BASE_SHA:$f" 2>/dev/null || true)"
    HEAD_CONTENT="$(git -C "$BASE_DIR" show "$HEAD_SHA:$f" 2>/dev/null || true)"
    BASE_KEYS="$(printf '%s' "$BASE_CONTENT" | security_dep_keys "$MTYPE" | sort -u || true)"
    HEAD_KEYS="$(printf '%s' "$HEAD_CONTENT" | security_dep_keys "$MTYPE" | sort -u || true)"
    NEW_DEP="$(comm -13 <(printf '%s\n' "$BASE_KEYS") <(printf '%s\n' "$HEAD_KEYS") | grep -v '^$' | head -1 || true)"
    if [ -n "$NEW_DEP" ]; then
      SECURITY=true
      SECURITY_WHY="dependência nova: $NEW_DEP"
      break
    fi
  done
fi

jq -s \
  --argjson security "$SECURITY" \
  --arg security_why "$SECURITY_WHY" \
  '{load: map(.name), why: (map({(.name): .why}) | add // {}),
    variants: (map(select((.variants|length)>0) | {(.name): .variants}) | add // {}),
    security: $security,
    security_why: (if $security_why=="" then null else $security_why end)}' \
  "$MATCHES_FILE" > "$OUT"

echo "checklists em: $OUT"
jq -r '"  load=\(if (.load|length)==0 then "-" else (.load|join(", ")) end)  security=\(.security)"' "$OUT"
