# F5 — Detecção determinística de checklist
echo "-- F5: detecção de checklist --"

run_detect() { # $1=diretório do repo -- resto = args do script
  local d="$1"; shift
  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/detect-checklists.sh" "$@" >/dev/null 2>&1 )
}

checklists_file_for() { # $1=diretório do repo
  find "$1/temp/cr" -name checklists.json 2>/dev/null | head -1
}

f5_react_por_paths_e_pgvector_por_content() {
  local d="$WORK/f5-react-pgvector" base head out
  new_repo "$d"
  printf 'export const a = 1;\n' > "$d/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  mkdir -p "$d/src/pages" "$d/src/db"
  printf 'export function Search() { return null }\n' > "$d/src/pages/Search.tsx"
  printf '{"dependencies": {"react": "18.0.0"}}\n' > "$d/package.json"
  printf 'export const q = "SELECT * FROM docs ORDER BY embedding <=> $1 LIMIT 10";\n' > "$d/src/db/search.ts"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f5: carrega frontend-react" "true" "$(jq -e '.load | index("frontend-react") != null' "$out")"
  assert_eq "f5: carrega database-postgres-pgvector" "true" "$(jq -e '.load | index("database-postgres-pgvector") != null' "$out")"
  assert_eq "f5: motivo do react cita paths" "true" "$(jq -e '.why["frontend-react"] | startswith("paths:")' "$out")"
}

f5_tsx_sem_react_no_package_json() {
  local d="$WORK/f5-tsx-sem-dep" base head out
  new_repo "$d"
  printf '{"dependencies": {}}\n' > "$d/package.json"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf 'export function X() { return null }\n' > "$d/x.tsx"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f5: .tsx sem react no package.json ainda carrega (via paths)" "true" "$(jq -e '.load | index("frontend-react") != null' "$out")"
  assert_eq "f5: motivo não cita deps" "true" "$(jq -e '.why["frontend-react"] | startswith("deps:") | not' "$out")"
}

f5_nenhum_checklist() {
  local d="$WORK/f5-nenhum" base head out
  new_repo "$d"
  printf 'export const a = 1;\n' > "$d/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf 'export const a = 2;\n' > "$d/a.ts"
  git -C "$d" commit -qam mudanca
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f5: nenhum checklist carrega" "0" "$(jq '.load | length' "$out")"
}

f5_react_por_paths_e_pgvector_por_content
f5_tsx_sem_react_no_package_json
f5_nenhum_checklist
