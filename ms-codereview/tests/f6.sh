# F6 — Passagem de segurança
echo "-- F6: passagem de segurança --"

f6_conteudo_query_interpolado() {
  local d="$WORK/f6-query" base head out
  new_repo "$d"
  printf 'export const a = 1;\n' > "$d/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  cat > "$d/a.ts" <<'EOF'
export function q(id) {
  return db.query(`SELECT * FROM x WHERE id = ${id}`);
}
EOF
  git -C "$d" commit -qam feature
  head="$(git -C "$d" rev-parse HEAD)"

  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/detect-checklists.sh" "$base...$head" >/dev/null 2>&1 )
  out="$(checklists_file_for "$d")"
  assert_eq "f6: query interpolado ativa security" "true" "$(jq -r .security "$out")"
  assert_eq "f6: security_why cita conteúdo" "true" "$(jq -e '.security_why | contains("query")' "$out")"
}

f6_caminho_sensivel() {
  local d="$WORK/f6-path" base head out
  new_repo "$d"
  printf 'export const a = 1;\n' > "$d/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  mkdir -p "$d/src/auth"
  printf 'export function login() {}\n' > "$d/src/auth/login.ts"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/detect-checklists.sh" "$base...$head" >/dev/null 2>&1 )
  out="$(checklists_file_for "$d")"
  assert_eq "f6: caminho src/auth ativa security" "true" "$(jq -r .security "$out")"
  assert_eq "f6: security_why cita caminho" "true" "$(jq -e '.security_why | contains("caminho")' "$out")"
}

f6_dependencia_nova() {
  local d="$WORK/f6-dep" base head out
  new_repo "$d"
  printf '{"dependencies": {}}\n' > "$d/package.json"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf '{"dependencies": {"left-pad": "1.0.0"}}\n' > "$d/package.json"
  git -C "$d" commit -qam feature
  head="$(git -C "$d" rev-parse HEAD)"

  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/detect-checklists.sh" "$base...$head" >/dev/null 2>&1 )
  out="$(checklists_file_for "$d")"
  assert_eq "f6: dependência nova ativa security" "true" "$(jq -r .security "$out")"
  assert_eq "f6: security_why cita a dependência" "true" "$(jq -e '.security_why | contains("left-pad")' "$out")"
}

f6_nada_suspeito_nao_ativa() {
  local d="$WORK/f6-limpo" base head out
  new_repo "$d"
  printf 'export const a = 1;\n' > "$d/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf 'export const a = 2;\n' > "$d/a.ts"
  git -C "$d" commit -qam feature
  head="$(git -C "$d" rev-parse HEAD)"

  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/detect-checklists.sh" "$base...$head" >/dev/null 2>&1 )
  out="$(checklists_file_for "$d")"
  assert_eq "f6: diff limpo não ativa security" "false" "$(jq -r .security "$out")"
}

f6_conteudo_query_interpolado
f6_caminho_sensivel
f6_dependencia_nova
f6_nada_suspeito_nao_ativa
