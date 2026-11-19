#!/usr/bin/env bats
#
# Regression for the v0.38.2 "container exits the moment setup finishes" bug.
#
# Several phase functions ended with a bare verbose guard:
#   [ "${BACK2BASE_VERBOSE:-0}" = "1" ] && echo "..."
# When BACK2BASE_VERBOSE is unset (the normal interactive launch) the test is
# false, the && short-circuits, and the compound command returns 1. As the
# LAST command of a function, that becomes the function's return value. The
# function is dispatched by _phase under the top-level `set -e`, so the call —
# a simple command returning 1 — trips set -e and aborts entrypoint.sh right
# after the previous phase's ✓. The container dies before `exec claude`.
#
# (At the top level `false && echo` is exempt from set -e, which is why the
# bug only manifested through a function call, not the inline guard itself.)
#
# Fix: route all verbose logging through _vlog, which always returns 0, and
# forbid inline verbose guards from creeping back in.

setup() {
  REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  ENTRYPOINT="$REPO_DIR/entrypoint.sh"
}

# Print the definition of a shell function from entrypoint.sh (sed range).
extract_fn() {
  sed -n "/^$1()/,/^}/p" "$ENTRYPOINT"
}

@test "_vlog is defined in entrypoint.sh" {
  run extract_fn _vlog
  [ -n "$output" ]
}

@test "_vlog returns 0 with verbose off (safe as a function's last command)" {
  fn="$(extract_fn _vlog)"
  run bash -c "
    set -e
    unset BACK2BASE_VERBOSE
    $fn
    _vlog ':: some detail'
    echo RC=\$?
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"RC=0"* ]]
}

@test "_vlog still prints when verbose on" {
  fn="$(extract_fn _vlog)"
  run bash -c "
    set -e
    export BACK2BASE_VERBOSE=1
    $fn
    _vlog ':: visible detail'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"visible detail"* ]]
}

@test "_vlog is silent when verbose off" {
  fn="$(extract_fn _vlog)"
  run bash -c "
    set -e
    unset BACK2BASE_VERBOSE
    $fn
    _vlog ':: hidden detail'
    echo DONE
  "
  [ "$status" -eq 0 ]
  [[ "$output" != *"hidden detail"* ]]
  [[ "$output" == *"DONE"* ]]
}

@test "a function ending in _vlog returns 0 under set -e with verbose off" {
  vlog="$(extract_fn _vlog)"
  run bash -c "
    set -e
    unset BACK2BASE_VERBOSE
    $vlog
    some_phase() {
      local x=1
      _vlog ':: tail detail'
    }
    some_phase
    echo SURVIVED
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"SURVIVED"* ]]
}

@test "no inline BACK2BASE_VERBOSE && guards remain (use _vlog instead)" {
  # A bare `[ ... BACK2BASE_VERBOSE ... ] && echo` is the footgun. After the
  # fix every such line must be gone — verbose logging goes through _vlog,
  # which is exit-status-safe in any position.
  # Exclude comment lines (the _vlog doc block intentionally shows the old
  # idiom as the anti-pattern to avoid).
  run grep -nE '^[^#]*\[ "\$\{BACK2BASE_VERBOSE:-0\}" = "1" \][[:space:]]*&&' "$ENTRYPOINT"
  [ -z "$output" ]
}
