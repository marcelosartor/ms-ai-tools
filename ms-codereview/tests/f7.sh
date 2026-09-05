# F7 — PR mecânico é a própria spec
echo "-- F7: PR mecânico --"

run_fetch() { # $1=diretório do repo -- resto = args do script
  local d="$1"; shift
  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/fetch-context.sh" "$@" >/dev/null 2>&1 )
}

f7_deps() {
  local d="$WORK/f7-deps" base head status
  new_repo "$d"
  printf '{\n  "dependencies": { "a": "1.0.0" }\n}\n' > "$d/package.json"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf '{\n  "dependencies": { "a": "1.1.0" }\n}\n' > "$d/package.json"
  git -C "$d" commit -qam bump
  head="$(git -C "$d" rev-parse HEAD)"

  run_fetch "$d" "$base...$head"
  status="$(status_file_for "$d")"
  assert_eq "f7 deps: mechanical" "true" "$(jq -r .mechanical "$status")"
  assert_eq "f7 deps: kind" "deps" "$(jq -r .mechanical_kind "$status")"
}

f7_format() {
  local d="$WORK/f7-format" base head status
  new_repo "$d"
  printf 'function x() {\n  return 1;\n}\n' > "$d/a.js"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf 'function x() {\n    return 1;\n}\n' > "$d/a.js"
  git -C "$d" commit -qam reindent
  head="$(git -C "$d" rev-parse HEAD)"

  run_fetch "$d" "$base...$head"
  status="$(status_file_for "$d")"
  assert_eq "f7 format: mechanical" "true" "$(jq -r .mechanical "$status")"
  assert_eq "f7 format: kind" "format" "$(jq -r .mechanical_kind "$status")"
}

f7_rename() {
  local d="$WORK/f7-rename" base head status
  new_repo "$d"
  printf 'conteúdo estável\nlinha 2\nlinha 3\n' > "$d/old.txt"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  git -C "$d" mv old.txt new.txt
  git -C "$d" commit -qm rename
  head="$(git -C "$d" rev-parse HEAD)"

  run_fetch "$d" "$base...$head"
  status="$(status_file_for "$d")"
  assert_eq "f7 rename: mechanical" "true" "$(jq -r .mechanical "$status")"
  assert_eq "f7 rename: kind" "rename" "$(jq -r .mechanical_kind "$status")"
}

f7_docs() {
  local d="$WORK/f7-docs" base head status
  new_repo "$d"
  printf '# Título\n\ntexto\n' > "$d/README.md"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf '# Título\n\ntexto corrigido\n' > "$d/README.md"
  git -C "$d" commit -qam docs
  head="$(git -C "$d" rev-parse HEAD)"

  run_fetch "$d" "$base...$head"
  status="$(status_file_for "$d")"
  assert_eq "f7 docs: mechanical" "true" "$(jq -r .mechanical "$status")"
  assert_eq "f7 docs: kind" "docs" "$(jq -r .mechanical_kind "$status")"
}

f7_mixed_nao_mecanico() {
  local d="$WORK/f7-mixed" base head status
  new_repo "$d"
  printf '{\n  "dependencies": { "a": "1.0.0" }\n}\n' > "$d/package.json"
  printf 'export const a = 1;\n' > "$d/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf '{\n  "dependencies": { "a": "1.1.0" }\n}\n' > "$d/package.json"
  printf 'export const a = 2;\n' > "$d/a.ts"
  git -C "$d" commit -qam mixed
  head="$(git -C "$d" rev-parse HEAD)"

  run_fetch "$d" "$base...$head"
  status="$(status_file_for "$d")"
  assert_eq "f7 mixed (deps+código): não mecânico" "false" "$(jq -r .mechanical "$status")"
}

f7_deps_com_outros_campos_nao_mecanico() {
  local d="$WORK/f7-deps-plus" base head status
  new_repo "$d"
  printf '{\n  "scripts": { "test": "a" },\n  "dependencies": { "a": "1.0.0" }\n}\n' > "$d/package.json"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf '{\n  "scripts": { "test": "b" },\n  "dependencies": { "a": "1.1.0" }\n}\n' > "$d/package.json"
  git -C "$d" commit -qam mixed
  head="$(git -C "$d" rev-parse HEAD)"

  run_fetch "$d" "$base...$head"
  status="$(status_file_for "$d")"
  assert_eq "f7 package.json muda scripts além de deps: não mecânico" "false" "$(jq -r .mechanical "$status")"
}

f7_deps
f7_format
f7_rename
f7_docs
f7_mixed_nao_mecanico
f7_deps_com_outros_campos_nao_mecanico
