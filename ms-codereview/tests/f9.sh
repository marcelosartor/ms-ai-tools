# F2 — Verificações com baseline, monorepo e worktree vivo
echo "-- F2: baseline, monorepo, worktree vivo --"

run_checks_f9() { # $1=diretório -- resto = args do script
  local d="$1"; shift
  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/run-checks.sh" "$@" >/dev/null 2>&1 )
}

fake_vitest() { # $1=caminho do binário fake -- roda "ok" para tudo (nada falha)
  cat > "$1" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$1"
}

f9_monorepo_dois_pacotes() {
  local d="$WORK/f9-monorepo" base head raw
  new_repo "$d"
  mkdir -p "$d/apps/api/node_modules/.bin" "$d/apps/web/node_modules/.bin"
  printf '{}\n' > "$d/apps/api/package.json"
  printf '{}\n' > "$d/apps/web/package.json"
  fake_vitest "$d/apps/api/node_modules/.bin/vitest"
  fake_vitest "$d/apps/web/node_modules/.bin/vitest"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  mkdir -p "$d/apps/api/src" "$d/apps/web/src"
  printf 'export const a = 1;\n' > "$d/apps/api/src/a.spec.ts"
  printf 'export const b = 1;\n' > "$d/apps/web/src/b.spec.ts"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/fetch-context.sh" "$base...$head" >/dev/null 2>&1 )
  run_checks_f9 "$d" "$base...$head"
  raw="$(find "$d/temp/cr" -name checks.json | head -1)"

  assert_eq "f9: dois pacotes detectados" "2" "$(jq '.packages | length' "$raw")"
  assert_eq "f9: pacote apps/api presente" "true" "$(jq -e '[.packages[].dir] | index("apps/api") != null' "$raw")"
  assert_eq "f9: pacote apps/web presente" "true" "$(jq -e '[.packages[].dir] | index("apps/web") != null' "$raw")"
}

fake_tsc_marker() { # $1=caminho -- lê src/a.ts em busca de MARK1/MARK2
  cat > "$1" <<'EOF'
#!/usr/bin/env bash
RC=0
if grep -q MARK1 src/a.ts 2>/dev/null; then
  echo "src/a.ts(1,1): error TS1000: erro base"
  RC=1
fi
if grep -q MARK2 src/a.ts 2>/dev/null; then
  echo "src/a.ts(2,2): error TS2000: erro novo"
  RC=1
fi
exit $RC
EOF
  chmod +x "$1"
}

f9_baseline_typecheck_preexistente() {
  local d="$WORK/f9-tc-ok" base head raw
  new_repo "$d"
  mkdir -p "$d/node_modules/.bin" "$d/src"
  printf '{}\n' > "$d/package.json"
  printf '{}\n' > "$d/tsconfig.json"
  fake_tsc_marker "$d/node_modules/.bin/tsc"
  printf '// MARK1\nexport const a = 1;\n' > "$d/src/a.ts"
  printf 'export const b = 1;\n' > "$d/src/b.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  printf 'export const b = 2;\n' > "$d/src/b.ts"
  git -C "$d" commit -qam feature

  head="$(git -C "$d" rev-parse HEAD)"

  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/fetch-context.sh" "$base...$head" >/dev/null 2>&1 )
  run_checks_f9 "$d" "$base...$head"
  raw="$(find "$d/temp/cr" -name checks.json | head -1)"

  assert_eq "f9: typecheck ok quando erro já existia na base" "ok" "$(jq -r '.packages[0].typecheck.status' "$raw")"
  assert_eq "f9: preexisting=1" "1" "$(jq -r '.packages[0].typecheck.preexisting' "$raw")"
}

f9_baseline_typecheck_erro_novo() {
  local d="$WORK/f9-tc-fail" base head raw
  new_repo "$d"
  mkdir -p "$d/node_modules/.bin" "$d/src"
  printf '{}\n' > "$d/package.json"
  printf '{}\n' > "$d/tsconfig.json"
  fake_tsc_marker "$d/node_modules/.bin/tsc"
  printf '// MARK1\nexport const a = 1;\n' > "$d/src/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  printf '// MARK1\n// MARK2\nexport const a = 1;\n' > "$d/src/a.ts"
  git -C "$d" commit -qam feature
  head="$(git -C "$d" rev-parse HEAD)"

  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/fetch-context.sh" "$base...$head" >/dev/null 2>&1 )
  run_checks_f9 "$d" "$base...$head"
  raw="$(find "$d/temp/cr" -name checks.json | head -1)"

  assert_eq "f9: typecheck falhou com erro novo" "falhou" "$(jq -r '.packages[0].typecheck.status' "$raw")"
  assert_eq "f9: new=1" "1" "$(jq -r '.packages[0].typecheck.new' "$raw")"
  assert_eq "f9: preexisting=1 mesmo com falha" "1" "$(jq -r '.packages[0].typecheck.preexisting' "$raw")"
}

f9_keep_mantem_worktree() {
  local d="$WORK/f9-keep" base head raw wt
  new_repo "$d"
  printf '{}\n' > "$d/package.json"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf '{"x":1}\n' > "$d/package.json"
  git -C "$d" commit -qam feature
  head="$(git -C "$d" rev-parse HEAD)"

  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/fetch-context.sh" "$base...$head" >/dev/null 2>&1 )
  run_checks_f9 "$d" "$base...$head" --keep
  raw="$(find "$d/temp/cr" -name checks.json | head -1)"
  wt="$(jq -r '.worktree' "$raw")"

  assert_eq "f9: --keep grava caminho do worktree" "true" "$([ -n "$wt" ] && [ "$wt" != "null" ] && echo true || echo false)"
  assert_eq "f9: --keep mantém o diretório" "true" "$([ -d "$wt" ] && echo true || echo false)"
  git -C "$d" worktree remove --force "$wt" >/dev/null 2>&1 || true
}

f9_sem_keep_remove_worktree() {
  local d="$WORK/f9-nokeep" base head raw
  new_repo "$d"
  printf '{}\n' > "$d/package.json"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf '{"x":1}\n' > "$d/package.json"
  git -C "$d" commit -qam feature
  head="$(git -C "$d" rev-parse HEAD)"

  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/fetch-context.sh" "$base...$head" >/dev/null 2>&1 )
  run_checks_f9 "$d" "$base...$head"

  assert_eq "f9: sem --keep, worktree não existe" "true" "$([ ! -d "$d/temp/cr/$base...$head/wt" ] && echo true || echo false)"
}

f9_gradle_sem_package_json() {
  local d="$WORK/f9-gradle" base head raw
  new_repo "$d"
  printf 'plugins {}\n' > "$d/build.gradle.kts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  mkdir -p "$d/src/main/kotlin/app"
  printf 'class App\n' > "$d/src/main/kotlin/app/App.kt"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/fetch-context.sh" "$base...$head" >/dev/null 2>&1 )
  local rc
  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/run-checks.sh" "$base...$head" >/dev/null 2>&1 )
  rc=$?
  raw="$(find "$d/temp/cr" -name checks.json | head -1)"

  assert_eq "f9: gradle sem package.json -> exit 0" "0" "$rc"
  assert_eq "f9: gradle sem package.json -> typecheck não rodou" "não rodou" "$(jq -r '.typecheck.status' "$raw")"
  assert_eq "f9: motivo cita stack fora do Node" "true" "$(jq -e '.typecheck.reason | contains("gradle")' "$raw")"
}

f9_discovery_por_import_relativo() {
  local d="$WORK/f9-discovery" base head raw
  new_repo "$d"
  mkdir -p "$d/node_modules/.bin" "$d/src" "$d/tests"
  printf '{}\n' > "$d/package.json"
  fake_vitest "$d/node_modules/.bin/vitest"
  printf 'export default 1;\n' > "$d/src/index.ts"
  printf "import x from '../src/other';\nx;\n" > "$d/tests/one.spec.ts"
  printf 'const s = "isto menciona index só como texto";\n' > "$d/tests/two.spec.ts"
  printf 'const index = 5; index;\n' > "$d/tests/three.spec.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  printf "import x from '../src/index';\nx;\n" > "$d/tests/one.spec.ts"
  printf 'export default 2;\n' > "$d/src/index.ts"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/fetch-context.sh" "$base...$head" >/dev/null 2>&1 )
  run_checks_f9 "$d" "$base...$head"
  raw="$(find "$d/temp/cr" -name checks.json | head -1)"

  assert_eq "f9: só o teste que importa index entra" "1" "$(jq '.test.files | length' "$raw")"
  assert_eq "f9: é tests/one.spec.ts" "true" "$(jq -e '.test.files | index("tests/one.spec.ts") != null' "$raw")"
}

f9_monorepo_dois_pacotes
f9_baseline_typecheck_preexistente
f9_baseline_typecheck_erro_novo
f9_keep_mantem_worktree
f9_sem_keep_remove_worktree
f9_gradle_sem_package_json
f9_discovery_por_import_relativo
