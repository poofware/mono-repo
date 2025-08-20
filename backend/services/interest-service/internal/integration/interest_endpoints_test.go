//go:build dev && integration

package integration

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/poofware/mono-repo/backend/services/interest-service/internal/dtos"
)

// -----------------------------------------------------------------------------
// Globals
// -----------------------------------------------------------------------------

var (
	baseURL string
)

// -----------------------------------------------------------------------------
// Suite bootstrap
// -----------------------------------------------------------------------------

func TestMain(m *testing.M) {
	baseURL = os.Getenv("APP_URL_FROM_COMPOSE_NETWORK")
	if baseURL == "" {
		fmt.Println("APP_URL_FROM_COMPOSE_NETWORK env var is missing")
		os.Exit(1)
	}

	baseURL = strings.TrimRight(baseURL, "/")

	os.Exit(m.Run())
}

// -----------------------------------------------------------------------------
// Happy-path (real e-mail address)
// -----------------------------------------------------------------------------

func TestSubmitInterestHappyPath(t *testing.T) {
	const realEmail = "jlmoors001@gmail.com"

	t.Run("Worker", func(t *testing.T) {
		submitInterestExpect(t, "/api/v1/interest/worker", realEmail, http.StatusOK)
	})

	t.Run("PM", func(t *testing.T) {
		submitInterestExpect(t, "/api/v1/interest/pm", realEmail, http.StatusOK)
	})
}

// -----------------------------------------------------------------------------
// Negative-path – malformed / invalid emails
// -----------------------------------------------------------------------------

func TestSubmitInterestInvalidEmails(t *testing.T) {
	invalidEmails := []string{
		"",                   // empty
		"plainaddress",       // no '@'
		"@nouser.com",        // missing user
		"user@domain..com",   // double dot
		"user@invalid.",      // no TLD
		"user@.invalid.com",  // dot immediately after '@'
	}

	for _, path := range []string{"/api/v1/interest/worker", "/api/v1/interest/pm"} {
		for _, email := range invalidEmails {
			name := fmt.Sprintf("%s – %q", path, email)
			t.Run(name, func(t *testing.T) {
				submitInterestExpect(t, path, email, http.StatusBadRequest)
			})
		}
	}
}

// -----------------------------------------------------------------------------
// Helper
// -----------------------------------------------------------------------------

func submitInterestExpect(t *testing.T, apiPath, email string, wantStatus int) {
	t.Helper()

	payload := dtos.InterestRequest{Email: email}
	b, err := json.Marshal(payload)
	require.NoError(t, err)

	url := baseURL + apiPath
	resp, err := http.Post(url, "application/json", strings.NewReader(string(b)))
	require.NoError(t, err)
	defer resp.Body.Close()

	require.Equal(t, wantStatus, resp.StatusCode,
		fmt.Sprintf("expected %d for email %q on %s, got %d",
			wantStatus, email, apiPath, resp.StatusCode,
		),
	)
}

