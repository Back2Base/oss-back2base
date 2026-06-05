package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"
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

var loginCmd = &cobra.Command{
	Use:   "login",
	Short: "Link your Claude subscription (runs claude setup-token, saves the OAuth token)",
	Long: `Runs 'claude setup-token' inside a throwaway container and saves the
resulting long-lived OAuth token to ~/.config/back2base/env as
BACK2BASE_CLAUDE_CODE_OAUTH_TOKEN. This bills your Claude Pro/Max/Team
subscription instead of an API key.

OSS has no Auth0 / cloud step, so this is the only sign-in path.`,
	Args: cobra.NoArgs,
	RunE: runLogin,
}

func init() {
	rootCmd.AddCommand(loginCmd)
}

// runLogin starts a throwaway container running `claude setup-token`, has the
// user paste the resulting OAuth token, and saves it to the local env file.
func runLogin(cmd *cobra.Command, args []string) error {
	s, err := ensureReady()
	if err != nil {
		return err
	}
	if err := ensureBaseImage(resolveBaseImage()); err != nil {
		return err
	}

	composeArgs := baseComposeArgs(s.cfg)
	composeArgs = append(composeArgs, "run", "--rm",
		"-e", "ANTHROPIC_BASE_URL=",
		"claude", "claude", "setup-token")
	if err := composeRun(composeArgs); err != nil {
		return err
	}

	fmt.Println()
	fmt.Print("Paste the token here: ")
	reader := bufio.NewReader(os.Stdin)
	token, err := reader.ReadString('\n')
	if err != nil && err != io.EOF {
		return fmt.Errorf("read token: %w", err)
	}
	token = strings.TrimSpace(token)
	if token == "" {
		return fmt.Errorf("no token provided")
	}

	return saveOAuthToken(s.cfg, token, os.Stderr)
}
