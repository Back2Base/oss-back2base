#!/usr/bin/env python3
"""Schema-versioned migrator for ~/.claude/settings.json.

Invoked from entrypoint.sh on every container start. Reads the top-level
`_back2base_schema` field (default 0 — pre-versioning files are treated as
schema 0), runs every numbered migration whose number is greater than the
current schema, and stamps the new schema to the highest applied number.

Idempotent: a file already at or above CURRENT_SCHEMA is left alone (mtime
preserved). Tolerant of missing or malformed files: bad input never blocks
container startup, so the script silently exits 0 in those cases.

Adding a migration: append a new (number, callable) entry to MIGRATIONS,
bump CURRENT_SCHEMA, and bump _back2base_schema in defaults/settings.json
so freshly-seeded configs skip the migrations.
"""

import json
import pathlib
import sys


# ── Migrations ──────────────────────────────────────────────────────────────

# The back2base statusLine command. claude-hud (vendored at
# /opt/back2base/claude-hud) renders the HUD; statusline-extra.sh feeds the
# back2base namespace segment via --extra-cmd. COLUMNS is exported because the
# container TTY may not set it and claude-hud uses it for width.
STATUSLINE_COMMAND = (
    "bash -c 'export COLUMNS=\"${COLUMNS:-120}\"; "
    "exec node /opt/back2base/claude-hud/index.js "
    "--extra-cmd /opt/back2base/statusline-extra.sh'"
)

# The legacy hand-rolled renderer, replaced by claude-hud in schema 5. Used by
# migrate_5 to detect an unmodified back2base statusLine worth upgrading.
LEGACY_STATUSLINE_COMMAND = "/opt/back2base/statusline.sh"


def migrate_1_envelope_hooks(d):
    """Wrap bare {type:"command",...} hook entries in {matcher,hooks} envelope.

    Claude Code now requires hooks under hooks.<event>[i] to use the
    matcher+hooks shape. Older settings.json files have bare command dicts.
    """
    hooks = d.get("hooks")
    if not isinstance(hooks, dict):
        return False
    changed = False
    for event, arr in list(hooks.items()):
        if not isinstance(arr, list):
            continue
        new = []
        for entry in arr:
            if (
                isinstance(entry, dict)
                and entry.get("type") == "command"
                and "hooks" not in entry
            ):
                new.append({"matcher": "", "hooks": [entry]})
                changed = True
            else:
                new.append(entry)
        hooks[event] = new
    return changed


def migrate_2_prune_defunct_sessionstart(d):
    """Drop registrations of /opt/back2base/memory-sessionstart-hook.sh.

    The script was removed in v0.19.21 (the local memory dir is now a
    write-only cache; recall is the read path). Older settings.json files
    still register it, which surfaces a non-blocking error on every Claude
    Code session start.
    """
    hooks = d.get("hooks")
    if not isinstance(hooks, dict) or "SessionStart" not in hooks:
        return False
    arr = hooks.get("SessionStart")
    if not isinstance(arr, list):
        return False
    defunct = "/opt/back2base/memory-sessionstart-hook.sh"

    def is_defunct(group):
        if not isinstance(group, dict):
            return False
        inner = group.get("hooks") or []
        if not isinstance(inner, list):
            return False
        return any(
            isinstance(h, dict) and h.get("command") == defunct for h in inner
        )

    new_arr = [g for g in arr if not is_defunct(g)]
    if len(new_arr) == len(arr):
        return False
    if new_arr:
        hooks["SessionStart"] = new_arr
    else:
        hooks.pop("SessionStart", None)
    return True


def migrate_3_add_statusline(d):
    """Insert the back2base statusLine block if the user hasn't set one.

    Defensive: if the user has manually customized statusLine to point at a
    different script, leave it alone. Only an absent or empty/falsy key gets
    populated.
    """
    if d.get("statusLine"):
        return False
    d["statusLine"] = {
        "type": "command",
        "command": STATUSLINE_COMMAND,
        "padding": 0,
    }
    return True


def migrate_4_strip_hooks_block(d):
    """Drop the `hooks` key — render-hooks.py owns it from schema 4 on.

    The renderer rebuilds the block from defaults/hooks.json on every
    container start, so any previously-baked content is discarded.
    Returns True iff the key was present so the migrator logs it.
    """
    if "hooks" not in d:
        return False
    del d["hooks"]
    return True


def migrate_5_statusline_to_claude_hud(d):
    """Repoint an unmodified back2base statusLine at vendored claude-hud.

    Only rewrites a statusLine still pointing at the legacy renderer
    (/opt/back2base/statusline.sh). A user who customized the command to
    something else is left alone — same defensive posture as migrate_3.
    """
    sl = d.get("statusLine")
    if not isinstance(sl, dict):
        return False
    if sl.get("command") != LEGACY_STATUSLINE_COMMAND:
        return False
    sl["command"] = STATUSLINE_COMMAND
    return True


# Registry: (number, callable). Numbers must be strictly increasing. Each
# callable mutates the dict in place and returns True if it changed anything
# (return value is informational; presence in the registry is what matters).
MIGRATIONS = [
    (1, migrate_1_envelope_hooks),
    (2, migrate_2_prune_defunct_sessionstart),
    (3, migrate_3_add_statusline),
    (4, migrate_4_strip_hooks_block),
    (5, migrate_5_statusline_to_claude_hud),
]
CURRENT_SCHEMA = max(n for n, _ in MIGRATIONS)


# ── Driver ──────────────────────────────────────────────────────────────────


MIGRATION_LOG = {
    1: ":: settings.json: migrated hooks to matcher+hooks envelope",
    2: ":: settings.json: pruned defunct SessionStart prefetch hook",
    3: ":: settings.json: seeded statusLine block",
    4: ":: settings.json: stripped hooks block (renderer now owns it)",
    5: ":: settings.json: repointed statusLine at claude-hud",
}


def main(path):
    p = pathlib.Path(path)
    if not p.exists():
        return 0
    try:
        original = p.read_text()
        d = json.loads(original)
    except Exception:
        # Malformed JSON or unreadable file: never block startup.
        return 0
    if not isinstance(d, dict):
        return 0

    schema = d.get("_back2base_schema", 0)
    if not isinstance(schema, int):
        schema = 0

    if schema >= CURRENT_SCHEMA:
        # Already current (or ahead — don't downgrade). Leave file alone so
        # mtime is preserved.
        return 0

    applied = []
    for num, fn in MIGRATIONS:
        if num <= schema:
            continue
        if fn(d):
            applied.append(num)

    d["_back2base_schema"] = CURRENT_SCHEMA
    p.write_text(json.dumps(d, indent=2) + "\n")
    for num in applied:
        msg = MIGRATION_LOG.get(num)
        if msg:
            print(msg)
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(0)
    sys.exit(main(sys.argv[1]))
