# oss-back2base

> A sandboxed [Claude Code](https://docs.anthropic.com/en/docs/claude-code) container, driven by a single Go CLI. Claude runs inside Docker behind an outbound firewall; your host stays clean.

`oss-back2base` is a Go (Cobra) command-line tool that wraps Docker Compose to launch a containerized Claude Code session. Each session ships with a curated MCP-server registry, named tool profiles, an outbound iptables firewall, and persistent local state — all defined in plain JSON / Markdown files you can edit. **macOS is the primary supported platform** (Linux works too).

## About back2base

This repository is the open-source build of **[back2base](https://back2base.net)** — the de-clouded fork of the hosted product. It is everything you need to run a sandboxed Claude Code session **locally, with no account**:

- the Go CLI,
- the Docker container payload (Dockerfile, compose, entrypoint, firewall),
- the starter configs for MCP servers, skills, and slash commands.

It deliberately leaves out the hosted pieces. There is **no Auth0 sign-in, no Cloudflare Workers / proxy gateway, and no cloud memory sync** — persistence here is local bind mounts only.

| Feature | `oss-back2base` (this repo) | [back2base.net](https://back2base.net) |
|---|:---:|:---:|
| Containerized Claude Code | yes | yes |
| MCP server registry + named profiles | yes | yes |
| Outbound iptables firewall | yes | yes |
| Starter skills + slash commands | yes | yes |
| Local plans/memories persistence (bind mount) | yes | yes |
| Proxy / API gateway | no | yes |
| Cross-device config sync | no | yes |
| Cloud (durable-object / R2) memory sync | no | yes |
| Auth0 sign-in | no | yes |

## Requirements

- **macOS** (primary target) or Linux.
- **Docker** — Docker Desktop, Colima, or any compatible daemon.
- An **Anthropic credential** — either a Claude Code OAuth token (uses your Claude subscription) or an `ANTHROPIC_API_KEY`.

## Install

### Homebrew (macOS / Linux)

```bash
brew install back2base/back2base/oss-back2base
```

### Debian / Ubuntu (`.deb`)

Download `oss-back2base_<version>_linux_<arch>.deb` from the [Releases page](https://github.com/back2base/oss-back2base/releases) and install it:

```bash
sudo dpkg -i oss-back2base_*_linux_amd64.deb
```

### Pre-built binary

Grab the matching `oss-back2base_<os>_<arch>.tar.gz` from the [Releases page](https://github.com/back2base/oss-back2base/releases), extract the `oss-back2base` binary, and move it onto your `$PATH`.

### From source

Requires Go 1.23+.

```bash
go build -o oss-back2base .
# or, with version metadata stamped in:
make build
```

## Quickstart

```bash
# 1. Run first-time setup. This extracts the container payload to
#    ~/.local/share/back2base, seeds ~/.config/back2base/env from the
#    template, and builds the image (~500 MB base-image pull + a thin
#    local layer).
oss-back2base install

# 2. Authenticate. Easiest path — runs `claude setup-token` for you and
#    saves the OAuth token into ~/.config/back2base/env:
oss-back2base login

#    …or set a credential by hand instead:
#      BACK2BASE_CLAUDE_CODE_OAUTH_TOKEN=  (from `claude setup-token`)
#      BACK2BASE_ANTHROPIC_API_KEY=        (from https://console.anthropic.com)
#    $EDITOR ~/.config/back2base/env

# 3. Launch Claude Code in the current directory.
oss-back2base
```

`oss-back2base` with no subcommand launches a Claude Code session, mounting your current working directory as `/workspace` inside the container. Run it from inside the repo you want to work on. On an interactive launch it asks which [tool profile](#profiles-and-models) to load.

Other common entry points:

```bash
oss-back2base shell        # drop into a container shell instead of Claude
oss-back2base doctor       # health-check Docker, the payload, and your config
oss-back2base status       # show container / volume status
oss-back2base mcp list     # list the MCP servers configured for this namespace
oss-back2base resume       # resume the most recent session in this workspace
```

## How it works

**Container.** Each launch runs `docker compose run --rm` against a payload extracted to `~/.local/share/back2base`. The image is built `FROM` a prebuilt base (`ramseymcgrath/back2base-base:latest`) that carries the toolchains and MCP servers; the local layer adds your defaults. Claude Code runs as the unprivileged `node` user, started with `--permission-mode bypassPermissions` *inside* the sandbox, so the firewall and container boundary — not interactive prompts — are what contain it.

**Firewall.** The container is granted `NET_ADMIN` and applies an outbound iptables allowlist on startup (see [`back2base-container/init-firewall.sh`](back2base-container/init-firewall.sh)). A refresh daemon re-resolves the allowed domains periodically so long sessions survive IP rotation. Set `DISABLE_FIREWALL=1` to allow all outbound traffic (useful for debugging).

**MCP servers + profiles.** The registry lives in `~/.config/back2base/state/.mcp.json`. A *profile* names a subset of those servers (plus an optional model pin) so you only load the tools a given task needs. Profiles are defined in [`back2base-container/defaults/profiles.json`](back2base-container/defaults/profiles.json).

**Persistent state.** Your `~/.claude` directory inside the container is a bind mount of `~/.config/back2base/state/` on the host — MCP registry, settings, skills, slash commands, session history. It is seeded from image-baked defaults on first launch, then it is yours to edit. The in-session statusline is [claude-hud](https://github.com/jarrodwatts/claude-hud) (vendored, MIT).

**Host credentials.** When present on the host, `~/.ssh` and `~/.gitconfig` mount read-only for git, and `~/.aws`, `~/.kube`, and `~/.config/gh` are bind-mounted (per-run, only if they exist) so those CLIs work inside the container. The Docker socket is mounted so Claude can spawn docker-based MCP servers.

## Configuration

Two on-disk locations matter, both under `~/.config/back2base/`:

| Path | What it holds | How to edit |
|---|---|---|
| `~/.config/back2base/env` | Auth tokens, model / profile overrides, MCP-server tokens, firewall toggle, data dir. | Edit directly. Re-sourced on every launch. See [`back2base-container/defaults/env.example`](back2base-container/defaults/env.example) for the full catalog. |
| `~/.config/back2base/state/` | The container's `~/.claude`: `.mcp.json`, `settings.json`, `skills/`, `commands/`, session history. | Edit directly. Seeded from image defaults on first launch, then user-owned. |

### Environment variables

All variables are read from `~/.config/back2base/env` (or your shell, for process-env overrides). Auth values are read **only** under the `BACK2BASE_` prefix — the CLI strips the prefix and forwards the canonical name into the container, so it never accidentally inherits a bare `ANTHROPIC_API_KEY` you set for something else.

| Variable | Purpose |
|---|---|
| `BACK2BASE_CLAUDE_CODE_OAUTH_TOKEN` | Claude Code OAuth token (uses your subscription). From `claude setup-token`. |
| `BACK2BASE_ANTHROPIC_API_KEY` | Anthropic API key (pay-as-you-go). Alternative to the OAuth token. |
| `BACK2BASE_ANTHROPIC_AUTH_TOKEN` | Custom auth bearer token for an Anthropic-compatible endpoint. |
| `BACK2BASE_ANTHROPIC_BASE_URL` | Custom Anthropic-compatible base URL (e.g. a self-hosted proxy). |
| `BACK2BASE_PROFILE` | MCP profile to load. Defaults to `auto` (fingerprint the workspace). Set a name (`full`, `go`, `frontend`, `infra`, `general`, …) to pin one; `last` resolves to the last profile used in this namespace. |
| `BACK2BASE_MODEL` | Force a specific Claude model alias. Unset = the selected profile's pinned model (default `claude-opus-4-8[1m]`). |
| `BACK2BASE_DATA_DIR` | Host directory for persistent plans + memories. See [below](#persisting-plans-and-memories). |
| `BACK2BASE_MANAGED_SETTINGS_DIR` | Override the host path probed for [enterprise managed policy](#enterprise-managed-policy). |
| `DISABLE_FIREWALL` | Set to `1` to disable the outbound firewall (allow all). |
| `BACK2BASE_HOME` | Override the payload dir (default `~/.local/share/back2base`). |
| `BACK2BASE_CONFIG` | Override the config/state parent dir (default `~/.config/back2base`). |
| `BACK2BASE_BASE_IMAGE` | Override the base image (default `ramseymcgrath/back2base-base:latest`). |
| `REPO_PATH` | Pin a fixed repo to mount as `/workspace` instead of the CWD. |
| `TZ` | Container timezone. |

Optional per-tool MCP credentials (`GITHUB_TOKEN`, `DD_API_KEY` / `DD_APPLICATION_KEY`, `CONTEXT7_API_KEY`, `BRAVE_API_KEY`, `TFC_TOKEN`, `BUILDKITE_API_TOKEN`, `CF_AIG_TOKEN`, `CUSTOM_API_HEADER`, `AWS_PROFILE` / `AWS_REGION`) are forwarded to the matching server when set. The full annotated list lives in [`env.example`](back2base-container/defaults/env.example).

### Profiles and models

A profile narrows which MCP servers (and which model) a session loads. The default is **`auto`**, which fingerprints your workspace at startup (e.g. `go.mod` → Go tools, `package.json` → frontend tools, `*.tf` → infra) and loads only the matching servers — keeping the cached tool prefix small and turns fast. Override per run:

```bash
oss-back2base                     # default → auto-detect from the workspace
oss-back2base --profile go        # force the Go server set
oss-back2base --profile frontend  # web / TypeScript
oss-back2base --profile full      # every server (max capability, highest token cost)
oss-back2base --profile minimal   # filesystem + git only
```

Built-in profiles: `auto` (default), `full`, `go`, `python`, `frontend`, `infra`, `research`, `documentation`, `general` (lean fallback when nothing is detected), `minimal`. Every profile includes the `core` servers (`filesystem`, `git`). The auto-detected set is the **union** of every matched profile, so polyglot repos still get what they need; an empty/unknown workspace falls back to `general`. The tool list is locked at session start (don't add/remove servers mid-session — it breaks the prompt cache). The default model pinned by the profiles is `claude-opus-4-8[1m]`; override per-run with `BACK2BASE_MODEL`. Edit or add profiles in [`back2base-container/defaults/profiles.json`](back2base-container/defaults/profiles.json).

### Adding or removing MCP servers

Edit `~/.config/back2base/state/.mcp.json` — plain JSON. Add your own servers, remove the ones you don't want, and drop any required token into `~/.config/back2base/env`. Use `oss-back2base mcp list` to see the resolved set, and `oss-back2base mcp test` to probe HTTP-transport servers for reachability.

### Editing skills and slash commands

`~/.config/back2base/state/skills/` and `~/.config/back2base/state/commands/` are seeded from the image defaults on first launch, then they're yours — add, remove, or rewrite anything. The defaults are starting points, not a contract.

### Persisting plans and memories

By default, memories live under the back2base state dir and are cleared at each session start. To persist them somewhere you control, set:

```bash
BACK2BASE_DATA_DIR=~/back2base-data
```

in `~/.config/back2base/env` (or your shell). On launch, `oss-back2base` creates `plans/` and `memories/` subfolders under that directory and bind-mounts them at `~/.back2base/plans` and `~/.back2base/memories` inside the container. The memory tool reads and writes the mounted `memories/` folder directly, so memories persist across sessions and live somewhere you own. This is local-only: OSS has no cloud sync, so it's volumes-only.

### Enterprise managed policy

If your organization deploys [Claude Code managed settings](https://code.claude.com/docs/en/server-managed-settings) (admin `permissions.allow` / `permissions.deny`, hooks, env vars, a permission-rules lock, or a centrally managed `CLAUDE.md`), `oss-back2base` honors that policy inside the container.

On every launch the CLI probes the platform-standard host directory and bind-mounts any artifacts that exist, read-only, at the canonical Linux paths Claude Code reads:

| Host path (probed) | Container path (mounted, read-only) |
|---|---|
| `/Library/Application Support/ClaudeCode/managed-settings.json` (macOS)<br>`/etc/claude-code/managed-settings.json` (Linux) | `/etc/claude-code/managed-settings.json` |
| `…/managed-settings.d/` | `/etc/claude-code/managed-settings.d/` |
| `…/CLAUDE.md` | `/etc/claude-code/CLAUDE.md` |

Only artifacts that actually exist on the host are mounted. Set `BACK2BASE_MANAGED_SETTINGS_DIR=<path>` to probe a non-standard host directory (useful for testing or air-gapped installs). Verify the wiring with `oss-back2base doctor`.

## Commands

| Command | What it does |
|---|---|
| `oss-back2base` *(no subcommand)* | Launch a Claude Code session in the current directory. |
| `install` | First-time setup: check prereqs, seed the env file, build the image. |
| `login` | Run `claude setup-token` in a throwaway container and save the OAuth token to `~/.config/back2base/env`. |
| `build` | Build the container image. |
| `rebuild` | Full rebuild with no cache. |
| `shell` | Drop into a container shell instead of Claude. |
| `resume [sessionId]` | Resume the most recent (or named) session in this workspace. |
| `mcp list` / `mcp test` | List configured MCP servers / probe HTTP servers for reachability. |
| `doctor` | Run health checks across Docker, payload, and config (`--json` for machine output). |
| `status` | Show container / volume status. |
| `clean` | Remove this project's containers and built image. |
| `prune` | Remove old base/container images that no longer match this binary (`--dry-run`, `--keep N`). |
| `wipe-images` | Remove ALL oss-back2base containers and images. |
| `update` | Update the `oss-back2base` binary to the latest release. |
| `version` | Print version information. |

Useful root flags: `--profile <name>` (MCP profile), `-p/--prompt` (one-shot prompt, then exit), `-d/--dir <path>` (mount an extra directory at `/repos/<name>`, repeatable), `-r/--repo` (override the repo mount), `--namespace <name>` (memory namespace), `--overview` / `--no-overview` (pre-launch repo overview), `-y/--yes` (skip confirmations), `--no-update-check`. The model is chosen by the profile or `BACK2BASE_MODEL` — there is no `--model` flag. Run `oss-back2base <command> --help` for full details.

## Development

```bash
go build ./...                          # build
go test ./...                           # run the Go unit tests
make build                              # build with version metadata
make lint                               # go vet
bats back2base-container/test/          # container-side bats tests (run from repo root)
```

### Repository layout

- `*.go` — the CLI source.
- `back2base-container/` — the Docker image payload (Dockerfile, `docker-compose.yml`, `entrypoint.sh`, `init-firewall.sh`, `defaults/`, `skills/`, `commands/`, `lib/`). Extracted to `~/.local/share/back2base` on first run.
- `back2base-container/test/` — bats tests for the container scripts.
- `.github/workflows/` — CI and the GoReleaser-driven release pipeline.

## License

MIT. See [LICENSE](LICENSE).

The upstream hosted product at [back2base.net](https://back2base.net) is a separate offering and is not covered by this license.
