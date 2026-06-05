package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// saveOAuthToken upserts the Claude OAuth token into the env file at
// cfg.EnvFile, preserving every other line. If an Anthropic API key is also
// present, it writes a warning to w (it does NOT remove the key). Progress and
// warning messages are written to w so callers (and tests) control the sink.
func saveOAuthToken(cfg cbConfig, token string, w io.Writer) error {
	const key = "BACK2BASE_CLAUDE_CODE_OAUTH_TOKEN"

	// Fresh install: write a file containing just this line (no leading blank).
	if _, err := os.Stat(cfg.EnvFile); errors.Is(err, os.ErrNotExist) {
		if err := os.MkdirAll(filepath.Dir(cfg.EnvFile), 0755); err != nil {
			return fmt.Errorf("create config dir: %w", err)
		}
		if err := os.WriteFile(cfg.EnvFile, []byte(key+"="+token+"\n"), 0644); err != nil {
			return fmt.Errorf("create env file: %w", err)
		}
		fmt.Fprintf(w, ":: OAuth token saved to %s\n", cfg.EnvFile)
		return nil
	} else if err != nil {
		return fmt.Errorf("stat env file: %w", err)
	}

	if err := setEnvValue(cfg.EnvFile, key, token); err != nil {
		return fmt.Errorf("save OAuth token: %w", err)
	}

	if v := readEnvFile(cfg.EnvFile)["BACK2BASE_ANTHROPIC_API_KEY"]; v != "" {
		fmt.Fprintf(w, ":: warning: BACK2BASE_ANTHROPIC_API_KEY is also set in %s\n", cfg.EnvFile)
		fmt.Fprintln(w, "   Both credentials are now present; comment out whichever you don't want.")
	}

	fmt.Fprintf(w, ":: OAuth token saved to %s\n", cfg.EnvFile)
	return nil
}
