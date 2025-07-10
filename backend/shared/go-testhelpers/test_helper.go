package testhelpers

import (
	"context"
	"crypto/rsa"
	"encoding/base64"
	"encoding/pem"
	"flag"
	"fmt"
	"log"
	"os"
	"testing"

	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v4/pgxpool"
	"github.com/poofware/go-repositories"
	"github.com/poofware/go-utils"
	"github.com/stripe/stripe-go/v82"
	"github.com/stretchr/testify/require"
)

// TestHelper encapsulates all necessary components for running integration tests across services.
type TestHelper struct {
	T                   *testing.T
	Ctx                 context.Context
	BaseURL             string
	DB                  *pgxpool.Pool
	PrivateKey          *rsa.PrivateKey
	DBEncryptionKey     []byte
	StripeWebhookSecret string
	StripeClient        *stripe.Client
	CheckrAPIKey        string
	RunWithUI           bool

	// From ldflags
	AppName         string
	UniqueRunNumber string
	UniqueRunnerID  string

	// Repositories
	AdminRepo       repositories.AdminRepository // NEW
	WorkerRepo      repositories.WorkerRepository
	PMRepo          repositories.PropertyManagerRepository
	PropertyRepo    repositories.PropertyRepository
	BldgRepo        repositories.PropertyBuildingRepository
	UnitRepo        repositories.UnitRepository
	DumpsterRepo    repositories.DumpsterRepository
	JobDefRepo      repositories.JobDefinitionRepository
	JobInstRepo     repositories.JobInstanceRepository
	AgentRepo       repositories.AgentRepository
	PMEmailRepo     repositories.PMEmailVerificationRepository
	PMSMSRepo       repositories.PMSMSVerificationRepository
	WorkerEmailRepo repositories.WorkerEmailVerificationRepository
	WorkerSMSRepo   repositories.WorkerSMSVerificationRepository
}

// NewTestHelper sets up the entire testing environment by loading secrets, connecting to the DB,
// and initializing repositories. It's designed to be called once from a TestMain function.
func NewTestHelper(t *testing.T, appName, uniqueRunID, uniqueRunNum string) *TestHelper {
	// Conditionally check for the --manual flag. This is the most robust approach.
	var runWithUI bool
	if manualFlag := flag.Lookup("manual"); manualFlag != nil {
		// The flag has been defined by the calling test package. We can safely get its value.
		// Note: The flag must be parsed in the caller's TestMain before this.
		runWithUI = manualFlag.Value.(flag.Getter).Get().(bool)
	}

	// 1. Load environment
	baseURL := os.Getenv("APP_URL_FROM_ANYWHERE")
	if baseURL == "" {
		log.Fatal("APP_URL_FROM_ANYWHERE env var is missing")
	}
	env := os.Getenv("ENV")
	if env == "" {
		log.Fatal("ENV env var is missing")
	}

	// 2. HCP Secrets Client
	client, err := utils.NewHCPSecretsClient()
	require.NoError(t, err, "Failed to init HCPSecretsClient")

	// 3. Shared Secrets (RSA Key, DB Encryption Key, Stripe Secret Key)
	sharedAppName := fmt.Sprintf("shared-%s", env)
	sharedSecrets, err := client.GetHCPSecretsFromSecretsJSON(sharedAppName)
	require.NoError(t, err, "Failed to fetch shared secrets")

	privateKeyB64, ok := sharedSecrets["RSA_PRIVATE_KEY_BASE64"]
	require.True(t, ok && privateKeyB64 != "", "RSA_PRIVATE_KEY_BASE64 not found")
	privateKeyPEM, err := base64.StdEncoding.DecodeString(privateKeyB64)
	require.NoError(t, err)
	block, _ := pem.Decode(privateKeyPEM)
	require.NotNil(t, block, "Failed to parse PEM block for RSA_PRIVATE_KEY_BASE64")
	privateKey, err := jwt.ParseRSAPrivateKeyFromPEM(privateKeyPEM)
	require.NoError(t, err)

	dbEncB64, ok := sharedSecrets["DB_ENCRYPTION_KEY_BASE64"]
	require.True(t, ok && dbEncB64 != "", "DB_ENCRYPTION_KEY_BASE64 not found")
	dbEncryptionKey, err := base64.StdEncoding.DecodeString(dbEncB64)
	require.NoError(t, err)
	require.Len(t, dbEncryptionKey, 32, "DB encryption key must be 32 bytes")

	stripeSecretKey, ok := sharedSecrets["STRIPE_SECRET_KEY"]
	require.True(t, ok && stripeSecretKey != "", "STRIPE_SECRET_KEY not found in sharedSecrets")

	// 4. App-Specific Secrets (DB_URL, Webhook Secrets, API Keys)
	appNameEnv := fmt.Sprintf("%s-%s", appName, env)
	appSecrets, err := client.GetHCPSecretsFromSecretsJSON(appNameEnv)
	require.NoError(t, err)
	dbURL, ok := appSecrets["DB_URL"]
	require.True(t, ok && dbURL != "", "DB_URL not found in appSecrets")

	stripeWebhookSecret := appSecrets["STRIPE_WEBHOOK_SECRET"] // Can be empty if not used by service
	checkrAPIKey := appSecrets["CHECKR_API_KEY"]               // Can be empty if not used by service

	// 5. Connect to DB with isolated role
	effectiveURL, err := utils.WithIsolatedRole(dbURL, uniqueRunID, uniqueRunNum)
	require.NoError(t, err)

	ctx := context.Background()
	dbPool, err := pgxpool.Connect(ctx, effectiveURL)
	require.NoError(t, err)
	t.Cleanup(func() { dbPool.Close() })

	// 6. Initialize Stripe Client
	sc := stripe.NewClient(stripeSecretKey)

	// 7. Initialize all repositories and the helper
	h := &TestHelper{
		T:                   t,
		Ctx:                 ctx,
		BaseURL:             baseURL,
		DB:                  dbPool,
		PrivateKey:          privateKey,
		DBEncryptionKey:     dbEncryptionKey,
		StripeWebhookSecret: stripeWebhookSecret,
		StripeClient:        sc,
		CheckrAPIKey:        checkrAPIKey,
		RunWithUI:           runWithUI,
		AppName:             appName,
		UniqueRunnerID:      uniqueRunID,
		UniqueRunNumber:     uniqueRunNum,
		AdminRepo:           repositories.NewAdminRepository(dbPool, dbEncryptionKey), // NEW
		WorkerRepo:          repositories.NewWorkerRepository(dbPool, dbEncryptionKey),
		PMRepo:              repositories.NewPropertyManagerRepository(dbPool, dbEncryptionKey),
		PropertyRepo:        repositories.NewPropertyRepository(dbPool),
		BldgRepo:            repositories.NewPropertyBuildingRepository(dbPool),
		UnitRepo:            repositories.NewUnitRepository(dbPool),
		DumpsterRepo:        repositories.NewDumpsterRepository(dbPool),
		JobDefRepo:          repositories.NewJobDefinitionRepository(dbPool),
		JobInstRepo:         repositories.NewJobInstanceRepository(dbPool),
		AgentRepo:           repositories.NewAgentRepository(dbPool),
		PMEmailRepo:         repositories.NewPMEmailVerificationRepository(dbPool),
		PMSMSRepo:           repositories.NewPMSMSVerificationRepository(dbPool),
		WorkerEmailRepo:     repositories.NewWorkerEmailVerificationRepository(dbPool),
		WorkerSMSRepo:       repositories.NewWorkerSMSVerificationRepository(dbPool),
	}

	return h
}