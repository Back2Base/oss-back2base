#!/bin/bash
# claude-hud --extra-cmd helper for oss-back2base.
#
# claude-hud (vendored at /opt/back2base/claude-hud) renders the generic
# statusline HUD. This helper supplies the one back2base-specific segment it
# can't know about — the memory namespace — emitting a single JSON object on
# stdout:
#
#   {"label": "ns:<namespace>"}
#
# claude-hud styles + truncates the label itself and strips any ANSI, so we
# emit plain text only. The segment is omitted entirely when no namespace is
# set (a bare "ns:?" carries no information).
#
# OSS note: the hosted build's auth:/pwr: segments are intentionally absent —
# there is no service token and no power-steering daemon in oss-back2base.

set +e

label=""
if [ -n "${MEMORY_NAMESPACE:-}" ]; then
  label="ns:${MEMORY_NAMESPACE}"
fi

# Cap at 50 chars to match claude-hud's own truncation; character-based so
# multibyte glyphs count as one.
if [ "${#label}" -gt 50 ]; then
  label="${label:0:49}…"
fi

# Escape backslashes and double quotes defensively (values here are controlled).
label=${label//\\/\\\\}
label=${label//\"/\\\"}
printf '{"label":"%s"}\n' "$label"
