## Profile: general (auto)

No language-specific signal was detected in this workspace, so a lean,
general-purpose MCP set is loaded: filesystem, git, plus context7 (library
docs), fetch (HTTP), and github. This keeps the cached tool prefix small and
your turns fast.

If this repo is actually Go / TypeScript / Python / infra and you want the
matching tool set, restart with `BACK2BASE_PROFILE=<go|frontend|python|infra>`,
or `BACK2BASE_PROFILE=full` for everything. Do not try to add MCP servers
mid-session — the tool list is locked at session start by design.
