package main

import (
	"os"
	"os/exec"
	"regexp"
	"strings"
)

var gidRegex = regexp.MustCompile(`^\d+$`)

func parseGIDOutput(output string) (string, bool) {
	s := strings.TrimSpace(output)
	if gidRegex.MatchString(s) {
		return s, true
	}
	return "", false
}

// probeGIDFunc is the function used to probe the docker socket GID.
// Replaceable in tests to avoid depending on Docker availability.
var probeGIDFunc = probeDockerGID

func probeDockerGID() string {
	cmd := exec.Command("docker", "run", "--rm",
		"-v", "/var/run/docker.sock:/var/run/docker.sock",
		"busybox", "stat", "-c", "%g", "/var/run/docker.sock")
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	gid, _ := parseGIDOutput(string(out))
	return gid
}

// resolveGID resolves the docker socket GID. Order: env override → cache
// file → live probe (≈0.5–1.5s busybox spin-up; refreshes the cache) →
// "999" default. The cache is consulted before probing because the socket
// GID is effectively static per machine — if it ever changes (Docker
// reinstall), delete the cache file or set BACK2BASE_DOCKER_GID.
func resolveGID(envOverride, cacheFile string) string {
	if envOverride != "" {
		return envOverride
	}

	if cached, err := os.ReadFile(cacheFile); err == nil {
		if gid, ok := parseGIDOutput(string(cached)); ok {
			return gid
		}
	}

	if probed := probeGIDFunc(); probed != "" {
		os.WriteFile(cacheFile, []byte(probed), 0644)
		return probed
	}

	return "999"
}
