# F4 — Segurança afinada
echo "-- F4: segurança afinada --"

run_detect_f11() { # $1=diretório -- resto = args do script
  local d="$1"; shift
  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/detect-checklists.sh" "$@" >/dev/null 2>&1 )
}

checklists_file_for() { # $1=diretório do repo (redefinida aqui: f11 roda antes de f5 na ordem alfabética)
  find "$1/temp/cr" -name checklists.json 2>/dev/null | head -1
}

f11_author_ts_nao_ativa() {
  local d="$WORK/f11-author" base head out
  new_repo "$d"
  printf 'export const a = 1;\n' > "$d/author.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf 'export const a = 2;\n' > "$d/author.ts"
  git -C "$d" commit -qam feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f11 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f11: author.ts não ativa security" "false" "$(jq -r .security "$out")"
}

f11_tokens_ts_nao_ativa() {
  local d="$WORK/f11-tokens" base head out
  new_repo "$d"
  printf 'export const a = 1;\n' > "$d/tokens.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf 'export const a = 2;\n' > "$d/tokens.ts"
  git -C "$d" commit -qam feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f11 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f11: tokens.ts não ativa security" "false" "$(jq -r .security "$out")"
}

f11_regex_exec_nao_ativa() {
  local d="$WORK/f11-reexec" base head out
  new_repo "$d"
  printf 'export const a = 1;\n' > "$d/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf 'export function m(re, s) { return re.exec(s); }\n' > "$d/a.ts"
  git -C "$d" commit -qam feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f11 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f11: re.exec(s) não ativa security" "false" "$(jq -r .security "$out")"
}

f11_child_process_ativa() {
  local d="$WORK/f11-childproc" base head out
  new_repo "$d"
  printf 'export const a = 1;\n' > "$d/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf "import { exec } from 'child_process';\nexec('ls');\n" > "$d/a.ts"
  git -C "$d" commit -qam feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f11 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f11: child_process ativa security" "true" "$(jq -r .security "$out")"
}

f11_github_workflow_ativa_por_caminho() {
  local d="$WORK/f11-workflow" base head out
  new_repo "$d"
  mkdir -p "$d/.github/workflows"
  printf 'name: x\n' > "$d/.github/workflows/ci.yml"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf 'name: x\non: push\n' > "$d/.github/workflows/ci.yml"
  git -C "$d" commit -qam feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f11 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f11: .github/workflows ativa security" "true" "$(jq -r .security "$out")"
  assert_eq "f11: motivo cita caminho" "true" "$(jq -e '.security_why | contains("caminho")' "$out")"
}

f11_pom_xml_dependencia_nova() {
  local d="$WORK/f11-pom" base head out
  new_repo "$d"
  printf '<project></project>\n' > "$d/pom.xml"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf '<project><dependency><artifactId>spring-boot-starter-web</artifactId></dependency></project>\n' > "$d/pom.xml"
  git -C "$d" commit -qam feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f11 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f11: pom.xml com artifactId novo ativa security" "true" "$(jq -r .security "$out")"
  assert_eq "f11: security_why cita a dependência" "true" "$(jq -e '.security_why | contains("spring-boot-starter-web")' "$out")"
}

f11_advisories_com_gh() {
  local d="$WORK/f11-advisories" base head fakebin
  new_repo "$d"
  printf '{"dependencies": {}}\n' > "$d/package.json"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf '{"dependencies": {"left-pad": "1.0.0"}}\n' > "$d/package.json"
  git -C "$d" commit -qam feature
  head="$(git -C "$d" rev-parse HEAD)"

  fakebin="$WORK/f11-fake-gh-bin"
  mkdir -p "$fakebin"
  cat > "$fakebin/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "api" ]; then
  echo '[{"ghsa_id":"GHSA-aaaa-bbbb-cccc","severity":"high","vulnerabilities":[{"vulnerable_version_range":"< 2.0.0","first_patched_version":"2.0.0"}]}]'
  exit 0
fi
exit 1
EOF
  chmod +x "$fakebin/gh"

  ( cd "$d" && PATH="$fakebin:$PATH" CR_BASE_DIR="$d" "$SKILL_DIR/scripts/fetch-context.sh" "$base...$head" >/dev/null 2>&1 )
  assert_eq "f11: advisories.md cita GHSA" "true" \
    "$(grep -q 'GHSA-aaaa-bbbb-cccc' "$d/temp/cr/$base...$head/raw/advisories.md" && echo true || echo false)"
}

f11_advisories_sem_gh() {
  local d="$WORK/f11-advisories-sem-gh" base head
  new_repo "$d"
  printf '{"dependencies": {}}\n' > "$d/package.json"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  printf '{"dependencies": {"left-pad": "1.0.0"}}\n' > "$d/package.json"
  git -C "$d" commit -qam feature
  head="$(git -C "$d" rev-parse HEAD)"

  # CR_NO_GH=1 simula "sem gh" sem mexer no PATH (gh de verdade continua
  # sendo achado por outra chamada do teste, então filtrar PATH é frágil).
  ( cd "$d" && CR_NO_GH=1 CR_BASE_DIR="$d" "$SKILL_DIR/scripts/fetch-context.sh" "$base...$head" >/dev/null 2>&1 )
  assert_eq "f11: sem gh -> não consultado" "true" \
    "$(grep -q 'não consultado' "$d/temp/cr/$base...$head/raw/advisories.md" && echo true || echo false)"
}

f11_author_ts_nao_ativa
f11_tokens_ts_nao_ativa
f11_regex_exec_nao_ativa
f11_child_process_ativa
f11_github_workflow_ativa_por_caminho
f11_pom_xml_dependencia_nova
f11_advisories_com_gh
f11_advisories_sem_gh
