package config

import (
	"crypto/rsa"
	"encoding/base64"
	"encoding/pem"
	"fmt"
	"os"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/launchdarkly/go-sdk-common/v3/ldcontext"
	ld "github.com/launchdarkly/go-server-sdk/v7"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

type Config struct {
	OrganizationName                     string
	AppName                              string
	AppPort                              string
	AppUrl                               string
	UniqueRunNumber                      string
	UniqueRunnerID                       string
	DBUrl                                string
	DBEncryptionKey                      []byte
	StripeSecretKey                      string
	StripeWebhookSecret                  string
	CheckrAPIKey                         string
	TwilioAccountSID                     string
	TwilioAuthToken                      string
	SendgridAPIKey                       string
	GMapsAPIKey                          string
	RSAPrivateKey                        *rsa.PrivateKey
	RSAPublicKey                         *rsa.PublicKey
	LDSDKKey                             string
	LDFlag_PrefillStripeExpressKYC       bool
	LDFlag_AllowOOSSetupFlow             bool
	LDFlag_SeedDbWithTestAccounts        bool
	LDFlag_CheckrStagingMode             bool
	LDFlag_DynamicCheckrWebhookEndpoint  bool
	LDFlag_ValidatePhoneWithTwilio       bool
	LDFlag_ValidateEmailWithSendGrid     bool
	LDFlag_UsingIsolatedSchema           bool
	LDFlag_DynamicStripeWebhookEndpoint  bool
	LDFlag_DoRealMobileDeviceAttestation bool
	LDFlag_CORSHighSecurity              bool
	LDFlag_SendgridFromEmail             string
	LDFlag_SendgridSandboxMode           bool // NEW
}

const (
	OrganizationName    = utils.OrganizationName
	LDConnectionTimeout = 5 * time.Second
)

// Default values, override via ldflags at build time to inject encrypted secrets.
var (
	AppName             string
	UniqueRunNumber     string
	UniqueRunnerID      string
	LDServerContextKey  string
	LDServerContextKind string
)

func LoadConfig() *Config {
	//----------------------------------------------------------------------
	// Check for required ldflags
	//----------------------------------------------------------------------
	if AppName == "" {
		utils.Logger.Fatal("AppName was not overridden with ldflags at build time (or is empty)")
	}
	if UniqueRunNumber == "" {
		utils.Logger.Fatal("UniqueRunNumber was not overridden with ldflags at build time (or is empty)")
	}
	if UniqueRunnerID == "" {
		utils.Logger.Fatal("UniqueRunnerID was not overridden with ldflags at build time (or is empty)")
	}
	if LDServerContextKey == "" {
		utils.Logger.Fatal("LDServerContextKey was not overridden with ldflags at build time (or is empty)")
	}
	if LDServerContextKind == "" {
		utils.Logger.Fatal("LDServerContextKind was not overridden with ldflags at build time (or is empty)")
	}

	utils.Logger.Info("Loading config for app: ", AppName)

	//----------------------------------------------------------------------
	// Load environment variables.
	//----------------------------------------------------------------------
	env := os.Getenv("ENV")
	if env == "" {
		utils.Logger.Fatal("ENV env var is missing")
	}
	appUrl := os.Getenv("APP_URL_FROM_ANYWHERE")
	if appUrl == "" {
		utils.Logger.Fatal("APP_URL_FROM_ANYWHERE env var is missing")
	}
	appPort := os.Getenv("APP_PORT")
	if appPort == "" {
		utils.Logger.Fatal("APP_PORT env var is missing")
	}

	utils.Logger.Debugf("App can be accessed at: %s", appUrl)

	//----------------------------------------------------------------------
	// Create BWSSecretsClient
	//----------------------------------------------------------------------
	client, err := utils.NewBWSSecretsClient()
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to initialize BWSSecretsClient")
	}

	//----------------------------------------------------------------------
	// Fetch app-specific secrets from BWS (appName-env)
	//----------------------------------------------------------------------
	bwsProjectName := fmt.Sprintf("%s-%s", AppName, env)
	appSecrets, err := client.GetBWSSecrets(bwsProjectName)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to fetch app-specific secrets from BWS")
	}

	//----------------------------------------------------------------------
	// Fetch shared secrets from BWS (shared-env)
	//----------------------------------------------------------------------
	bwsSharedProjectName := fmt.Sprintf("shared-%s", env)
	sharedSecrets, err := client.GetBWSSecrets(bwsSharedProjectName)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to fetch shared secrets from BWS")
	}

	//----------------------------------------------------------------------
	// Parse required secrets from appSecrets
	//----------------------------------------------------------------------
	dbURL, ok := appSecrets["DB_URL"]
	if !ok || dbURL == "" {
		utils.Logger.Fatalf("DB_URL not found in BWS secrets (%s)", bwsProjectName)
	}

	ldSDKKey, ok := appSecrets["LD_SDK_KEY"]
	if !ok || ldSDKKey == "" {
		utils.Logger.Fatalf("LD_SDK_KEY not found in BWS secrets (%s)", bwsProjectName)
	}

	checkrAPIKey, ok := appSecrets["CHECKR_API_KEY"]
	if !ok || checkrAPIKey == "" {
		utils.Logger.Fatalf("CHECKR_API_KEY not found in BWS secrets (%s)", bwsProjectName)
	}

	//----------------------------------------------------------------------
	// Parse required secrets from sharedSecrets (RSA keys)
	//----------------------------------------------------------------------
	dbEncryptionKeyBase64, ok := sharedSecrets["DB_ENCRYPTION_KEY_BASE64"]
	if !ok || dbEncryptionKeyBase64 == "" {
		utils.Logger.Fatal("DB_ENCRYPTION_KEY_BASE64 not found in BWS secrets (appName-env)")
	}
	decodedKey, err := base64.StdEncoding.DecodeString(dbEncryptionKeyBase64)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to decode DB_ENCRYPTION_KEY_BASE64 from base64")
	}
	if len(decodedKey) != 32 {
		utils.Logger.Fatal("DBEncryptionKey must be 32 bytes for AES-256 encryption")
	}

	privateKeyBase64, ok := sharedSecrets["RSA_PRIVATE_KEY_BASE64"]
	if !ok || privateKeyBase64 == "" {
		utils.Logger.Fatal("RSA_PRIVATE_KEY_BASE64 not found in BWS secrets (shared-env)")
	}
	privateKeyPEM, err := base64.StdEncoding.DecodeString(privateKeyBase64)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to decode base64 private key")
	}
	block, _ := pem.Decode(privateKeyPEM)
	if block == nil {
		utils.Logger.Fatal("Failed to decode PEM block for private key")
	}
	privateKey, err := jwt.ParseRSAPrivateKeyFromPEM(privateKeyPEM)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to parse RSA private key")
	}

	publicKeyBase64, ok := sharedSecrets["RSA_PUBLIC_KEY_BASE64"]
	if !ok || publicKeyBase64 == "" {
		utils.Logger.Fatal("RSA_PUBLIC_KEY_BASE64 not found in BWS secrets (shared-env)")
	}
	publicKeyPEM, err := base64.StdEncoding.DecodeString(publicKeyBase64)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to decode base64 public key")
	}
	block, _ = pem.Decode(publicKeyPEM)
	if block == nil {
		utils.Logger.Fatal("Failed to decode PEM block for public key")
	}
	publicKey, err := jwt.ParseRSAPublicKeyFromPEM(publicKeyPEM)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to parse RSA public key")
	}

	stripeSecretKey, ok := sharedSecrets["STRIPE_SECRET_KEY"]
	if !ok || stripeSecretKey == "" {
		utils.Logger.Fatal("STRIPE_SECRET_KEY not found in BWS secrets (shared-env)")
	}

	twilioAccountSID, ok := sharedSecrets["TWILIO_ACCOUNT_SID"]
	if !ok || twilioAccountSID == "" {
		utils.Logger.Fatalf("TWILIO_ACCOUNT_SID not found in BWS secrets (%s)", bwsProjectName)
	}
	twilioAuthToken, ok := sharedSecrets["TWILIO_AUTH_TOKEN"]
	if !ok || twilioAuthToken == "" {
		utils.Logger.Fatalf("TWILIO_AUTH_TOKEN not found in BWS secrets (%s)", bwsProjectName)
	}

	sendgridAPIKey, ok := sharedSecrets["SENDGRID_API_KEY"]
	if !ok || sendgridAPIKey == "" {
		utils.Logger.Fatalf("SENDGRID_API_KEY not found in BWS secrets (%s)", bwsProjectName)
	}

	gmapsAPIKey, ok := sharedSecrets["GMAPS_ROUTES_API_KEY"]
	if !ok || gmapsAPIKey == "" {
		utils.Logger.Fatal("GMAPS_ROUTES_API_KEY not found in BWS secrets (shared-env)")
	}

	//----------------------------------------------------------------------
	// Initialize the LaunchDarkly client with the LD_SDK_KEY.
	//----------------------------------------------------------------------
	ldClient, err := ld.MakeClient(ldSDKKey, LDConnectionTimeout)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to create LaunchDarkly client")
	}
	if !ldClient.Initialized() {
		ldClient.Close()
		utils.Logger.Fatal("LaunchDarkly client failed to initialize")
	}
	defer ldClient.Close()

	//----------------------------------------------------------------------
	// Build an LD context and fetch feature flags
	//----------------------------------------------------------------------
	context := ldcontext.NewWithKind(ldcontext.Kind(LDServerContextKind), LDServerContextKey)

	prefillStripeExpressKyc, err := ldClient.BoolVariation("prefill_stripe_express_kyc", context, false)
	if err != nil {
		ldClient.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving prefill_stripe_express_kyc flag")
	}
	utils.Logger.Debugf("prefill_stripe_express_kyc flag: %t", prefillStripeExpressKyc)

	allowOOSSetupFlow, err := ldClient.BoolVariation("allow_oos_setup_flow", context, false)
	if err != nil {
		ldClient.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving allow_oos_setup_flow flag")
	}
	utils.Logger.Debugf("allow_oos_setup_flow flag: %t", allowOOSSetupFlow)

	seedTestAccounts, err := ldClient.BoolVariation("seed_db_with_test_accounts", context, false)
	if err != nil {
		ldClient.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving seed_db_with_test_accounts flag")
	}
	utils.Logger.Debugf("seed_db_with_test_accounts flag: %t", seedTestAccounts)

	checkrStagingMode, err := ldClient.BoolVariation("checkr_staging_mode", context, false)
	if err != nil {
		ldClient.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving checkr_staging_mode flag")
	}
	utils.Logger.Debugf("checkr_staging_mode flag: %t", checkrStagingMode)

	dynamicCheckrWebhook, err := ldClient.BoolVariation("dynamic_checkr_webhook_endpoint", context, false)
	if err != nil {
		ldClient.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving dynamic_checkr_webhook_endpoint flag")
	}
	utils.Logger.Debugf("dynamic_checkr_webhook_endpoint flag: %t", dynamicCheckrWebhook)

	validatePhoneWithTwilio, err := ldClient.BoolVariation("validate_phone_with_twilio", context, false)
	if err != nil {
		ldClient.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving validate_phone_with_twilio flag")
	}
	utils.Logger.Debugf("validate_phone_with_twilio flag: %t", validatePhoneWithTwilio)

	validateEmailWithSendGrid, err := ldClient.BoolVariation("validate_email_with_sendgrid", context, false)
	if err != nil {
		ldClient.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving validate_email_with_sendgrid flag")
	}
	utils.Logger.Debugf("validate_email_with_sendgrid flag: %t", validateEmailWithSendGrid)

	usingIsolatedSchema, err := ldClient.BoolVariation("using_isolated_schema", context, false)
	if err != nil {
		ldClient.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving using_isolated_schema flag")
	}
	utils.Logger.Debugf("using_isolated_schema flag: %t", usingIsolatedSchema)

	dynamicStripeWebhook, err := ldClient.BoolVariation("dynamic_stripe_webhook_endpoint", context, false)
	if err != nil {
		ldClient.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving dynamic_stripe_webhook_endpoint flag")
	}
	utils.Logger.Debugf("dynamic_stripe_webhook_endpoint flag: %t", dynamicStripeWebhook)

	// Fetch LD_SDK_KEY_SHARED for shared LaunchDarkly flags
	ldSDKKeyShared, ok := sharedSecrets["LD_SDK_KEY_SHARED"]
	if !ok || ldSDKKeyShared == "" {
		utils.Logger.Fatal("LD_SDK_KEY_SHARED not found in BWS secrets (shared-env)")
	}

	// Fetch do_real_mobile_device_attestation flag from LaunchDarkly using LD_SDK_KEY_SHARED
	ldClientShared, err := ld.MakeClient(ldSDKKeyShared, LDConnectionTimeout)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to create shared LaunchDarkly client")
	}
	defer ldClientShared.Close()

	doRealMobileDeviceAttestation, err := ldClientShared.BoolVariation("do_real_mobile_device_attestation", context, false)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Error retrieving do_real_mobile_device_attestation flag")
	}
	utils.Logger.Debugf("do_real_mobile_device_attestation flag: %t", doRealMobileDeviceAttestation)

	corsHighSecurityFlag, err := ldClientShared.BoolVariation("cors_high_security", context, false)
	if err != nil {
		ldClientShared.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving cors_high_security flag")
	}
	utils.Logger.Debugf("cors_high_security flag: %t", corsHighSecurityFlag)

	sendgridSandboxMode, err := ldClientShared.BoolVariation("sendgrid_sandbox_mode", context, false)
	if err != nil {
		ldClientShared.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving sendgrid_sandbox_mode flag")
	}
	utils.Logger.Debugf("sendgrid_sandbox_mode flag: %t", sendgridSandboxMode)

	sendgridFromEmail, err := ldClientShared.StringVariation("sendgrid_from_email", context, "")
	if err != nil {
		ldClientShared.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving sendgrid_from_email flag")
	}
	utils.Logger.Debugf("sendgrid_from_email flag: %s", sendgridFromEmail)

	var stripeWebhookSecret string
	if !dynamicStripeWebhook {
		var ok bool
		stripeWebhookSecret, ok = sharedSecrets["STRIPE_WEBHOOK_SECRET"]
		if !ok || stripeWebhookSecret == "" {
			utils.Logger.Fatalf("STRIPE_WEBHOOK_SECRET not found in BWS secrets (%s)", bwsSharedProjectName)
		}
	}

	return &Config{
		OrganizationName:                     OrganizationName,
		AppName:                              AppName,
		AppPort:                              appPort,
		AppUrl:                               appUrl,
		UniqueRunNumber:                      UniqueRunNumber,
		UniqueRunnerID:                       UniqueRunnerID,
		DBUrl:                                dbURL,
		DBEncryptionKey:                      decodedKey,
		StripeSecretKey:                      stripeSecretKey,
		StripeWebhookSecret:                  stripeWebhookSecret,
		CheckrAPIKey:                         checkrAPIKey,
		TwilioAccountSID:                     twilioAccountSID,
		TwilioAuthToken:                      twilioAuthToken,
		SendgridAPIKey:                       sendgridAPIKey,
		GMapsAPIKey:                          gmapsAPIKey,
		RSAPrivateKey:                        privateKey,
		RSAPublicKey:                         publicKey,
		LDSDKKey:                             ldSDKKey,
		LDFlag_PrefillStripeExpressKYC:       prefillStripeExpressKyc,
		LDFlag_AllowOOSSetupFlow:             allowOOSSetupFlow,
		LDFlag_SeedDbWithTestAccounts:        seedTestAccounts,
		LDFlag_CheckrStagingMode:             checkrStagingMode,
		LDFlag_DynamicCheckrWebhookEndpoint:  dynamicCheckrWebhook,
		LDFlag_ValidatePhoneWithTwilio:       validatePhoneWithTwilio,
		LDFlag_ValidateEmailWithSendGrid:     validateEmailWithSendGrid,
		LDFlag_UsingIsolatedSchema:           usingIsolatedSchema,
		LDFlag_DynamicStripeWebhookEndpoint:  dynamicStripeWebhook,
		LDFlag_DoRealMobileDeviceAttestation: doRealMobileDeviceAttestation,
		LDFlag_CORSHighSecurity:              corsHighSecurityFlag,
		LDFlag_SendgridFromEmail:             sendgridFromEmail,
		LDFlag_SendgridSandboxMode:           sendgridSandboxMode, // NEW
	}
}

func (c *Config) Close() {}
