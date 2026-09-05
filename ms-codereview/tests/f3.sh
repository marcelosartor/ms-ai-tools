# F3 — Re-review incremental
echo "-- F3: re-review incremental --"

f3_detecta_report_anterior() {
  local d="$WORK/f3-previous" status
  new_repo "$d"
  echo x > "$d/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base

  mkdir -p "$d/temp/cr/999"
  printf '<!-- achados\nblocker | a.ts:1 | exemplo\n-->\n' > "$d/temp/cr/999/report-abc1234.md"

  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/fetch-context.sh" 999 >/dev/null 2>&1 )
  status="$(status_file_for "$d")"
  assert_eq "f3: previous_sha detectado" "abc1234" "$(jq -r .previous_sha "$status")"
  assert_eq "f3: previous_report aponta pro arquivo certo" "$d/temp/cr/999/report-abc1234.md" "$(jq -r .previous_report "$status")"
}

f3_sem_report_anterior() {
  local d="$WORK/f3-none" status
  new_repo "$d"
  echo x > "$d/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base

  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/fetch-context.sh" 999 >/dev/null 2>&1 )
  status="$(status_file_for "$d")"
  assert_eq "f3: sem report anterior -> previous_sha nulo" "null" "$(jq -r '.previous_sha // "null"' "$status")"
}

f3_head_base_sha_de_range() {
  local d="$WORK/f3-shas" base head status
  new_repo "$d"
  echo x > "$d/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  echo y > "$d/a.ts"
  git -C "$d" commit -qam mudanca
  head="$(git -C "$d" rev-parse HEAD)"

  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/fetch-context.sh" "$base...$head" >/dev/null 2>&1 )
  status="$(status_file_for "$d")"
  assert_eq "f3: base_sha do range" "$base" "$(jq -r .base_sha "$status")"
  assert_eq "f3: head_sha do range" "$head" "$(jq -r .head_sha "$status")"
}

f3_detecta_report_anterior
f3_sem_report_anterior
f3_head_base_sha_de_range
