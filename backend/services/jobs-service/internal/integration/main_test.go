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
	"github.com/poofware/go-models"
	"github.com/poofware/go-testhelpers"
	"github.com/poofware/go-utils"
	"github.com/poofware/jobs-service/internal/config"
	"github.com/stretchr/testify/require"
)

// Global test-level variables
var (
	h      *testhelpers.TestHelper
	testPM *models.PropertyManager
)

// TestMain sets up a single TestHelper for all integration tests in this package.
func TestMain(m *testing.M) {
	// Required ldflags checks
	if config.AppName == "" {
		log.Fatal("config.AppName is empty or not set (ldflags missing?)")
	}
	if config.UniqueRunnerID == "" {
		log.Fatal("config.UniqueRunnerID is empty or not set")
	}
	if config.UniqueRunNumber == "" {
		log.Fatal("config.UniqueRunNumber is empty or not set")
	}

	// Use a dummy testing.T to initialize the helper.
	// We can't use one from a real test since TestMain runs before tests.
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
