#!/bin/bash
# claude-hud --extra-cmd helper for oss-back2base.
#
# claude-hud (vendored at /opt/back2base/claude-hud) renders the HUD; this adds
# the one segment it can't know — the memory namespace — as a JSON object on
# stdout: {"label":"ns:<namespace>"}. Omitted when no namespace is set. (The
# hosted build's auth/pwr segments don't exist in OSS.)

set +e

label=""
if [ -n "${MEMORY_NAMESPACE:-}" ]; then
  label="ns:${MEMORY_NAMESPACE}"
fi

# claude-hud truncates past 50 chars anyway; cap here to keep this self-contained.
if [ "${#label}" -gt 50 ]; then
  label="${label:0:49}…"
fi

label=${label//\\/\\\\}
label=${label//\"/\\\"}
printf '{"label":"%s"}\n' "$label"
