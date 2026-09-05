# F2 — Rodar o que for barato
echo "-- F2: typecheck e testes tocados --"

f2_teste_falha_vira_exit_1() {
  local d="$WORK/f2-fail" base head rc raw
  new_repo "$d"
  mkdir -p "$d/node_modules/.bin" "$d/src"
  printf '{"name":"x"}\n' > "$d/package.json"
  printf 'export const a = 1;\n' > "$d/src/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  printf "test('a', () => {})\n" > "$d/src/a.spec.ts"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  cat > "$d/node_modules/.bin/vitest" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    *a.spec.ts) exit 1 ;;
  esac
done
exit 0
EOF
  chmod +x "$d/node_modules/.bin/vitest"

  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/fetch-context.sh" "$base...$head" >/dev/null 2>&1 )
  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/run-checks.sh" "$base...$head" >/dev/null 2>&1 )
  rc=$?
  raw="$(find "$d/temp/cr" -name checks.json | head -1)"

  assert_eq "f2: exit 1 quando teste falha" "1" "$rc"
  assert_eq "f2: test.status falhou" "falhou" "$(jq -r .test.status "$raw")"
  assert_eq "f2: deps reaproveitado (ok)" "ok" "$(jq -r .deps.status "$raw")"
}

f2_sem_node_modules_nao_roda() {
  local d="$WORK/f2-sem-nm" base head rc raw
  new_repo "$d"
  printf '{"name":"x"}\n' > "$d/package.json"
  printf 'export const a = 1;\n' > "$d/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf "test('a', () => {})\n" > "$d/a.spec.ts"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/fetch-context.sh" "$base...$head" >/dev/null 2>&1 )
  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/run-checks.sh" "$base...$head" >/dev/null 2>&1 )
  rc=$?
  raw="$(find "$d/temp/cr" -name checks.json | head -1)"

  assert_eq "f2: sem node_modules -> exit 0" "0" "$rc"
  assert_eq "f2: sem node_modules -> deps indisponível" "indisponível" "$(jq -r .deps.status "$raw")"
  assert_eq "f2: sem node_modules -> test não rodou" "não rodou" "$(jq -r .test.status "$raw")"
}

f2_pr_altera_dependencias_nao_instala() {
  local d="$WORK/f2-deps-pr" base head raw
  new_repo "$d"
  mkdir -p "$d/node_modules/.bin"
  printf '{"name":"x","dependencies":{}}\n' > "$d/package.json"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf '{"name":"x","dependencies":{"a":"1.0.0"}}\n' > "$d/package.json"
  git -C "$d" commit -qam bump
  head="$(git -C "$d" rev-parse HEAD)"

  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/fetch-context.sh" "$base...$head" >/dev/null 2>&1 )
  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/run-checks.sh" "$base...$head" >/dev/null 2>&1 )
  raw="$(find "$d/temp/cr" -name checks.json | head -1)"

  assert_eq "f2: PR altera deps -> não reaproveita node_modules" "indisponível" "$(jq -r .deps.status "$raw")"
  assert_eq "f2: motivo cita dependências" "true" "$(jq -e '.deps.reason | contains("dependências")' "$raw")"
}

f2_teste_falha_vira_exit_1
f2_sem_node_modules_nao_roda
f2_pr_altera_dependencias_nao_instala
