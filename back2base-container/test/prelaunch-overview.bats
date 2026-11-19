#!/usr/bin/env bats

# Tests for lib/prelaunch-overview.sh — orchestrates `claude -p` + splice
# into CLAUDE.md, with timeout, heartbeat, and graceful-skip on failure.

setup() {
  TEST_TMP="$(mktemp -d "${BATS_TMPDIR}/prelaunch-overview.XXXXXX")"
  export TEST_TMP

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HELPER="$REPO_ROOT/lib/prelaunch-overview.sh"
  RENDERER="$REPO_ROOT/lib/render-overview.py"
  PROMPT_FILE="$REPO_ROOT/lib/prelaunch-prompt.txt"

  # Stub `claude` and any other binaries we need on PATH.
  STUB_BIN="$TEST_TMP/stub-bin"
  mkdir -p "$STUB_BIN"
  export PATH="$STUB_BIN:$PATH"

  # Faux HOME with a starter CLAUDE.md.
  export HOME="$TEST_TMP/home"
  mkdir -p "$HOME/.claude"
  echo "# Stub CLAUDE.md" > "$HOME/.claude/CLAUDE.md"

  # Faux mounts the helper expects.
  export OVERVIEW_RENDERER_PATH="$RENDERER"
  export OVERVIEW_PROMPT_PATH="$PROMPT_FILE"

  # Generous timeout so heavy parallel load can't trip a spurious timeout in
  # the completion tests (splice / skip-nonzero / skip-empty). The dedicated
  # timeout test overrides this to a short value.
  export OVERVIEW_TIMEOUT_SECS=60
  export OVERVIEW_HEARTBEAT_SECS=1
}

teardown() {
  rm -rf "$TEST_TMP"
}

stub_claude() {
  cat > "$STUB_BIN/claude" <<EOF
#!/bin/sh
$1
EOF
  chmod +x "$STUB_BIN/claude"
}

@test "skip when BACK2BASE_OVERVIEW=0" {
  export BACK2BASE_OVERVIEW=0
  stub_claude 'echo "should not run"; exit 0'

  # shellcheck source=/dev/null
  . "$HELPER"
  run run_prelaunch_overview
  [ "$status" -eq 0 ]
  ! grep -q 'should not run' "$HOME/.claude/CLAUDE.md"
  ! grep -q 'overview-begin' "$HOME/.claude/CLAUDE.md"
}

@test "skip when BACK2BASE_OVERVIEW unset" {
  unset BACK2BASE_OVERVIEW
  stub_claude 'echo "should not run"; exit 0'

  . "$HELPER"
  run run_prelaunch_overview
  [ "$status" -eq 0 ]
  ! grep -q 'overview-begin' "$HOME/.claude/CLAUDE.md"
}

@test "splice on success" {
  export BACK2BASE_OVERVIEW=1
  stub_claude 'cat <<MARK
## What this is
Hello overview body.
MARK
exit 0'

  . "$HELPER"
  run run_prelaunch_overview
  [ "$status" -eq 0 ]
  grep -q 'overview-begin' "$HOME/.claude/CLAUDE.md"
  grep -q 'Hello overview body.' "$HOME/.claude/CLAUDE.md"
}

@test "skip when claude exits non-zero" {
  export BACK2BASE_OVERVIEW=1
  stub_claude 'echo partial; exit 7'

  . "$HELPER"
  run run_prelaunch_overview
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'overview skipped: claude exited 7'
  ! grep -q 'overview-begin' "$HOME/.claude/CLAUDE.md"
}

@test "skip on empty output" {
  export BACK2BASE_OVERVIEW=1
  stub_claude 'exit 0'  # nothing to stdout

  . "$HELPER"
  run run_prelaunch_overview
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'overview skipped: empty output'
  ! grep -q 'overview-begin' "$HOME/.claude/CLAUDE.md"
}

@test "timeout kills slow claude" {
  export BACK2BASE_OVERVIEW=1
  export OVERVIEW_TIMEOUT_SECS=1   # short timeout; stub sleeps far longer
  stub_claude 'sleep 10; echo too-late'

  . "$HELPER"
  run run_prelaunch_overview
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE 'overview skipped: timeout after [0-9]+s'
  ! grep -q 'too-late' "$HOME/.claude/CLAUDE.md"
}

@test "heartbeat lines appear during slow run" {
  export BACK2BASE_OVERVIEW=1
  stub_claude 'sleep 2; echo done'

  . "$HELPER"
  run run_prelaunch_overview
  [ "$status" -eq 0 ]
  # OVERVIEW_HEARTBEAT_SECS=1 → at least one "still running" line in 2s
  echo "$output" | grep -q 'still running'
}

@test "skips regeneration when tree hash unchanged and markers present" {
  export BACK2BASE_OVERVIEW=1
  stub_claude 'touch "$CLAUDE_INVOKED_MARKER"; echo "fresh overview"; exit 0'
  export CLAUDE_INVOKED_MARKER="$TEST_TMP/claude-ran"

  # A git repo whose HEAD tree hash we pre-store, plus existing markers.
  REPO_DIR="$TEST_TMP/repo"
  mkdir -p "$REPO_DIR" && cd "$REPO_DIR"
  git init -q . && echo hi > f.txt && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm init
  printf '%s\n' "<!-- back2base:overview-begin -->" "old overview" "<!-- back2base:overview-end -->" \
    >> "$HOME/.claude/CLAUDE.md"
  git rev-parse 'HEAD^{tree}' > "$HOME/.claude/.overview-tree-hash"

  . "$HELPER"
  run run_prelaunch_overview
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'repo unchanged'
  [ ! -f "$CLAUDE_INVOKED_MARKER" ]
  grep -q 'old overview' "$HOME/.claude/CLAUDE.md"
}

@test "regenerates when tree hash differs" {
  export BACK2BASE_OVERVIEW=1
  stub_claude 'touch "$CLAUDE_INVOKED_MARKER"; echo "fresh overview"; exit 0'
  export CLAUDE_INVOKED_MARKER="$TEST_TMP/claude-ran"

  REPO_DIR="$TEST_TMP/repo"
  mkdir -p "$REPO_DIR" && cd "$REPO_DIR"
  git init -q . && echo hi > f.txt && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm init
  printf '%s\n' "<!-- back2base:overview-begin -->" "old overview" "<!-- back2base:overview-end -->" \
    >> "$HOME/.claude/CLAUDE.md"
  echo "stale-hash-value" > "$HOME/.claude/.overview-tree-hash"

  . "$HELPER"
  run run_prelaunch_overview
  [ "$status" -eq 0 ]
  [ -f "$CLAUDE_INVOKED_MARKER" ]
  grep -q 'fresh overview' "$HOME/.claude/CLAUDE.md"
  # Hash file refreshed to the current tree
  [ "$(cat "$HOME/.claude/.overview-tree-hash")" = "$(git rev-parse 'HEAD^{tree}')" ]
}

@test "regenerates when markers absent even if hash matches" {
  export BACK2BASE_OVERVIEW=1
  stub_claude 'touch "$CLAUDE_INVOKED_MARKER"; echo "fresh overview"; exit 0'
  export CLAUDE_INVOKED_MARKER="$TEST_TMP/claude-ran"

  REPO_DIR="$TEST_TMP/repo"
  mkdir -p "$REPO_DIR" && cd "$REPO_DIR"
  git init -q . && echo hi > f.txt && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm init
  # Matching hash but NO markers in CLAUDE.md (e.g. file was reset)
  git rev-parse 'HEAD^{tree}' > "$HOME/.claude/.overview-tree-hash"

  . "$HELPER"
  run run_prelaunch_overview
  [ "$status" -eq 0 ]
  [ -f "$CLAUDE_INVOKED_MARKER" ]
  grep -q 'fresh overview' "$HOME/.claude/CLAUDE.md"
}

@test "missing claude binary skips gracefully" {
  export BACK2BASE_OVERVIEW=1
  rm -f "$STUB_BIN/claude"
  # Restrict PATH so no real `claude` binary leaks in from the host environment.
  export PATH="$STUB_BIN:/usr/local/bin:/usr/bin:/bin"

  . "$HELPER"
  run run_prelaunch_overview
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'overview skipped: claude CLI not found'
}
