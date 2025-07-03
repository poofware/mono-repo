package utils

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
)

// Default values, override via ldflags at build time to inject encrypted secrets.
var (
	HCPOrgID     string
	HCPProjectID string
)

type HCPSecretsClient struct {
	orgID       string
	projectID   string
	hcpAPIToken string // decrypted API token
}

// NewHCPSecretsClient reads HCP_TOKEN_ENC_KEY from environment,
// decrypts HCPEncryptedAPIToken, and returns a ready-to-use client.
func NewHCPSecretsClient() (*HCPSecretsClient, error) {
	// Check for required ldflags
	if HCPOrgID == "" {
		return nil, errors.New("HCPOrgID was not overridden with ldflags at build time (or is empty)")
	}
	if HCPProjectID == "" {
		return nil, errors.New("HCPProjectID was not overridden with ldflags at build time (or is empty)")
	}

	hcpEncryptedAPIToken := os.Getenv("HCP_ENCRYPTED_API_TOKEN")
	if hcpEncryptedAPIToken == "" {
		return nil, errors.New("HCP_ENCRYPTED_API_TOKEN env var is missing")
	}
	encryptionKey := os.Getenv("HCP_TOKEN_ENC_KEY")
	if encryptionKey == "" {
		return nil, errors.New("HCP_TOKEN_ENC_KEY env var is missing")
	}

	// Decrypt the HCPEncryptedAPIToken (AES-256-CBC + PBKDF2 Salted__ format).
	decryptedToken, err := DecryptOpenSSLSalted([]byte(encryptionKey), hcpEncryptedAPIToken)
	if err != nil {
		return nil, fmt.Errorf("failed to decrypt HCP token: %w", err)
	}

	client := &HCPSecretsClient{
		orgID:       HCPOrgID,
		projectID:   HCPProjectID,
		hcpAPIToken: decryptedToken,
	}
	return client, nil
}

// GetHCPSecrets retrieves secrets from HashiCorp Cloud Platform for the given
// app name (e.g. "auth-service-dev"), returning a map of secretName -> secretValue.
func (c *HCPSecretsClient) GetHCPSecrets(hcpAppName string) (map[string]string, error) {
	url := fmt.Sprintf(
		"https://api.cloud.hashicorp.com/secrets/2023-11-28/organizations/%s/projects/%s/apps/%s/secrets:open",
		c.orgID,
		c.projectID,
		hcpAppName,
	)

	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		Logger.WithError(err).Error("Failed to create HCP secrets request")
		return nil, fmt.Errorf("creating HCP secrets request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+c.hcpAPIToken)

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		Logger.WithError(err).Error("Failed to perform HCP secrets request")
		return nil, fmt.Errorf("performing HCP secrets request: %w", err)
	}
	defer resp.Body.Close()

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		Logger.WithError(err).Error("Failed to read HCP secrets response")
		return nil, fmt.Errorf("reading HCP secrets response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		err := fmt.Errorf(
			"unexpected status code %d from HCP. Full response:\n%s",
			resp.StatusCode,
			string(bodyBytes),
		)
		Logger.WithError(err).Error("GetHCPSecrets failed due to status code")
		return nil, err
	}

	var rawPayload map[string]any
	if err := json.Unmarshal(bodyBytes, &rawPayload); err != nil {
		Logger.WithError(err).Error("Failed to decode HCP secrets response")
		return nil, fmt.Errorf(
			"decoding HCP secrets response: %w\nFull response:\n%s",
			err, string(bodyBytes),
		)
	}

	secretsIface, found := rawPayload["secrets"]
	if !found {
		err := fmt.Errorf("'secrets' key not found in HCP response. Full: %s", string(bodyBytes))
		Logger.WithError(err).Error("GetHCPSecrets missing 'secrets' in response")
		return nil, err
	}

	secretsSlice, ok := secretsIface.([]any)
	if !ok {
		err := fmt.Errorf("invalid type for 'secrets'; expected an array. Full: %s", string(bodyBytes))
		Logger.WithError(err).Error("GetHCPSecrets had invalid 'secrets' array type")
		return nil, err
	}

	// Expecting only static secrets, not dynamic ones. If that changes, this will need to be updated.
	result := make(map[string]string)
	for _, secret := range secretsSlice {
		secretMap, ok := secret.(map[string]any)
		if !ok {
			err := fmt.Errorf("secret entry not a JSON object: %v", secret)
			Logger.WithError(err).Error("GetHCPSecrets parse error")
			return nil, err
		}

		name, _ := secretMap["name"].(string)
		if name == "" {
			err := fmt.Errorf("secret is missing 'name': %v", secretMap)
			Logger.WithError(err).Error("GetHCPSecrets parse error - missing secret name")
			return nil, err
		}

		staticVersion, _ := secretMap["static_version"].(map[string]any)
		if staticVersion == nil {
			err := fmt.Errorf("secret '%s' missing 'static_version': %v", name, secretMap)
			Logger.WithError(err).Error("GetHCPSecrets parse error - missing static_version")
			return nil, err
		}

		value, _ := staticVersion["value"].(string)
		if value == "" {
			err := fmt.Errorf("secret '%s' missing or empty 'value': %v", name, staticVersion)
			Logger.WithError(err).Error("GetHCPSecrets parse error - missing value")
			return nil, err
		}

		result[name] = value
	}

	return result, nil
}

// GetHCPSecretsFromSecretsJSON works similarly to GetHCPSecrets, but instead of
// returning all secrets from HCP directly, it retrieves the single "SECRETS_JSON"
// secret, parses it as JSON, and returns that as a map. It will error if
// "SECRETS_JSON" is missing or if the JSON within it is invalid.
//
// This allows you to store multiple sub-secrets in the single "SECRETS_JSON" key
// and retrieve them all at once, just like the above script does.
func (c *HCPSecretsClient) GetHCPSecretsFromSecretsJSON(hcpAppName string) (map[string]string, error) {
	// 1. Use the existing GetHCPSecrets to pull all secrets for the app.
	allSecrets, err := c.GetHCPSecrets(hcpAppName)
	if err != nil {
		return nil, err
	}

	// 2. Find the "SECRETS_JSON" secret among them.
	secretsJSONStr, found := allSecrets["SECRETS_JSON"]
	if !found {
		err := errors.New("SECRETS_JSON not found among secrets from HCP")
		Logger.WithError(err).Error("GetHCPSecretsFromSecretsJSON parse error - missing SECRETS_JSON")
		return nil, err
	}

	// 3. Parse the JSON in "SECRETS_JSON".
	var parsed map[string]string
	if err := json.Unmarshal([]byte(secretsJSONStr), &parsed); err != nil {
		err := fmt.Errorf("failed to parse 'SECRETS_JSON' as JSON: %v", err)
		Logger.WithError(err).Error("GetHCPSecretsFromSecretsJSON parse error - invalid JSON")
		return nil, err
	}

	return parsed, nil
}

