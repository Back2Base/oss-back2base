#!/usr/bin/env bash
# Memory-path alignment for the back2base container entrypoint.
#
# Sourced by entrypoint.sh and by test/memory-align.bats. Defines one function,
# b2b_align_memory_dir, which selects the canonical memory store and points
# Claude Code's auto-memory path at it. Reads HOME, PWD, MEMORY_NAMESPACE;
# exports CLAUDE_PROJECT_DIR and (when the bind mount is present)
# BACK2BASE_PLANS_DIR.

# b2b_align_memory_dir picks the canonical memory store and symlinks Claude
# Code's auto-memory path (PWD with '/' -> '-') to it:
#   - BACK2BASE_DATA_DIR mounted ~/.back2base/memories -> use it, never wiped.
#   - else MEMORY_NAMESPACE set -> ~/.claude/projects/<ns>/memory, wiped each
#     session to prevent bleed.
#   - else -> no-op.
b2b_align_memory_dir() {
  local ns_memory_dir=""
  if [ -d "$HOME/.back2base/memories" ]; then
    ns_memory_dir="$HOME/.back2base/memories"
    mkdir -p "$HOME/.back2base/plans"
    export BACK2BASE_PLANS_DIR="$HOME/.back2base/plans"
  elif [ -n "${MEMORY_NAMESPACE:-}" ]; then
    ns_memory_dir="$HOME/.claude/projects/${MEMORY_NAMESPACE}/memory"
    mkdir -p "$ns_memory_dir"
    # Start blank so old session memory doesn't bleed via MEMORY.md autoload.
    if [ -n "$(ls -A "$ns_memory_dir" 2>/dev/null)" ]; then
      rm -rf "${ns_memory_dir:?}"/* "${ns_memory_dir:?}"/.[!.]* 2>/dev/null || true
    fi
  fi

  [ -n "$ns_memory_dir" ] || return 0

  local cwd_dir_name cc_memory_dir
  cwd_dir_name="${PWD//\//-}"
  cc_memory_dir="$HOME/.claude/projects/${cwd_dir_name}/memory"
  export CLAUDE_PROJECT_DIR="$HOME/.claude/projects/${cwd_dir_name}"
  [ "$cc_memory_dir" != "$ns_memory_dir" ] || return 0

  mkdir -p "$(dirname "$cc_memory_dir")"
  if [ -L "$cc_memory_dir" ]; then
    if [ "$(readlink "$cc_memory_dir")" != "$ns_memory_dir" ]; then
      ln -sfn "$ns_memory_dir" "$cc_memory_dir"
    fi
  elif [ -d "$cc_memory_dir" ]; then
    if [ -n "$(ls -A "$cc_memory_dir" 2>/dev/null)" ]; then
      cp -an "$cc_memory_dir"/. "$ns_memory_dir"/ 2>/dev/null || true
    fi
    rm -rf "$cc_memory_dir"
    ln -sfn "$ns_memory_dir" "$cc_memory_dir"
  else
    ln -sfn "$ns_memory_dir" "$cc_memory_dir"
  fi
}
