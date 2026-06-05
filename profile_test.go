package main

import (
	"sort"
	"testing"
	"testing/fstest"
)

func TestLoadProfiles(t *testing.T) {
	testFS := fstest.MapFS{
		"defaults/profiles.json": {Data: []byte(`{
			"core": ["filesystem", "git"],
			"profiles": {
				"full": {"description": "All", "servers": ["fetch", "github"]},
				"minimal": {"description": "Bare", "servers": []}
			}
		}`)},
	}

	cfg, err := loadProfiles(testFS)
	if err != nil {
		t.Fatal(err)
	}
	if len(cfg.Core) != 2 {
		t.Errorf("core = %v, want 2 entries", cfg.Core)
	}
	if len(cfg.Profiles) != 2 {
		t.Errorf("profiles = %d, want 2", len(cfg.Profiles))
	}
}

func TestLoadProfiles_MissingFile(t *testing.T) {
	testFS := fstest.MapFS{}
	_, err := loadProfiles(testFS)
	if err == nil {
		t.Fatal("expected error for missing profiles.json")
	}
}

func TestLoadProfiles_InvalidJSON(t *testing.T) {
	testFS := fstest.MapFS{
		"defaults/profiles.json": {Data: []byte(`{invalid}`)},
	}
	_, err := loadProfiles(testFS)
	if err == nil {
		t.Fatal("expected error for invalid JSON")
	}
}

func TestResolvedServers(t *testing.T) {
	cfg := profilesConfig{
		Core: []string{"filesystem", "git", "memory"},
		Profiles: map[string]profileDef{
			"go":      {Servers: []string{"fetch", "github", "godevmcp"}},
			"minimal": {Servers: []string{}},
		},
	}

	servers, err := cfg.resolvedServers("go")
	if err != nil {
		t.Fatal(err)
	}

	want := []string{"fetch", "filesystem", "git", "github", "godevmcp", "memory"}
	if len(servers) != len(want) {
		t.Fatalf("got %v, want %v", servers, want)
	}
	for i, s := range want {
		if servers[i] != s {
			t.Errorf("servers[%d] = %q, want %q", i, servers[i], s)
		}
	}
}

func TestResolvedServers_Dedup(t *testing.T) {
	cfg := profilesConfig{
		Core: []string{"filesystem", "git"},
		Profiles: map[string]profileDef{
			"full": {Servers: []string{"filesystem", "git", "fetch"}},
		},
	}

	servers, err := cfg.resolvedServers("full")
	if err != nil {
		t.Fatal(err)
	}
	if len(servers) != 3 {
		t.Errorf("got %v, want 3 unique servers", servers)
	}
}

func TestResolvedServers_Minimal(t *testing.T) {
	cfg := profilesConfig{
		Core: []string{"filesystem", "git", "memory"},
		Profiles: map[string]profileDef{
			"minimal": {Servers: []string{}},
		},
	}

	servers, err := cfg.resolvedServers("minimal")
	if err != nil {
		t.Fatal(err)
	}

	want := []string{"filesystem", "git", "memory"}
	sort.Strings(want)
	if len(servers) != len(want) {
		t.Fatalf("got %v, want %v", servers, want)
	}
}

func TestResolvedServers_UnknownProfile(t *testing.T) {
	cfg := profilesConfig{
		Core:     []string{"filesystem"},
		Profiles: map[string]profileDef{},
	}

	_, err := cfg.resolvedServers("nonexistent")
	if err == nil {
		t.Fatal("expected error for unknown profile")
	}
}

func TestProfileNames_Order(t *testing.T) {
	cfg := profilesConfig{
		Profiles: map[string]profileDef{
			"minimal":  {},
			"go":       {},
			"auto":     {},
			"full":     {},
			"frontend": {},
			"infra":    {},
		},
	}

	names := cfg.profileNames()

	if names[0] != "auto" {
		t.Errorf("first = %q, want auto", names[0])
	}
	if names[1] != "full" {
		t.Errorf("second = %q, want full", names[1])
	}
	if names[len(names)-1] != "minimal" {
		t.Errorf("last = %q, want minimal", names[len(names)-1])
	}

	middle := names[2 : len(names)-1]
	for i := 1; i < len(middle); i++ {
		if middle[i] < middle[i-1] {
			t.Errorf("middle not sorted: %v", middle)
			break
		}
	}
}

func TestProfileNames_AutoFirst(t *testing.T) {
	cfg := profilesConfig{
		Profiles: map[string]profileDef{
			"auto":    {},
			"full":    {},
			"go":      {},
			"minimal": {},
		},
	}

	names := cfg.profileNames()
	if len(names) == 0 || names[0] != "auto" {
		t.Errorf("profileNames()[0] = %q, want auto", names[0])
	}
}

func TestProfileNames_OmitsMissingSentinels(t *testing.T) {
	// A config without the auto/full/minimal sentinels must not list them —
	// otherwise the menu shows empty-description rows and numeric selection can
	// resolve to a profile that isn't in the config.
	cfg := profilesConfig{
		Profiles: map[string]profileDef{
			"go":     {},
			"python": {},
		},
	}

	names := cfg.profileNames()
	for _, n := range names {
		if n == "auto" || n == "full" || n == "minimal" {
			t.Errorf("profileNames() = %v, must not include sentinel %q absent from config", names, n)
		}
	}
	want := []string{"go", "python"}
	if len(names) != len(want) {
		t.Fatalf("profileNames() = %v, want %v", names, want)
	}
	for i := range want {
		if names[i] != want[i] {
			t.Errorf("profileNames()[%d] = %q, want %q", i, names[i], want[i])
		}
	}
}

func TestParseSemver(t *testing.T) {
	tests := []struct {
		input string
		want  [3]int
	}{
		{"1.2.3", [3]int{1, 2, 3}},
		{"v0.1.0", [3]int{0, 1, 0}},
		{"10.20.30", [3]int{10, 20, 30}},
		{"1.0", [3]int{1, 0, 0}},
		{"1", [3]int{1, 0, 0}},
		{"", [3]int{0, 0, 0}},
		{"abc", [3]int{0, 0, 0}},
	}
	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			got := parseSemver(tt.input)
			if got != tt.want {
				t.Errorf("parseSemver(%q) = %v, want %v", tt.input, got, tt.want)
			}
		})
	}
}

func TestIsHomebrewInstall(t *testing.T) {
	got := isHomebrewInstall()
	_ = got // just verify it doesn't panic
}
