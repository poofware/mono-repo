//go:build (dev_test || staging_test) && integration

package integration

import (
	"flag"
	"log"
	"os"
	"testing"
	"time"

	"github.com/poofware/account-service/internal/config"
	"github.com/poofware/go-testhelpers"
)

var h *testhelpers.TestHelper

// TestMain sets up a single TestHelper for all integration tests in this package.
func TestMain(m *testing.M) {
	// Required ldflags checks
	if config.AppName == "" {
		log.Fatal("AppName ldflag is missing")
	}
	if config.UniqueRunnerID == "" {
		log.Fatal("UniqueRunnerID ldflag is missing")
	}
	if config.UniqueRunNumber == "" {
		log.Fatal("UniqueRunNumber ldflag is missing")
	}

	// The TestHelper already parses this flag.
	flag.Bool("manual", false, "Run with UI (headless Chrome) for testing")
	flag.Parse()

	// Use a dummy testing.T to initialize the helper.
	// We can't use one from a real test since TestMain runs before tests.
	t := &testing.T{}
	h = testhelpers.NewTestHelper(t, config.AppName, config.UniqueRunnerID, config.UniqueRunNumber)

	// Give DB a moment to be fully ready
	time.Sleep(100 * time.Millisecond)

	// Run the tests
	code := m.Run()

	// Cleanup is handled by t.Cleanup() inside NewTestHelper
	os.Exit(code)
}

