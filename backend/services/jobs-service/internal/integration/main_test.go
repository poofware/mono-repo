//go:build (dev_test || dev || staging_test) && integration

package integration

import (
	"context"
	"log"
	"os"
	"testing"
	"time"
	_ "time/tzdata"

	"github.com/google/uuid"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-testhelpers"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/config"
	"github.com/stretchr/testify/require"
)

// Global test-level variables
var (
	h      *testhelpers.TestHelper
	testPM *models.PropertyManager
	cfg    *config.Config
)

// TestMain sets up a single TestHelper for all integration tests in this package.
func TestMain(m *testing.M) {
	// Required ldflags checks (these are read by config.LoadConfig)
	if config.AppName == "" {
		log.Fatal("config.AppName is empty or not set (ldflags missing?)")
	}
	if config.UniqueRunnerID == "" {
		log.Fatal("config.UniqueRunnerID is empty or not set")
	}
	if config.UniqueRunNumber == "" {
		log.Fatal("config.UniqueRunNumber is empty or not set")
	}

	// Load the full application config, which includes fetching LD flags.
	cfg = config.LoadConfig()

	// Use a dummy testing.T to initialize the helper.
	t := &testing.T{}
	h = testhelpers.NewTestHelper(t, config.AppName, config.UniqueRunnerID, config.UniqueRunNumber)

	ctx := context.Background()

	// Create a reusable property manager
	testPM = &models.PropertyManager{
		ID:              uuid.New(),
		Email:           "integration-pm@poofware.dev",
		PhoneNumber:     utils.Ptr("+15550000000"),
		BusinessName:    "Integration PM",
		BusinessAddress: "1 Main St",
		City:            "Testville",
		State:           "TN",
		ZipCode:         "00000",
		AccountStatus:   models.AccountStatusActive,
		SetupProgress:   models.SetupProgressDone,
	}
	err := h.PMRepo.Create(ctx, testPM)
	require.NoError(t, err, "Failed to create testPM property manager")

	log.Printf("jobs-service integration tests: DB connected, baseURL=%s, env=%s", h.BaseURL, os.Getenv("ENV"))

	// Give DB a moment to be fully ready
	time.Sleep(100 * time.Millisecond)

	// Actually run the tests
	code := m.Run()

	// Cleanup is handled by t.Cleanup() inside NewTestHelper
	os.Exit(code)
}
