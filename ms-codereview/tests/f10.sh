# F3 — Detecção v2: manifesto, variantes, always, monorepo
echo "-- F3: detecção v2 --"

run_detect_f10() { # $1=diretório $2=index.json -- resto = args do script
  local d="$1" index="$2"; shift 2
  ( cd "$d" && CR_BASE_DIR="$d" CR_CHECKLISTS_INDEX="$index" "$SKILL_DIR/scripts/detect-checklists.sh" "$@" >/dev/null 2>&1 )
}

checklists_file_for() { # $1=diretório do repo (redefinida aqui: f10 roda antes de f5 na ordem alfabética)
  find "$1/temp/cr" -name checklists.json 2>/dev/null | head -1
}

f10_monorepo_deps_manifesto_mais_proximo() {
  local d="$WORK/f10-monorepo" index base head out
  new_repo "$d"
  mkdir -p "$d/apps/web/src"
  printf '{}\n' > "$d/apps/web/package.json"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  printf '{"dependencies": {"react": "18.0.0"}}\n' > "$d/apps/web/package.json"
  printf 'export function X() { return null }\n' > "$d/apps/web/src/X.tsx"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  index="$WORK/f10-index-monorepo.json"
  cat > "$index" <<'JSON'
{ "frontend-react": { "paths": [], "deps": ["react"] } }
JSON

  run_detect_f10 "$d" "$index" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f10: monorepo carrega por deps do manifesto mais próximo" "true" \
    "$(jq -e '.load | index("frontend-react") != null' "$out")"
}

f10_always_carrega_e_nao_carrega_sem_arquivo() {
  local d="$WORK/f10-always" index base head out
  new_repo "$d"
  echo x > "$d/a.txt"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  echo y > "$d/a.txt"
  git -C "$d" commit -qam mudanca
  head="$(git -C "$d" rev-parse HEAD)"

  index="$WORK/f10-index-always.json"
  cat > "$index" <<'JSON'
{ "common": { "always": true } }
JSON

  run_detect_f10 "$d" "$index" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f10: always carrega" "true" "$(jq -e '.load | index("common") != null' "$out")"
  assert_eq "f10: why é always" "always" "$(jq -r '.why["common"]' "$out")"

  # diff vazio: mesmo commit nos dois lados -> nenhum arquivo tocado
  local d2="$WORK/f10-always-vazio"
  new_repo "$d2"
  echo x > "$d2/a.txt"
  git -C "$d2" add -A && git -C "$d2" commit -qm base
  local only="$(git -C "$d2" rev-parse HEAD)"
  run_detect_f10 "$d2" "$index" "$only...$only"
  local out2
  out2="$(checklists_file_for "$d2")"
  assert_eq "f10: always não carrega com diff vazio" "0" "$(jq '.load | length' "$out2")"
}

f10_variants_express_e_nest() {
  local d="$WORK/f10-variants" index base head out
  new_repo "$d"
  printf '{}\n' > "$d/package.json"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  printf '{"dependencies": {"express": "5.0.0", "@nestjs/core": "11.0.0"}}\n' > "$d/package.json"
  mkdir -p "$d/src"
  printf 'export const x = 1;\n' > "$d/src/app.controller.ts"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  index="$WORK/f10-index-variants.json"
  cat > "$index" <<'JSON'
{
  "backend-node": {
    "paths": ["**/*.controller.ts"],
    "variants": {
      "express": {"deps": ["express"]},
      "fastify": {"deps": ["fastify"]},
      "nest": {"deps": ["@nestjs/core"]}
    }
  }
}
JSON

  run_detect_f10 "$d" "$index" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f10: backend-node carrega" "true" "$(jq -e '.load | index("backend-node") != null' "$out")"
  assert_eq "f10: variants contém express" "true" "$(jq -e '.variants["backend-node"] | index("express") != null' "$out")"
  assert_eq "f10: variants contém nest" "true" "$(jq -e '.variants["backend-node"] | index("nest") != null' "$out")"
  assert_eq "f10: variants não contém fastify" "true" "$(jq -e '.variants["backend-node"] | index("fastify") == null' "$out")"
}

f10_manifest_pom_xml() {
  local d="$WORK/f10-manifest" index base head out
  new_repo "$d"
  printf '<project></project>\n' > "$d/pom.xml"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  printf '<project><dependency><artifactId>spring-boot-starter</artifactId></dependency></project>\n' > "$d/pom.xml"
  mkdir -p "$d/src/main/java/app"
  printf 'class App {}\n' > "$d/src/main/java/app/App.java"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  index="$WORK/f10-index-manifest.json"
  cat > "$index" <<'JSON'
{
  "java-spring": {
    "manifest": {"files": ["pom.xml", "build.gradle", "build.gradle.kts"], "pattern": "spring-boot", "ext": [".java", ".kt"]}
  }
}
JSON

  run_detect_f10 "$d" "$index" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f10: java-spring carrega por manifest" "true" "$(jq -e '.load | index("java-spring") != null' "$out")"
  assert_eq "f10: why cita manifest: pom.xml" "manifest: pom.xml" "$(jq -r '.why["java-spring"]' "$out")"
}

f10_variants_saida_vazia_e_objeto() {
  local d="$WORK/f10-sem-variants" index base head out
  new_repo "$d"
  echo x > "$d/a.txt"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  echo y > "$d/a.txt"
  git -C "$d" commit -qam mudanca
  head="$(git -C "$d" rev-parse HEAD)"

  index="$WORK/f10-index-sem-variants.json"
  cat > "$index" <<'JSON'
{ "algo": { "paths": ["**/nada"] } }
JSON

  run_detect_f10 "$d" "$index" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f10: variants é objeto vazio quando ninguém casa" "{}" "$(jq -c '.variants' "$out")"
}

f10_monorepo_deps_manifesto_mais_proximo
f10_always_carrega_e_nao_carrega_sem_arquivo
f10_variants_express_e_nest
f10_manifest_pom_xml
f10_variants_saida_vazia_e_objeto
