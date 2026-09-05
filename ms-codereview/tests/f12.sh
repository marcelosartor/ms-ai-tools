# F5 — Sinais baratos
echo "-- F5: sinais baratos --"

f12_github_closing_issue() {
  local d="$WORK/f12-github" fakebin status
  new_repo "$d"
  echo x > "$d/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base

  fakebin="$WORK/f12-fake-gh-github"
  mkdir -p "$fakebin"
  cat > "$fakebin/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  case " $* " in
    *" --comments "*) echo "(sem comentarios)"; exit 0 ;;
  esac
  cat <<'JSON'
{"number":42,"title":"t","url":"https://x","state":"OPEN","isDraft":false,"author":{"login":"a"},"baseRefName":"main","headRefName":"feat/x","baseRefOid":"aaa","headRefOid":"bbb","body":"","additions":1,"deletions":0,"changedFiles":1,"files":[],"labels":[],"createdAt":"","mergedAt":null,"closedAt":null,"closingIssuesReferences":[{"number":42}]}
JSON
  exit 0
fi
if [ "$1" = "pr" ] && [ "$2" = "checks" ]; then echo '[]'; exit 0; fi
if [ "$1" = "auth" ]; then exit 0; fi
if [ "$1" = "repo" ] && [ "$2" = "view" ]; then echo 'false'; exit 0; fi
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  cat <<'JSON'
{"number":42,"title":"Issue title","body":"desc","state":"OPEN","labels":[],"comments":[],"url":"https://x"}
JSON
  exit 0
fi
exit 1
EOF
  chmod +x "$fakebin/gh"

  ( cd "$d" && PATH="$fakebin:$PATH" CR_BASE_DIR="$d" "$SKILL_DIR/scripts/fetch-context.sh" 42 >/dev/null 2>&1 )
  status="$(status_file_for "$d")"
  assert_eq "f12: provider github" "github" "$(jq -r .provider "$status")"
  assert_eq "f12: task_id 42" "42" "$(jq -r .task_id "$status")"
  assert_eq "f12: ticket.md gerado" "true" "$([ -s "$d/temp/cr/42/raw/ticket.md" ] && echo true || echo false)"
}

f12_jira_vence_sobre_github() {
  local d="$WORK/f12-jira" cfg base head status
  new_repo "$d"
  cfg="$WORK/f12-jira-config"
  mkdir -p "$cfg"
  cat > "$cfg/.env" <<'EOF'
JIRA_BASE_URL=https://example.atlassian.net
JIRA_EMAIL=me@example.com
JIRA_API_TOKEN=faketoken
EOF
  echo x > "$d/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base
  base="$(git -C "$d" rev-parse HEAD)"
  git -C "$d" checkout -qb feat/DEV-1
  echo y > "$d/a.ts"
  git -C "$d" commit -qam feature
  head="$(git -C "$d" rev-parse HEAD)"

  ( cd "$d" && MS_AI_TOOLS_CONFIG_DIR="$cfg" CR_BASE_DIR="$d" "$SKILL_DIR/scripts/fetch-context.sh" "$base...$head" >/dev/null 2>&1 )
  status="$(status_file_for "$d")"
  assert_eq "f12: jira vence sobre github" "jira" "$(jq -r .provider "$status")"
}

f12_ci_checks_failure() {
  local d="$WORK/f12-ci" fakebin status
  new_repo "$d"
  echo x > "$d/a.ts"
  git -C "$d" add -A && git -C "$d" commit -qm base

  fakebin="$WORK/f12-fake-gh-ci"
  mkdir -p "$fakebin"
  cat > "$fakebin/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  case " $* " in
    *" --comments "*) echo "(sem comentarios)"; exit 0 ;;
  esac
  cat <<'JSON'
{"number":7,"title":"t","url":"https://x","state":"OPEN","isDraft":false,"author":{"login":"a"},"baseRefName":"main","headRefName":"feat/y","baseRefOid":"aaa","headRefOid":"bbb","body":"","additions":1,"deletions":0,"changedFiles":1,"files":[],"labels":[],"createdAt":"","mergedAt":null,"closedAt":null,"closingIssuesReferences":[]}
JSON
  exit 0
fi
if [ "$1" = "pr" ] && [ "$2" = "checks" ]; then
  echo '[{"name":"build","state":"FAILURE","link":"https://x/checks/1"}]'
  exit 0
fi
if [ "$1" = "auth" ]; then exit 1; fi
exit 1
EOF
  chmod +x "$fakebin/gh"

  ( cd "$d" && PATH="$fakebin:$PATH" CR_BASE_DIR="$d" "$SKILL_DIR/scripts/fetch-context.sh" 7 >/dev/null 2>&1 )
  local ci
  ci="$(find "$d/temp/cr" -name ci.json | head -1)"
  assert_eq "f12: ci.json tem o check FAILURE" "FAILURE" "$(jq -r '.[0].state' "$ci")"
}

# ---------- post-review.sh: validação de linha antes de postar ----------
FAKE_GH_DIFF_DIR="$WORK/f12-fake-gh-diff"
mkdir -p "$FAKE_GH_DIFF_DIR"
cat > "$FAKE_GH_DIFF_DIR/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  printf '%s\n' "${FAKE_GH_HEAD:-}"
  exit 0
fi
if [ "$1" = "pr" ] && [ "$2" = "diff" ]; then
  printf -- '--- a/a.ts\n+++ b/a.ts\n@@ -1,2 +1,3 @@\n line1\n+line2\n line3\n'
  exit 0
fi
if [ "$1" = "api" ]; then
  exit "${FAKE_GH_API_EXIT:-0}"
fi
exit 1
EOF
chmod +x "$FAKE_GH_DIFF_DIR/gh"

run_post_f12() { # $1=diretório $2=head_sha -- resto=args do script
  local d="$1" head="$2"; shift 2
  ( cd "$d" && PATH="$FAKE_GH_DIFF_DIR:$PATH" FAKE_GH_HEAD="$head" \
    CR_BASE_DIR="$d" "$SKILL_DIR/scripts/post-review.sh" "$@" )
}

f12_linha_fora_do_diff_recusa() {
  local d="$WORK/f12-fora-diff"
  mkdir -p "$d/temp/cr/9"
  cat > "$d/temp/cr/9/review-abc1234.json" <<'EOF'
{"commit_id":"deadbeef","event":"COMMENT","body":"ok","comments":[{"path":"a.ts","line":99,"side":"RIGHT","body":"x"}]}
EOF
  assert_exit "f12: linha fora do diff recusa com exit 5" "5" run_post_f12 "$d" "deadbeef" "9"
}

f12_linha_dentro_do_diff_prossegue() {
  local d="$WORK/f12-dentro-diff"
  mkdir -p "$d/temp/cr/9"
  cat > "$d/temp/cr/9/review-abc1234.json" <<'EOF'
{"commit_id":"deadbeef","event":"COMMENT","body":"ok","comments":[{"path":"a.ts","line":2,"side":"RIGHT","body":"x"}]}
EOF
  assert_exit "f12: linha dentro do diff prossegue (exit 0)" "0" run_post_f12 "$d" "deadbeef" "9"
}

f12_github_closing_issue
f12_jira_vence_sobre_github
f12_ci_checks_failure
f12_linha_fora_do_diff_recusa
f12_linha_dentro_do_diff_prossegue
