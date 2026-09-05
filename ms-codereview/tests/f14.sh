# F7 — Checklist backend-node (Node puro, Express, Fastify, NestJS)
echo "-- F7: checklist backend-node --"

run_detect_f14() { # $1=diretório -- resto = args do script
  local d="$1"; shift
  ( cd "$d" && CR_BASE_DIR="$d" "$SKILL_DIR/scripts/detect-checklists.sh" "$@" >/dev/null 2>&1 )
}

checklists_file_for() { # redefinida aqui: f14 roda antes de f5 na ordem alfabética
  find "$1/temp/cr" -name checklists.json 2>/dev/null | head -1
}

f14_express() {
  local d="$WORK/f14-express" base head out
  new_repo "$d"
  printf '{}\n' > "$d/package.json"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  printf '{"dependencies": {"express": "5.0.0"}}\n' > "$d/package.json"
  mkdir -p "$d/src/routes"
  printf 'export const x = 1;\n' > "$d/src/routes/users.ts"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f14 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f14: carrega backend-node" "true" "$(jq -e '.load | index("backend-node") != null' "$out")"
  assert_eq "f14: variants == [express]" '["express"]' "$(jq -c '.variants["backend-node"]' "$out")"
}

f14_nest_sobre_fastify() {
  local d="$WORK/f14-nest-fastify" base head out
  new_repo "$d"
  printf '{}\n' > "$d/package.json"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"

  printf '{"dependencies": {"@nestjs/core": "11.0.0", "@nestjs/platform-fastify": "11.0.0"}}\n' > "$d/package.json"
  mkdir -p "$d/src"
  printf 'export const x = 1;\n' > "$d/src/app.controller.ts"
  git -C "$d" add -A && git -C "$d" commit -qm feature
  head="$(git -C "$d" rev-parse HEAD)"

  run_detect_f14 "$d" "$base...$head"
  out="$(checklists_file_for "$d")"
  assert_eq "f14: variants == [fastify,nest]" '["fastify","nest"]' "$(jq -c '.variants["backend-node"]' "$out")"
}

f14_arquivo_renomeado() {
  assert_eq "f14: backend-node-nest.md não existe mais" "true" \
    "$([ ! -f "$SKILL_DIR/checklists/backend-node-nest.md" ] && echo true || echo false)"
  assert_eq "f14: backend-node.md existe" "true" \
    "$([ -f "$SKILL_DIR/checklists/backend-node.md" ] && echo true || echo false)"
  assert_eq "f14: index.json não cita backend-node-nest" "true" \
    "$(jq -e 'has("backend-node-nest") | not' "$SKILL_DIR/checklists/index.json")"
}

f14_express
f14_nest_sobre_fastify
f14_arquivo_renomeado
