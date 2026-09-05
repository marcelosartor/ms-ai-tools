# F4 — Review inline pronto para postar
echo "-- F4: review inline --"

# gh falso: só entende "pr view ... --json headRefOid -q .headRefOid" (imprime
# $FAKE_GH_HEAD) e "api ... --method POST --input ..." (sai com
# $FAKE_GH_API_EXIT, default 0). Fica na frente do PATH só durante o teste.
FAKE_GH_DIR="$WORK/fake-gh-bin"
mkdir -p "$FAKE_GH_DIR"
cat > "$FAKE_GH_DIR/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  printf '%s\n' "${FAKE_GH_HEAD:-}"
  exit 0
fi
if [ "$1" = "api" ]; then
  exit "${FAKE_GH_API_EXIT:-0}"
fi
exit 1
EOF
chmod +x "$FAKE_GH_DIR/gh"

run_post() { # $1=diretório $2=head_sha_do_gh $3=api_exit -- resto=args do script
  local d="$1" head="$2" api_exit="$3"; shift 3
  ( cd "$d" && PATH="$FAKE_GH_DIR:$PATH" FAKE_GH_HEAD="$head" FAKE_GH_API_EXIT="$api_exit" \
    CR_BASE_DIR="$d" "$SKILL_DIR/scripts/post-review.sh" "$@" )
}

f4_json_valido_publica() {
  local d="$WORK/f4-valido"
  mkdir -p "$d/temp/cr/42"
  cat > "$d/temp/cr/42/review-abc1234.json" <<'EOF'
{"commit_id":"deadbeef","event":"COMMENT","body":"ok","comments":[{"path":"a.ts","line":1,"side":"RIGHT","body":"x"}]}
EOF
  assert_exit "f4: JSON válido publica (commit_id bate)" "0" run_post "$d" "deadbeef" "0" "42"
}

f4_sem_event_falha_uso() {
  local d="$WORK/f4-sem-event"
  mkdir -p "$d/temp/cr/42"
  cat > "$d/temp/cr/42/review-abc1234.json" <<'EOF'
{"commit_id":"deadbeef","body":"ok","comments":[]}
EOF
  assert_exit "f4: sem event falha com exit 2" "2" run_post "$d" "deadbeef" "0" "42"
}

f4_commit_id_divergente_falha() {
  local d="$WORK/f4-divergente"
  mkdir -p "$d/temp/cr/42"
  cat > "$d/temp/cr/42/review-abc1234.json" <<'EOF'
{"commit_id":"deadbeef","event":"APPROVE","body":"ok","comments":[]}
EOF
  assert_exit "f4: commit_id divergente falha com exit 3" "3" run_post "$d" "outrocommit" "0" "42"
}

f4_json_valido_publica
f4_sem_event_falha_uso
f4_commit_id_divergente_falha
