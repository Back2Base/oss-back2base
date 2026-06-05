#!/usr/bin/env bats

# Tests for seed_agents_if_missing — seeds ~/.claude/agents from image
# defaults when the target is absent/empty; idempotent otherwise.

setup() {
  TEST_TMP="$(mktemp -d "${BATS_TMPDIR}/seed-agents.XXXXXX")"
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$TEST_TMP/home"; mkdir -p "$HOME/.claude"
  export DEFAULTS="$TEST_TMP/opt/defaults/agents"; mkdir -p "$DEFAULTS/claudekit"
  echo "agent body" > "$DEFAULTS/claudekit/example.md"
  FN="$TEST_TMP/fn.sh"
  awk '/^seed_agents_if_missing\(\) \{/,/^\}/' "$REPO_ROOT/entrypoint.sh" > "$FN"
}

teardown() { rm -rf "$TEST_TMP"; }

@test "seeds agents when target is missing" {
  run bash -c "source '$FN'; \
    HOME='$HOME' B2B_DEFAULTS_AGENTS='$DEFAULTS' seed_agents_if_missing; \
    cat '$HOME/.claude/agents/claudekit/example.md'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"agent body"* ]]
}

@test "is idempotent / does not clobber a populated target" {
  mkdir -p "$HOME/.claude/agents"; echo "user agent" > "$HOME/.claude/agents/mine.md"
  run bash -c "source '$FN'; \
    HOME='$HOME' B2B_DEFAULTS_AGENTS='$DEFAULTS' seed_agents_if_missing; \
    cat '$HOME/.claude/agents/mine.md'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"user agent"* ]]
}
