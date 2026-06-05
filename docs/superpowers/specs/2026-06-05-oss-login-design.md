# Design: `oss-back2base login`

**Date:** 2026-06-05
**Status:** Approved

## Problem

The closed-source `back2base login` runs two sign-in paths: (1) an Auth0 device
flow that mints a back2base service token, and (2) `claude setup-token`, which
mints an Anthropic long-lived OAuth token and uploads it to cloud config.

The OSS fork has no Auth0, no proxy, and no cloud config — so step 1 cannot be
ported. Today OSS users authenticate by manually running `claude setup-token`
and hand-editing `~/.config/back2base/env` to paste
`BACK2BASE_CLAUDE_CODE_OAUTH_TOKEN`.

This feature ports the portable half of the flow: a single `oss-back2base login`
command that runs `claude setup-token` for the user and saves the resulting
token to the local env file — replacing the cloud-config upload with a local
write.

## Decisions

- **Command shape:** `oss-back2base login` (bare, no subcommands). OSS has no
  Auth0 step, so `login` means the Anthropic flow directly.
- **Where `claude setup-token` runs:** in a throwaway container
  (`docker compose run --rm claude claude setup-token`), matching closed-source.
  No host `claude` install required; uses the same Claude version as the image.
- **Write behavior:** upsert `BACK2BASE_CLAUDE_CODE_OAUTH_TOKEN` only, preserving
  all other env-file lines. If `BACK2BASE_ANTHROPIC_API_KEY` is also present,
  leave it and warn that both credentials are now set.

## Architecture

One new file, `login.go`, at the OSS repo root, mirroring closed-source
`login.go` but with the cloud-config upload swapped for a local env-file write.
No new dependencies — it composes existing helpers.

### Command registration

Standard Cobra pattern:

```go
var loginCmd = &cobra.Command{
    Use:   "login",
    Short: "Link your Claude subscription (runs claude setup-token, saves the OAuth token)",
    Args:  cobra.NoArgs,
    RunE:  runLogin,
}

func init() { rootCmd.AddCommand(loginCmd) }
```

### Flow: `runLogin`

1. `s, err := ensureReady()` — ensures dirs exist and seeds the env file, so it
   is writable afterward.
2. `ensureBaseImage(resolveBaseImage())` — guarantees the image is present.
3. Run the throwaway container:
   ```go
   composeArgs := baseComposeArgs(s.cfg)
   composeArgs = append(composeArgs, "run", "--rm",
       "-e", "ANTHROPIC_BASE_URL=",
       "claude", "claude", "setup-token")
   if err := composeRun(composeArgs); err != nil { return err }
   ```
   Claude's own OAuth flow prints the URL; the user completes it in a browser.
4. Prompt `Paste the token here:`, read one line from stdin, `strings.TrimSpace`.
5. If the token is empty, return `fmt.Errorf("no token provided")`.
6. Delegate to `saveOAuthToken(s.cfg, token)`.

### Core helper: `saveOAuthToken(cfg cbConfig, token string) error`

This is the unit-testable core — the container/stdin parts are not unit-testable,
but the file-write + warn logic is, and that is where the real behavior lives.

- Call `setEnvValue(cfg.EnvFile, "BACK2BASE_CLAUDE_CODE_OAUTH_TOKEN", token)`.
  `setEnvValue` (config.go:80) already upserts and revives a commented-out key.
- `setEnvValue` uses `os.ReadFile`, which errors if the file is missing. Since
  `ensureReady` seeds the env file this should not happen, but defensively: if
  the file does not exist, create it with the single line first.
- Read back via `readEnvFile`; if `BACK2BASE_ANTHROPIC_API_KEY` is present and
  non-empty, print a warning to stderr that both credentials are now set and the
  user should comment out whichever they do not want.
- Print `:: OAuth token saved to <cfg.EnvFile>`.

## Data flow

```
user → oss-back2base login
        → ensureReady (seed env file)
        → ensureBaseImage
        → docker compose run --rm claude claude setup-token  (browser OAuth)
        → user pastes token at prompt
        → saveOAuthToken → setEnvValue → ~/.config/back2base/env
                                          BACK2BASE_CLAUDE_CODE_OAUTH_TOKEN=<token>
        → (next launch) compose strips BACK2BASE_ prefix → CLAUDE_CODE_OAUTH_TOKEN in container
```

## Error handling

- Image build / `ensureReady` failures propagate from the existing helpers.
- `composeRun` failure (e.g. setup-token aborted) propagates and stops the flow.
- Empty pasted token → explicit `no token provided` error, nothing written.
- Missing env file in `saveOAuthToken` → create it rather than error.

## Testing

`login_test.go` — table tests for `saveOAuthToken` against a temp env file:

1. Fresh file with no matching key → var is appended.
2. Existing `BACK2BASE_CLAUDE_CODE_OAUTH_TOKEN` → replaced, not duplicated.
3. Commented-out `# BACK2BASE_CLAUDE_CODE_OAUTH_TOKEN=...` → revived (uncommented, updated).
4. `BACK2BASE_ANTHROPIC_API_KEY` present and non-empty → warning emitted.
5. Unrelated lines (comments, other vars) → preserved verbatim.

The container run and stdin prompt in `runLogin` are not unit-tested (they
require Docker and a TTY); they are thin glue over tested helpers.

## Documentation

Update `README.md`: replace the manual "run `claude setup-token` → hand-edit
`~/.config/back2base/env`" setup steps with `oss-back2base login`, keeping the
`ANTHROPIC_API_KEY` path as the documented alternative.

## Out of scope (YAGNI)

- No Auth0 / service-token step.
- No cloud upload (`putEnvVar` / `/api/env`).
- No `login anthropic` subcommand.
- No host-`claude` fallback path.
