# F10 — Checklist android-kotlin
echo "-- F10: checklist android-kotlin --"

run_detect_f16() { # $1=diretório -- resto = args do script
  local d="$1"; shift
  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/detect-checklists.sh" "$@" >/dev/null 2>&1 )
}

checklists_file_for() { # redefinida aqui: f16 roda antes de f5 na ordem alfabética
  find "$1/temp/cr" -name checklists.json 2>/dev/null | head -1
}

f16_compose_por_manifest_e_variante() {
  local d="$WORK/f16-compose" base head out
  new_repo "$d"
  mkdir -p "$d/app"
  printf 'plugins {}\n' > "$d/app/build.gradle.kts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  printf 'plugins { id("com.android.application") }\nandroid { buildFeatures { compose = true } }\n' \
    > "$d/app/build.gradle.kts"
  mkdir -p "$d/app/src/main/kotlin/app"
  printf '@Composable\nfun Screen() {}\n' > "$d/app/src/main/kotlin/app/Screen.kt"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f16 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f16: carrega android-kotlin" "true" "$(jq -e '.load | index("android-kotlin") != null' "$out")"
  assert_eq "f16: variants contém compose" "true" "$(jq -e '.variants["android-kotlin"] | index("compose") != null' "$out")"
}

f16_kts_sozinho_em_projeto_spring_nao_carrega() {
  local d="$WORK/f16-spring-kts" base head out
  new_repo "$d"
  printf 'plugins { id("org.springframework.boot") }\n' > "$d/build.gradle.kts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  printf 'plugins { id("org.springframework.boot") }\ndependencies {}\n' > "$d/build.gradle.kts"
  git -C "$d" commit -qam feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f16 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f16: android-kotlin não carrega (paths_require_manifest)" "true" \
    "$(jq -e '.load | index("android-kotlin") == null' "$out")"
}

f16_views_variante() {
  local d="$WORK/f16-views" base head out
  new_repo "$d"
  mkdir -p "$d/app"
  printf 'plugins { id("com.android.application") }\n' > "$d/app/build.gradle.kts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  mkdir -p "$d/app/src/main/res/layout"
  printf '<LinearLayout />\n' > "$d/app/src/main/res/layout/item.xml"
  mkdir -p "$d/app/src/main/kotlin/app"
  printf 'fun bind() { findViewById<View>(0) }\n' > "$d/app/src/main/kotlin/app/Bind.kt"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f16 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f16: variants contém views" "true" "$(jq -e '.variants["android-kotlin"] | index("views") != null' "$out")"
}

f16_compose_por_manifest_e_variante
f16_kts_sozinho_em_projeto_spring_nao_carrega
f16_views_variante
