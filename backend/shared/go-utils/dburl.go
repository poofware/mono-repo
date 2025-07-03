package utils

import (
	"fmt"
	"net/url"
	"strings"
)

func WithIsolatedRole(baseURL, runnerID, runNumber string) (string, error) {
	if runnerID == "" || runNumber == "" {
		return "", fmt.Errorf("runnerID and runNumber must be non-empty")
	}

	role := strings.ToLower(runnerID + "-" + runNumber)

	u, err := url.Parse(baseURL)
	if err != nil {
		return "", fmt.Errorf("invalid DB URL: %w", err)
	}

	// Preserve the existing password (if any) but swap the user.
	password, _ := u.User.Password()
	u.User = url.UserPassword(role, password)

	return u.String(), nil
}

