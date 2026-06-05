package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// envCfg returns a cbConfig whose EnvFile points at a temp path, optionally
// pre-seeded with the given contents. Pass seed == "" to leave the file absent.
func envCfg(t *testing.T, seed string) cbConfig {
	t.Helper()
	dir := t.TempDir()
	envFile := filepath.Join(dir, "env")
	if seed != "" {
		if err := os.WriteFile(envFile, []byte(seed), 0644); err != nil {
			t.Fatalf("seed env file: %v", err)
		}
	}
	return cbConfig{ConfigDir: dir, EnvFile: envFile}
}

const oauthKey = "BACK2BASE_CLAUDE_CODE_OAUTH_TOKEN"

func TestSaveOAuthTokenMissingFile(t *testing.T) {
	cfg := envCfg(t, "") // file does not exist yet
	var w bytes.Buffer
	if err := saveOAuthToken(cfg, "tok-abc", &w); err != nil {
		t.Fatalf("saveOAuthToken: %v", err)
	}
	got := readEnvFile(cfg.EnvFile)
	if got[oauthKey] != "tok-abc" {
		t.Fatalf("token not saved: got %q", got[oauthKey])
	}
}

func TestSaveOAuthTokenReplacesExisting(t *testing.T) {
	cfg := envCfg(t, oauthKey+"=old-token\n")
	var w bytes.Buffer
	if err := saveOAuthToken(cfg, "new-token", &w); err != nil {
		t.Fatalf("saveOAuthToken: %v", err)
	}
	data, _ := os.ReadFile(cfg.EnvFile)
	if n := strings.Count(string(data), oauthKey+"="); n != 1 {
		t.Fatalf("expected exactly 1 occurrence, got %d in:\n%s", n, data)
	}
	if got := readEnvFile(cfg.EnvFile)[oauthKey]; got != "new-token" {
		t.Fatalf("token not replaced: got %q", got)
	}
}

func TestSaveOAuthTokenRevivesCommentedKey(t *testing.T) {
	cfg := envCfg(t, "# "+oauthKey+"=old-token\n")
	var w bytes.Buffer
	if err := saveOAuthToken(cfg, "new-token", &w); err != nil {
		t.Fatalf("saveOAuthToken: %v", err)
	}
	if got := readEnvFile(cfg.EnvFile)[oauthKey]; got != "new-token" {
		t.Fatalf("commented key not revived: got %q", got)
	}
}

func TestSaveOAuthTokenPreservesOtherLines(t *testing.T) {
	cfg := envCfg(t, "# my config\nBACK2BASE_MODEL=opus\n")
	var w bytes.Buffer
	if err := saveOAuthToken(cfg, "tok", &w); err != nil {
		t.Fatalf("saveOAuthToken: %v", err)
	}
	got := readEnvFile(cfg.EnvFile)
	if got["BACK2BASE_MODEL"] != "opus" {
		t.Fatalf("unrelated var clobbered: %#v", got)
	}
	data, _ := os.ReadFile(cfg.EnvFile)
	if !strings.Contains(string(data), "# my config") {
		t.Fatalf("comment line lost:\n%s", data)
	}
}

func TestSaveOAuthTokenWarnsOnApiKey(t *testing.T) {
	cfg := envCfg(t, "BACK2BASE_ANTHROPIC_API_KEY=sk-123\n")
	var w bytes.Buffer
	if err := saveOAuthToken(cfg, "tok", &w); err != nil {
		t.Fatalf("saveOAuthToken: %v", err)
	}
	if !strings.Contains(w.String(), "BACK2BASE_ANTHROPIC_API_KEY") {
		t.Fatalf("expected API-key warning, got:\n%s", w.String())
	}
}

func TestSaveOAuthTokenNoWarnWithoutApiKey(t *testing.T) {
	cfg := envCfg(t, "")
	var w bytes.Buffer
	if err := saveOAuthToken(cfg, "tok", &w); err != nil {
		t.Fatalf("saveOAuthToken: %v", err)
	}
	if strings.Contains(w.String(), "BACK2BASE_ANTHROPIC_API_KEY") {
		t.Fatalf("unexpected API-key warning:\n%s", w.String())
	}
}
