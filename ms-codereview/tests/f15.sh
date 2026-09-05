# F9 — Checklists transversais: common, ci-infra, llm-integration
echo "-- F9: checklists transversais --"

run_detect_f15() { # $1=diretório -- resto = args do script
  local d="$1"; shift
  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/detect-checklists.sh" "$@" >/dev/null 2>&1 )
}

checklists_file_for() { # redefinida aqui: f15 roda antes de f5 na ordem alfabética
  find "$1/temp/cr" -name checklists.json 2>/dev/null | head -1
}

f15_common_sempre_e_diff_vazio() {
  local d="$WORK/f15-common" base head out
  new_repo "$d"
  echo x > "$d/a.txt"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  echo y > "$d/a.txt"
  git -C "$d" commit -qam mudanca
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f15 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f15: common carrega sempre" "true" "$(jq -e '.load | index("common") != null' "$out")"
  assert_eq "f15: why é always" "always" "$(jq -r '.why["common"]' "$out")"

  local d2="$WORK/f15-common-vazio" only
  new_repo "$d2"
  echo x > "$d2/a.txt"
  git -C "$d2" add -A && git -C "$d2" commit -qm base
  only="$(git -C "$d2" rev-parse HEAD)"
  run_detect_f15 "$d2" "$only...$only"
  local out2
  out2="$(checklists_file_for "$d2")"
  assert_eq "f15: diff vazio -> load vazio" "0" "$(jq '.load | length' "$out2")"
}

f15_ci_infra_por_paths_e_security() {
  local d="$WORK/f15-ci-infra" base head out
  new_repo "$d"
  mkdir -p "$d/.github/workflows"
  printf 'name: x\n' > "$d/.github/workflows/x.yml"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf 'name: x\non: push\n' > "$d/.github/workflows/x.yml"
  git -C "$d" commit -qam feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f15 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f15: ci-infra carrega por paths" "true" "$(jq -e '.load | index("ci-infra") != null' "$out")"
  assert_eq "f15: security true" "true" "$(jq -r .security "$out")"
}

f15_llm_integration_deps() {
  local d="$WORK/f15-llm-deps" base head out
  new_repo "$d"
  printf '{"dependencies": {}}\n' > "$d/package.json"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf '{"dependencies": {"@anthropic-ai/sdk": "1.0.0"}}\n' > "$d/package.json"
  printf 'export const a = 1;\n' > "$d/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f15 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f15: llm-integration por deps" "true" "$(jq -e '.load | index("llm-integration") != null' "$out")"
  assert_eq "f15: why cita deps" "true" "$(jq -e '.why["llm-integration"] | startswith("deps:")' "$out")"
}

f15_llm_integration_manifest_java() {
  local d="$WORK/f15-llm-manifest" base head out
  new_repo "$d"
  printf '<project></project>\n' > "$d/pom.xml"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf '<project><dependency><artifactId>spring-ai-core</artifactId></dependency></project>\n' > "$d/pom.xml"
  mkdir -p "$d/src/main/java/app"
  printf 'class App {}\n' > "$d/src/main/java/app/App.java"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f15 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f15: llm-integration por manifest (spring-ai)" "true" "$(jq -e '.load | index("llm-integration") != null' "$out")"
  assert_eq "f15: why cita manifest" "true" "$(jq -e '.why["llm-integration"] | startswith("manifest:")' "$out")"
}

f15_common_sempre_e_diff_vazio
f15_ci_infra_por_paths_e_security
f15_llm_integration_deps
f15_llm_integration_manifest_java
