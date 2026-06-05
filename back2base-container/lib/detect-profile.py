#!/usr/bin/env python3
"""Auto-detect an MCP profile from a workspace fingerprint.

Scans --workspace (root + one level deep) for language/tooling signals and
maps each to a profile name defined in --profiles (profiles.json). Prints the
UNION of every matched profile's servers with the always-on `core` set, one
server name per line, in profiles.json declaration order. Zero matches prints
the `general` profile's set.

Tolerant by construction: any error prints the best available fallback
(general, else core, else nothing-but-exit-0) with a stderr warning, so
detection never blocks container startup.

Usage:
  detect-profile.py --workspace /workspace --profiles .../profiles.json
"""

import argparse
import json
import pathlib
import sys

# profile -> (exact filenames, file suffixes, directory names).
# Order is for deterministic stderr summaries only; union is order-independent.
SIGNALS = [
    ("go",            {"go.mod"},                                            {".go"},           set()),
    ("frontend",      {"package.json", "tsconfig.json"},                     {".ts", ".tsx"},   set()),
    ("python",        {"requirements.txt", "pyproject.toml", "setup.py", "Pipfile"}, {".py"},   set()),
    ("infra",         {"Chart.yaml", "kustomization.yaml"},                  {".tf", ".tfvars"}, {".terraform"}),
    ("documentation", {"mkdocs.yml", "docusaurus.config.js", "antora.yml"},  set(),             set()),
]

# Directories we never descend into when scanning one level deep. We still
# match these names as signal directories (e.g. .terraform) before deciding
# not to descend.
SKIP_DESCEND = {".git", "node_modules", "vendor", "dist", "build",
                "target", ".venv", "__pycache__", ".terraform"}


def _scan_entries(d, exact, suffix, dirname, matched):
    """Match the immediate children of directory `d`."""
    try:
        entries = list(d.iterdir())
    except OSError:
        return
    for e in entries:
        name = e.name
        try:
            is_dir = e.is_dir()
        except OSError:
            is_dir = False
        if is_dir:
            if name in dirname:
                matched.update(dirname[name])
        else:
            if name in exact:
                matched.update(exact[name])
            dot = name.rfind(".")
            # dot > 0 (not != -1) intentionally skips bare dotfiles like ".babelrc" / ".go" that have no extension beyond the leading dot
            if dot > 0:
                suf = name[dot:]
                if suf in suffix:
                    matched.update(suffix[suf])


def detect(workspace):
    """Return the set of matched profile names for `workspace`."""
    exact, suffix, dirname = {}, {}, {}
    for prof, files, sufs, dirs in SIGNALS:
        for f in files:
            exact.setdefault(f, set()).add(prof)
        for s in sufs:
            suffix.setdefault(s, set()).add(prof)
        for dn in dirs:
            dirname.setdefault(dn, set()).add(prof)

    matched = set()
    # Root level.
    _scan_entries(workspace, exact, suffix, dirname, matched)
    # One level deep (skip noisy/large dirs).
    try:
        children = list(workspace.iterdir())
    except OSError:
        children = []
    for child in children:
        try:
            if child.is_dir() and child.name not in SKIP_DESCEND:
                _scan_entries(child, exact, suffix, dirname, matched)
        except OSError:
            continue
    return matched


def resolve(matched, profiles):
    """Union core + matched profiles' servers, deduped, declaration order."""
    core = profiles.get("core", []) or []
    profs = profiles.get("profiles", {}) or {}
    servers = []
    for s in core:
        if s not in servers:
            servers.append(s)
    if matched:
        for name, spec in profs.items():  # declaration order
            if name in matched:
                for s in (spec.get("servers", []) or []):
                    if s not in servers:
                        servers.append(s)
    else:
        general = profs.get("general", {}) or {}
        for s in (general.get("servers", []) or []):
            if s not in servers:
                servers.append(s)
    return servers


def main(argv):
    parser = argparse.ArgumentParser(description="Auto-detect MCP profile")
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--profiles", required=True)
    args = parser.parse_args(argv[1:])

    try:
        with open(args.profiles, encoding="utf-8") as f:
            profiles = json.load(f)
    except (OSError, ValueError) as exc:
        print(f":: ⚠ detect-profile: unreadable profiles.json ({exc}); "
              "using core fallback", file=sys.stderr)
        # Minimal safe fallback: filesystem,git,memory.
        for s in ("filesystem", "git", "memory"):
            print(s)
        return 0

    workspace = pathlib.Path(args.workspace)
    if not workspace.is_dir():
        print(f":: ⚠ detect-profile: workspace missing ({workspace}); "
              "using general set", file=sys.stderr)
        matched = set()
    else:
        try:
            matched = detect(workspace)
        except Exception as exc:  # never block boot
            print(f":: ⚠ detect-profile: scan failed ({exc}); "
                  "using general set", file=sys.stderr)
            matched = set()

    servers = resolve(matched, profiles)
    for s in servers:
        print(s)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
