#!/usr/bin/env bats
# Tests for lib/memory-align.sh: b2b_align_memory_dir selects the canonical
# memory store and symlinks Claude Code's auto-memory path to it.

setup() {
  REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  . "$REPO_DIR/lib/memory-align.sh"
  TMP="$(mktemp -d)"
  export HOME="$TMP/home"; mkdir -p "$HOME"
  mkdir -p "$TMP/workspace"; cd "$TMP/workspace"
  unset MEMORY_NAMESPACE CLAUDE_PROJECT_DIR BACK2BASE_PLANS_DIR
}
teardown() { rm -rf "$TMP"; }

cc_path() { echo "$HOME/.claude/projects/${PWD//\//-}/memory"; }

@test "mounted: symlinks Claude Code memory path to ~/.back2base/memories" {
  mkdir -p "$HOME/.back2base/memories"
  b2b_align_memory_dir
  cc="$(cc_path)"
  [ -L "$cc" ]
  [ "$(readlink "$cc")" = "$HOME/.back2base/memories" ]
}

@test "mounted: does NOT wipe existing memory in the mount" {
  mkdir -p "$HOME/.back2base/memories"
  echo "keep me" > "$HOME/.back2base/memories/MEMORY.md"
  b2b_align_memory_dir
  [ -f "$HOME/.back2base/memories/MEMORY.md" ]
  [ "$(cat "$HOME/.back2base/memories/MEMORY.md")" = "keep me" ]
}

@test "mounted: exports BACK2BASE_PLANS_DIR and creates the plans dir" {
  mkdir -p "$HOME/.back2base/memories"
  b2b_align_memory_dir
  [ "$BACK2BASE_PLANS_DIR" = "$HOME/.back2base/plans" ]
  [ -d "$HOME/.back2base/plans" ]
}

@test "mounted: migrates a pre-existing real memory dir into the mount, then symlinks" {
  mkdir -p "$HOME/.back2base/memories"
  cc="$(cc_path)"; mkdir -p "$cc"; echo "old" > "$cc/old.md"
  b2b_align_memory_dir
  [ -L "$cc" ]
  [ "$(readlink "$cc")" = "$HOME/.back2base/memories" ]
  [ -f "$HOME/.back2base/memories/old.md" ]
}

@test "not mounted + namespace set: symlinks to namespaced dir and wipes stale memory" {
  export MEMORY_NAMESPACE=myrepo
  ns="$HOME/.claude/projects/myrepo/memory"; mkdir -p "$ns"; echo stale > "$ns/stale.md"
  b2b_align_memory_dir
  cc="$(cc_path)"
  [ -L "$cc" ]
  [ "$(readlink "$cc")" = "$ns" ]
  [ ! -f "$ns/stale.md" ]
}

@test "not mounted + no namespace: no-op (no symlink, no plans export)" {
  b2b_align_memory_dir
  [ ! -e "$(cc_path)" ]
  [ -z "${BACK2BASE_PLANS_DIR:-}" ]
}
