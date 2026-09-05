# F6 — Teste prova o fix (--prove-fix)
echo "-- F6: --prove-fix --"

run_checks_f13() { # $1=diretório -- resto = args do script
  local d="$1"; shift
  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/run-checks.sh" "$@" >/dev/null 2>&1 )
}

# vitest falso: falha em src/a.spec.ts quando src/a.ts contém "BUG", passa
# quando não contém. Simula "teste falha sem o fix, passa com o fix".
fake_vitest_prove() {
  cat > "$1" <<'EOF'
#!/usr/bin/env bash
if grep -q BUG src/a.ts 2>/dev/null; then
  echo "FAIL src/a.spec.ts"
  exit 1
fi
echo "PASS src/a.spec.ts"
exit 0
EOF
  chmod +x "$1"
}

f13_prove_fix_proves() {
  local d="$WORK/f13-proves" base head raw
  new_repo "$d"
  mkdir -p "$d/node_modules/.bin" "$d/src"
  printf '{}\n' > "$d/package.json"
  fake_vitest_prove "$d/node_modules/.bin/vitest"
  printf 'export const a = "BUG";\n' > "$d/src/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  printf 'export const a = "ok";\n' > "$d/src/a.ts"
  printf "test('a', () => {})\n" > "$d/src/a.spec.ts"
  git -C "$d" add -A && git -C "$d" commit -qm fix
  head="$(git -C "$d" rev-parse HEAD)"

  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/fetch-context.sh" "$base...$head" >/dev/null 2>&1 )
  run_checks_f13 "$d" "$base...$head" --prove-fix
  raw="$(find "$d/temp/cr" -name checks.json | head -1)"

  assert_eq "f13: prove_fix=proves" "proves" "$(jq -r .prove_fix "$raw")"
}

f13_prove_fix_does_not_prove() {
  local d="$WORK/f13-nao-prova" base head raw
  new_repo "$d"
  mkdir -p "$d/node_modules/.bin" "$d/src"
  printf '{}\n' > "$d/package.json"
  fake_vitest_prove "$d/node_modules/.bin/vitest"
  printf 'export const a = "ok";\n' > "$d/src/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  printf "test('a', () => {})\n" > "$d/src/a.spec.ts"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/fetch-context.sh" "$base...$head" >/dev/null 2>&1 )
  run_checks_f13 "$d" "$base...$head" --prove-fix
  raw="$(find "$d/temp/cr" -name checks.json | head -1)"

  assert_eq "f13: prove_fix=does_not_prove" "does_not_prove" "$(jq -r .prove_fix "$raw")"
}

f13_sem_flag_fica_null() {
  local d="$WORK/f13-sem-flag" base head raw
  new_repo "$d"
  mkdir -p "$d/node_modules/.bin" "$d/src"
  printf '{}\n' > "$d/package.json"
  fake_vitest_prove "$d/node_modules/.bin/vitest"
  printf 'export const a = "ok";\n' > "$d/src/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf "test('a', () => {})\n" > "$d/src/a.spec.ts"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/fetch-context.sh" "$base...$head" >/dev/null 2>&1 )
  run_checks_f13 "$d" "$base...$head"
  raw="$(find "$d/temp/cr" -name checks.json | head -1)"

  assert_eq "f13: sem --prove-fix, prove_fix é null" "null" "$(jq -r .prove_fix "$raw")"
}

f13_prove_fix_proves
f13_prove_fix_does_not_prove
f13_sem_flag_fica_null
