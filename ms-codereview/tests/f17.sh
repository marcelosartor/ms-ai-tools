# F11 — Checklist java-spring
echo "-- F11: checklist java-spring --"

run_detect_f17() { # $1=diretório -- resto = args do script
  local d="$1"; shift
  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/detect-checklists.sh" "$@" >/dev/null 2>&1 )
}

checklists_file_for() { # redefinida aqui: f17 roda antes de f5 na ordem alfabética
  find "$1/temp/cr" -name checklists.json 2>/dev/null | head -1
}

f17_jpa_e_security() {
  local d="$WORK/f17-jpa-security" base head out
  new_repo "$d"
  printf '<project></project>\n' > "$d/pom.xml"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  printf '<project><dependency><artifactId>spring-boot-starter-data-jpa</artifactId></dependency><dependency><artifactId>spring-boot-starter-security</artifactId></dependency></project>\n' \
    > "$d/pom.xml"
  mkdir -p "$d/src/main/java/app"
  printf 'class App {}\n' > "$d/src/main/java/app/App.java"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f17 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f17: carrega java-spring" "true" "$(jq -e '.load | index("java-spring") != null' "$out")"
  assert_eq "f17: variants contém jpa" "true" "$(jq -e '.variants["java-spring"] | index("jpa") != null' "$out")"
  assert_eq "f17: variants contém security" "true" "$(jq -e '.variants["java-spring"] | index("security") != null' "$out")"
}

f17_kotlin_com_spring_nao_carrega_android() {
  local d="$WORK/f17-kotlin-spring" base head out
  new_repo "$d"
  printf 'plugins {}\n' > "$d/build.gradle.kts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  printf 'dependencies { implementation("org.springframework.boot:spring-boot-starter") }\n' \
    > "$d/build.gradle.kts"
  mkdir -p "$d/src/main/kotlin/app"
  printf 'class App\n' > "$d/src/main/kotlin/app/App.kt"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f17 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f17: java-spring carrega por manifest (Kotlin)" "true" "$(jq -e '.load | index("java-spring") != null' "$out")"
  assert_eq "f17: android-kotlin não carrega" "true" "$(jq -e '.load | index("android-kotlin") == null' "$out")"
}

f17_migration_carrega_java_spring_e_postgres() {
  local d="$WORK/f17-migration" base head out
  new_repo "$d"
  echo x > "$d/a.txt"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  mkdir -p "$d/src/main/resources/db/migration"
  printf 'ALTER TABLE x ADD COLUMN y int;\n' > "$d/src/main/resources/db/migration/V2__x.sql"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f17 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f17: java-spring carrega (paths db/migration)" "true" "$(jq -e '.load | index("java-spring") != null' "$out")"
  assert_eq "f17: database-postgres-pgvector carrega (paths migration)" "true" \
    "$(jq -e '.load | index("database-postgres-pgvector") != null' "$out")"
}

f17_jpa_e_security
f17_kotlin_com_spring_nao_carrega_android
f17_migration_carrega_java_spring_e_postgres
