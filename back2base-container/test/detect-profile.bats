#!/usr/bin/env bats

# Tests for lib/detect-profile.py — fingerprints a workspace and prints the
# union of matched profiles' MCP servers (or the `general` fallback set).

setup() {
  TEST_TMP="$(mktemp -d "${BATS_TMPDIR}/detect-profile.XXXXXX")"
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  DETECT="$REPO_ROOT/lib/detect-profile.py"
  PROFILES="$REPO_ROOT/defaults/profiles.json"
  WS="$TEST_TMP/ws"
  mkdir -p "$WS"
}

teardown() { rm -rf "$TEST_TMP"; }

run_detect() { run python3 "$DETECT" --workspace "$WS" --profiles "$PROFILES"; }

@test "empty workspace falls back to general set" {
  run_detect
  [ "$status" -eq 0 ]
  # general = core + context7,fetch,github (OSS core has no memory)
  echo "$output" | grep -qx "filesystem"
  echo "$output" | grep -qx "git"
  echo "$output" | grep -qx "context7"
  echo "$output" | grep -qx "fetch"
  echo "$output" | grep -qx "github"
  [ "$(echo "$output" | grep -c .)" -eq 5 ]
}

@test "go.mod selects the go profile servers" {
  touch "$WS/go.mod"
  run_detect
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "godevmcp"     # go-only server
  echo "$output" | grep -qx "sequential-thinking"
  echo "$output" | grep -qx "filesystem"   # core always present
  ! echo "$output" | grep -qx "terraform"  # infra NOT pulled in
}

@test "package.json selects the frontend profile servers" {
  echo '{}' > "$WS/package.json"
  run_detect
  echo "$output" | grep -qx "lsmcp"        # frontend-only server
  ! echo "$output" | grep -qx "godevmcp"
}

@test "a .py file selects the python profile" {
  touch "$WS/app.py"
  run_detect
  echo "$output" | grep -qx "github"
  echo "$output" | grep -qx "sequential-thinking"
  echo "$output" | grep -qx "sqlite"   # sqlite confirms python path (absent from frontend/infra/docs)
}

@test "a .tf file selects the infra profile" {
  touch "$WS/main.tf"
  run_detect
  echo "$output" | grep -qx "terraform"
  echo "$output" | grep -qx "kubernetes"
}

@test "multiple signals union their servers (go + frontend)" {
  touch "$WS/go.mod"
  echo '{}' > "$WS/package.json"
  run_detect
  echo "$output" | grep -qx "godevmcp"     # from go
  echo "$output" | grep -qx "lsmcp"        # from frontend
}

@test "signals one level deep are detected" {
  mkdir -p "$WS/service"
  touch "$WS/service/go.mod"
  run_detect
  echo "$output" | grep -qx "godevmcp"
}

@test "node_modules is not descended into" {
  mkdir -p "$WS/node_modules/leftpad"
  touch "$WS/node_modules/leftpad/index.go"   # stray .go must NOT trigger go
  echo '{}' > "$WS/package.json"
  run_detect
  ! echo "$output" | grep -qx "godevmcp"
}

@test "result is always a subset of full and never empty" {
  # NOTE: assumes profiles.full.servers is a superset of all other profiles' servers.
  # If a new profile adds a server not in full, update full.servers or this test false-fails.
  touch "$WS/go.mod" "$WS/main.tf" "$WS/app.py"
  echo '{}' > "$WS/package.json"
  run_detect
  [ "$(echo "$output" | grep -c .)" -gt 0 ]
  full="$(jq -r '.profiles.full.servers[]' "$PROFILES")"
  while read -r s; do
    [ -z "$s" ] && continue
    echo "$full" | grep -qx "$s" || { echo "server $s not in full"; false; }
  done <<< "$output"
}

@test "malformed profiles.json falls back to general core, exit 0" {
  bad="$TEST_TMP/bad.json"
  echo 'not json' > "$bad"
  run python3 "$DETECT" --workspace "$WS" --profiles "$bad"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "filesystem"
}

@test "missing workspace dir falls back, exit 0" {
  run python3 "$DETECT" --workspace "$TEST_TMP/nope" --profiles "$PROFILES"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "filesystem"
}

@test "output is deterministic across runs" {
  touch "$WS/go.mod"
  a="$(python3 "$DETECT" --workspace "$WS" --profiles "$PROFILES")"
  b="$(python3 "$DETECT" --workspace "$WS" --profiles "$PROFILES")"
  [ "$a" = "$b" ]
}

@test "detect output filters a sample .mcp.json (auto end-to-end)" {
  touch "$WS/go.mod"
  mcp="$TEST_TMP/.mcp.json"
  cat > "$mcp" <<'EOF'
{ "mcpServers": {
    "godevmcp": {"command":"x"}, "terraform": {"command":"x"},
    "filesystem": {"command":"x"}, "git": {"command":"x"},
    "memory": {"command":"x"}, "datadog": {"command":"x"}
} }
EOF
  allowed="$(python3 "$DETECT" --workspace "$WS" --profiles "$PROFILES")"
  out="$(jq --argjson allowed "$(echo "$allowed" | jq -R -s 'split("\n") | map(select(. != ""))')" \
    '{ mcpServers: (.mcpServers | to_entries | map(select(.key as $k | $allowed | index($k))) | sort_by(.key) | from_entries) }' \
    "$mcp")"
  echo "$out" | jq -e '.mcpServers.godevmcp' >/dev/null      # kept (go)
  echo "$out" | jq -e '.mcpServers.filesystem' >/dev/null    # kept (core)
  echo "$out" | jq -e '.mcpServers.terraform // empty' >/dev/null && false || true  # dropped
  echo "$out" | jq -e '.mcpServers.datadog // empty' >/dev/null && false || true    # dropped
}
