# F12 — Checklists de banco: SQL Server, SQLite (Android), MongoDB
echo "-- F12: desempate entre checklists de banco --"

run_detect_f18() { # $1=diretório -- resto = args do script
  local d="$1"; shift
  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/detect-checklists.sh" "$@" >/dev/null 2>&1 )
}

checklists_file_for() { # redefinida aqui: f18 roda antes de f5 na ordem alfabética
  find "$1/temp/cr" -name checklists.json 2>/dev/null | head -1
}

f18_mssql_vence_por_deps() {
  local d="$WORK/f18-mssql" base head out
  new_repo "$d"
  printf '{"dependencies": {}}\n' > "$d/package.json"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  printf '{"dependencies": {"mssql": "10.0.0"}}\n' > "$d/package.json"
  mkdir -p "$d/db/migration"
  printf 'ALTER TABLE x ADD y INT;\n' > "$d/db/migration/V1__x.sql"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f18 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f18: database-mssql carrega" "true" "$(jq -e '.load | index("database-mssql") != null' "$out")"
  assert_eq "f18: database-postgres-pgvector NÃO carrega" "true" \
    "$(jq -e '.load | index("database-postgres-pgvector") == null' "$out")"
  assert_eq "f18: suppressed explica postgres" "true" \
    "$(jq -e '.suppressed["database-postgres-pgvector"] | contains("database")' "$out")"
}

f18_postgres_vence_por_deps() {
  local d="$WORK/f18-postgres" base head out
  new_repo "$d"
  printf '{"dependencies": {}}\n' > "$d/package.json"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  printf '{"dependencies": {"pg": "8.0.0"}}\n' > "$d/package.json"
  mkdir -p "$d/db/migration"
  printf 'ALTER TABLE x ADD y INT;\n' > "$d/db/migration/V1__x.sql"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f18 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f18: database-postgres-pgvector carrega" "true" \
    "$(jq -e '.load | index("database-postgres-pgvector") != null' "$out")"
  assert_eq "f18: database-mssql NÃO carrega" "true" "$(jq -e '.load | index("database-mssql") == null' "$out")"
}

f18_mssql_por_manifest_java() {
  local d="$WORK/f18-mssql-java" base head out
  new_repo "$d"
  printf '<project></project>\n' > "$d/pom.xml"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  printf '<project><dependency><artifactId>mssql-jdbc</artifactId></dependency></project>\n' > "$d/pom.xml"
  mkdir -p "$d/src/main/resources/db/migration"
  printf 'ALTER TABLE x ADD y INT;\n' > "$d/src/main/resources/db/migration/V1__x.sql"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f18 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f18: database-mssql carrega (manifest java)" "true" "$(jq -e '.load | index("database-mssql") != null' "$out")"
  assert_eq "f18: java-spring carrega" "true" "$(jq -e '.load | index("java-spring") != null' "$out")"
  assert_eq "f18: postgres não carrega" "true" "$(jq -e '.load | index("database-postgres-pgvector") == null' "$out")"
}

f18_sql_sem_dependencia_empata() {
  local d="$WORK/f18-empate-sql" base head out
  new_repo "$d"
  echo x > "$d/a.txt"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  mkdir -p "$d/db/migration"
  # conteúdo neutro: não bate em nenhum content-pattern específico de
  # mssql nem de postgres, só em "paths" para os dois -> empate real.
  printf 'CREATE TABLE foo (id INT);\n' > "$d/db/migration/V1__x.sql"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f18 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f18: empate mantém database-mssql" "true" "$(jq -e '.load | index("database-mssql") != null' "$out")"
  assert_eq "f18: empate mantém database-postgres-pgvector" "true" \
    "$(jq -e '.load | index("database-postgres-pgvector") != null' "$out")"
}

f18_android_sqlite() {
  local d="$WORK/f18-sqlite-android" base head out
  new_repo "$d"
  mkdir -p "$d/app"
  printf 'plugins { id("com.android.application") }\n' > "$d/app/build.gradle.kts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  printf 'plugins { id("com.android.application") }\ndependencies { implementation("androidx.room:room-runtime:2.7.0") }\n' \
    > "$d/app/build.gradle.kts"
  mkdir -p "$d/app/src/main/kotlin/app"
  printf '@Dao\ninterface UserDao {}\n' > "$d/app/src/main/kotlin/app/UserDao.kt"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f18 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f18: database-sqlite-android carrega" "true" "$(jq -e '.load | index("database-sqlite-android") != null' "$out")"
  assert_eq "f18: android-kotlin carrega junto" "true" "$(jq -e '.load | index("android-kotlin") != null' "$out")"
  assert_eq "f18: nenhum outro checklist de banco carrega" "0" \
    "$(jq '[.load[] | select(startswith("database-") and . != "database-sqlite-android")] | length' "$out")"
}

f18_mongo_e_postgres_empatam_por_deps() {
  local d="$WORK/f18-mongo-postgres" base head out
  new_repo "$d"
  printf '{"dependencies": {}}\n' > "$d/package.json"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  printf '{"dependencies": {"mongoose": "8.0.0", "pg": "8.0.0"}}\n' > "$d/package.json"
  printf "import mongoose from 'mongoose';\nmongoose.connect('x');\n" > "$d/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f18 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f18: database-mongodb carrega" "true" "$(jq -e '.load | index("database-mongodb") != null' "$out")"
  assert_eq "f18: database-postgres-pgvector carrega junto (empate deps)" "true" \
    "$(jq -e '.load | index("database-postgres-pgvector") != null' "$out")"
}

f18_why_com_dois_metodos() {
  local d="$WORK/f18-why-dois" base head out
  new_repo "$d"
  printf '{"dependencies": {}}\n' > "$d/package.json"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  printf '{"dependencies": {"mssql": "10.0.0"}}\n' > "$d/package.json"
  printf 'ALTER TABLE x ADD y INT;\n' > "$d/report.sql"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f18 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f18: why cita paths e deps separados por '; '" "true" \
    "$(jq -e '.why["database-mssql"] | contains("paths:") and contains("; ") and contains("deps:")' "$out")"
}

f18_mssql_vence_por_deps
f18_postgres_vence_por_deps
f18_mssql_por_manifest_java
f18_sql_sem_dependencia_empata
f18_android_sqlite
f18_mongo_e_postgres_empatam_por_deps
f18_why_com_dois_metodos
