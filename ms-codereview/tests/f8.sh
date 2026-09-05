# F1 — Modo incremental corrigido
echo "-- F1: previous_is_ancestor / previous_base_sha / base_moved --"

run_fetch_f8() { # $1=diretório do repo -- resto = args do script
  local d="$1"; shift
  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/fetch-context.sh" "$@" >/dev/null 2>&1 )
}

f8_ancestral_true() {
  local d="$WORK/f8-ancestor" prev_sha head_sha status
  new_repo "$d"
  git -C "$d" checkout -q -b base
  echo x > "$d/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  git -C "$d" checkout -q -b head
  echo y > "$d/a.ts"
  git -C "$d" commit -qam "commit anterior"
  prev_sha="$(git -C "$d" rev-parse HEAD)"

  mkdir -p "$d/temp/cr/base...head"
  printf '<!-- achados\nblocker | a.ts:1 | exemplo | y\n-->\n' \
    > "$d/temp/cr/base...head/report-$(git -C "$d" rev-parse --short "$prev_sha").md"

  echo z > "$d/a.ts"
  git -C "$d" commit -qam "commit novo"

  run_fetch_f8 "$d" "base...head"
  status="$(status_file_for "$d")"
  assert_eq "f8: previous_is_ancestor true" "true" "$(jq -r .previous_is_ancestor "$status")"
}

f8_nao_ancestral_false() {
  local d="$WORK/f8-not-ancestor" other_sha status
  new_repo "$d"
  git -C "$d" checkout -q -b base
  echo x > "$d/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base

  git -C "$d" checkout -q -b other
  echo w > "$d/a.ts"
  git -C "$d" commit -qam "commit de outra branch"
  other_sha="$(git -C "$d" rev-parse HEAD)"

  git -C "$d" checkout -q base
  git -C "$d" checkout -q -b head
  echo z > "$d/a.ts"
  git -C "$d" commit -qam "commit da branch do PR"

  mkdir -p "$d/temp/cr/base...head"
  printf '<!-- achados\nblocker | a.ts:1 | exemplo | w\n-->\n' \
    > "$d/temp/cr/base...head/report-$(git -C "$d" rev-parse --short "$other_sha").md"

  run_fetch_f8 "$d" "base...head"
  status="$(status_file_for "$d")"
  assert_eq "f8: previous_is_ancestor false (não ancestral)" "false" "$(jq -r .previous_is_ancestor "$status")"
}

f8_sha_inexistente_null() {
  local d="$WORK/f8-null" status
  new_repo "$d"
  git -C "$d" checkout -q -b base
  echo x > "$d/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  git -C "$d" checkout -q -b head
  echo y > "$d/a.ts"
  git -C "$d" commit -qam head

  mkdir -p "$d/temp/cr/base...head"
  printf '<!-- achados\nblocker | a.ts:1 | exemplo | y\n-->\n' \
    > "$d/temp/cr/base...head/report-0000000.md"

  run_fetch_f8 "$d" "base...head"
  status="$(status_file_for "$d")"
  assert_eq "f8: previous_is_ancestor null (sha inexistente)" "null" "$(jq -r .previous_is_ancestor "$status")"
}

f8_meta_base_moved() {
  local d="$WORK/f8-meta" base1_sha prev_sha status
  new_repo "$d"
  git -C "$d" checkout -q -b base
  echo x > "$d/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base1_sha="$(git -C "$d" rev-parse HEAD)"

  git -C "$d" checkout -q -b head
  echo y > "$d/a.ts"
  git -C "$d" commit -qam "commit anterior"
  prev_sha="$(git -C "$d" rev-parse HEAD)"

  mkdir -p "$d/temp/cr/base...head"
  printf '<!-- meta\nhead_sha: %s\nbase_sha: %s\n-->\n<!-- achados\n-->\n' \
    "$prev_sha" "$base1_sha" > "$d/temp/cr/base...head/report-$(git -C "$d" rev-parse --short "$prev_sha").md"

  echo z > "$d/a.ts"
  git -C "$d" commit -qam "commit novo"

  run_fetch_f8 "$d" "base...head"
  status="$(status_file_for "$d")"
  assert_eq "f8: previous_base_sha lido do bloco meta" "$base1_sha" "$(jq -r .previous_base_sha "$status")"
  assert_eq "f8: base_moved false quando base não mudou" "false" "$(jq -r .base_moved "$status")"
}

f8_ancestral_true
f8_nao_ancestral_false
f8_sha_inexistente_null
f8_meta_base_moved
