package utils

import (
	"errors"
	"fmt"
	"os"
	"strings"

	sdk "github.com/bitwarden/sdk-go"
)

//--------------------------------------------------------------------
// Constants
//--------------------------------------------------------------------

// bwsOrgID is the UUID of the Bitwarden organization that owns all
// projects and secrets. Change this here if the organization ever moves.
const bwsOrgID = "874c7885-c255-47bf-a5ef-b31d012e77aa"

//--------------------------------------------------------------------
// Client wrapper
//--------------------------------------------------------------------

// BWSSecretsClient wraps an authenticated Bitwarden SDK client.
type BWSSecretsClient struct {
	bw sdk.BitwardenClientInterface
}

// NewBWSSecretsClient logs in with the access token from the environment
// and returns a ready‑to‑use client.
func NewBWSSecretsClient() (*BWSSecretsClient, error) {
	accessToken := os.Getenv("BWS_ACCESS_TOKEN")
	if strings.TrimSpace(accessToken) == "" {
		return nil, errors.New("BWS_ACCESS_TOKEN env var is missing or empty")
	}

	// Create Bitwarden client (nil URLs → defaults).
	bw, err := sdk.NewBitwardenClient(nil, nil)
	if err != nil {
		return nil, fmt.Errorf("initialising Bitwarden SDK client: %w", err)
	}
	if err := bw.AccessTokenLogin(accessToken, nil); err != nil {
		return nil, fmt.Errorf("Bitwarden access‑token login failed: %w", err)
	}

	return &BWSSecretsClient{bw: bw}, nil
}

// Close releases resources held by the underlying SDK client.
func (c *BWSSecretsClient) Close() {
	if c != nil && c.bw != nil {
		c.bw.Close()
	}
}

//--------------------------------------------------------------------
// Public helpers
//--------------------------------------------------------------------

// GetBWSSecrets retrieves all key/value secrets belonging to the specified
// Bitwarden project **name** and returns them as a map.
func (c *BWSSecretsClient) GetBWSSecrets(projectName string) (map[string]string, error) {
	if strings.TrimSpace(projectName) == "" {
		return nil, errors.New("projectName must not be empty")
	}

	// 1. Resolve the project ID from the project name.
	projectsResp, err := c.bw.Projects().List(bwsOrgID)
	if err != nil {
		Logger.WithError(err).Error("Failed to list Bitwarden projects")
		return nil, fmt.Errorf("listing Bitwarden projects: %w", err)
	}

	var projectID string
	for _, p := range projectsResp.Data {
		if strings.EqualFold(p.Name, projectName) {
			projectID = p.ID
			break
		}
	}
	if projectID == "" {
		return nil, fmt.Errorf("project %q not found in organisation %s", projectName, bwsOrgID)
	}

	// 2. Sync secrets for the organisation.
	syncResp, err := c.bw.Secrets().Sync(bwsOrgID, nil)
	if err != nil {
		Logger.WithError(err).Error("Failed to sync Bitwarden secrets")
		return nil, fmt.Errorf("syncing Bitwarden secrets: %w", err)
	}

	// 3. Filter those belonging to the resolved project.
	out := make(map[string]string)
	for _, s := range syncResp.Secrets {
		if s.ProjectID != nil && *s.ProjectID == projectID {
			out[s.Key] = s.Value
		}
	}

	if len(out) == 0 {
		return nil, fmt.Errorf("no secrets found for project %q", projectName)
	}
	return out, nil
}

