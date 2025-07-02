package config

import (
	"crypto/ecdsa"
	"crypto/rsa"
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"fmt"
	"os"
	"time"

	"github.com/golang-jwt/jwt/v5"
	ld "github.com/launchdarkly/go-server-sdk/v7"
	"github.com/launchdarkly/go-sdk-common/v3/ldcontext"
	"github.com/poofware/go-utils"
)

// Config holds all application configuration, including secrets, flags, etc.
type Config struct {
	OrganizationName             string
	AppName                      string
	AppPort                      string
	AppUrl                       string
	DBUrl                        string
	DBEncryptionKey              []byte
	UniqueRunNumber              string
	UniqueRunnerID               string
	MobileTokenExpiry            time.Duration
	MobileRefreshTokenExpiry     time.Duration
	WebTokenExpiry               time.Duration
	WebRefreshTokenExpiry        time.Duration
	MaxLoginAttempts             int
	AttemptWindow                time.Duration
	LockDuration                 time.Duration
	TwilioAccountSID             string
	TwilioAuthToken              string
	SendGridAPIKey               string
	VerificationCodeLength       int
	VerificationCodeExpiry       time.Duration
	RSAPrivateKey                *rsa.PrivateKey
	RSAPublicKey                 *rsa.PublicKey
	AppleDeviceCheckKey          *ecdsa.PrivateKey
	PlayIntegritySAJSON          []byte
	SMSLimitPerIPPerHour         int
	SMSLimitPerNumberPerHour     int
	GlobalSMSLimitPerHour        int
	EmailLimitPerIPPerHour       int
	EmailLimitPerEmailPerHour    int
	GlobalEmailLimitPerHour      int
	RateLimitWindow              time.Duration

	// Static flags fetched once from LaunchDarkly
	LDFlag_SendgridFromEmail             string
	LDFlag_TwilioFromPhone               string
	LDFlag_ShortTokenTTL                 bool
	LDFlag_AcceptFakePhonesEmails        bool
	LDFlag_SendgridSandboxMode           bool
	LDFlag_ValidatePhoneWithTwilio       bool
	LDFlag_ValidateEmailWithSendGrid     bool
	LDFlag_UsingIsolatedSchema           bool
	LDFlag_DoRealMobileDeviceAttestation bool
	LDFlag_CORSHighSecurity              bool
}

// Constants for time-based configuration defaults.
const (
	OrganizationName                 = utils.OrganizationName
	MaxLoginAttempts                 = 10
	AttemptWindow                    = 5 * time.Minute
	LockDuration                     = 10 * time.Minute
	VerificationCodeLength           = 6
	DefaultVerificationCodeExpiry    = 5 * time.Minute
	TestShortVerificationCodeExpiry  = 3 * time.Second
	DefaultTokenExpiry               = 10 * time.Minute
	DefaultRefreshTokenExpiry        = 7 * 24 * time.Hour
	TestShortTokenExpiry             = 2 * time.Second
	TestShortRefreshTokenExpiry      = 8 * time.Second
	LDConnectionTimeout              = 5 * time.Second
	DefaultSMSLimitPerIPPerHour      = 20
	DefaultSMSLimitPerNumberPerHour  = 5
	DefaultGlobalSMSLimitPerHour     = 1000
	DefaultEmailLimitPerIPPerHour    = 50
	DefaultEmailLimitPerEmailPerHour = 5
	DefaultGlobalEmailLimitPerHour   = 2000
	DefaultRateLimitWindow           = 1 * time.Hour
	// NEW: Test-specific global limits for integration tests
	TestShortGlobalSMSLimit   = 50
	TestShortGlobalEmailLimit = 50
)

// Global compile-time overrides, defaults for demonstration.
var (
	AppName             string
	UniqueRunNumber     string
	UniqueRunnerID      string
	LDServerContextKey  string
	LDServerContextKind string
)

// LoadConfig fetches secrets from HCP, sets up LaunchDarkly, and returns a *Config.
func LoadConfig() *Config {
	//----------------------------------------------------------------------
	// Check for required ldflags.
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
	// Create HCPSecretsClient
	//----------------------------------------------------------------------
	client, err := utils.NewHCPSecretsClient()
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to initialize HCPSecretsClient")
	}

	//----------------------------------------------------------------------
	// Fetch app-specific secrets from HCP (appName-env).
	//----------------------------------------------------------------------
	utils.Logger.Debugf("Fetching app-specific secrets from HCP for %s-%s", AppName, env)
	hcpAppName := fmt.Sprintf("%s-%s", AppName, env)
	appSecrets, err := client.GetHCPSecretsFromSecretsJSON(hcpAppName)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to fetch app-specific secrets from HCP")
	}

	//----------------------------------------------------------------------
	// Fetch shared secrets from HCP (shared-env).
	//----------------------------------------------------------------------
	utils.Logger.Debugf("Fetching shared secrets from HCP for %s-%s", "shared", env)
	hcpSharedAppName := fmt.Sprintf("shared-%s", env)
	sharedSecrets, err := client.GetHCPSecretsFromSecretsJSON(hcpSharedAppName)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to fetch shared secrets from HCP")
	}

	//----------------------------------------------------------------------
	// Parse required secrets from appSecrets.
	//----------------------------------------------------------------------
	dbUrl, ok := appSecrets["DB_URL"]
	if !ok || dbUrl == "" {
		utils.Logger.Fatal("DB_URL not found in HCP secrets (appName-env)")
	}

	twilioAccountSID, ok := appSecrets["TWILIO_ACCOUNT_SID"]
	if !ok || twilioAccountSID == "" {
		utils.Logger.Fatal("TWILIO_ACCOUNT_SID not found in HCP secrets (appName-env)")
	}
	twilioAuthToken, ok := appSecrets["TWILIO_AUTH_TOKEN"]
	if !ok || twilioAuthToken == "" {
		utils.Logger.Fatal("TWILIO_AUTH_TOKEN not found in HCP secrets (appName-env)")
	}

	sendGridAPIKey, ok := appSecrets["SENDGRID_API_KEY"]
	if !ok || sendGridAPIKey == "" {
		utils.Logger.Fatal("SENDGRID_API_KEY not found in HCP secrets (appName-env)")
	}

	ldSDKKey, ok := appSecrets["LD_SDK_KEY"]
	if !ok || ldSDKKey == "" {
		utils.Logger.Fatal("LD_SDK_KEY not found in HCP secrets (appName-env)")
	}

	//----------------------------------------------------------------------
	// Parse required secrets from sharedSecrets (RSA keys).
	//----------------------------------------------------------------------
	privateKeyBase64, ok := sharedSecrets["RSA_PRIVATE_KEY_BASE64"]
	if !ok || privateKeyBase64 == "" {
		utils.Logger.Fatal("RSA_PRIVATE_KEY_BASE64 not found in HCP secrets (shared-env)")
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
		utils.Logger.Fatal("RSA_PUBLIC_KEY_BASE64 not found in HCP secrets (shared-env)")
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

	dbEncryptionKeyBase64, ok := sharedSecrets["DB_ENCRYPTION_KEY_BASE64"]
	if !ok || dbEncryptionKeyBase64 == "" {
		utils.Logger.Fatal("DB_ENCRYPTION_KEY_BASE64 not found in HCP secrets (appName-env)")
	}
	decodedKey, err := base64.StdEncoding.DecodeString(dbEncryptionKeyBase64)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to decode DB_ENCRYPTION_KEY_BASE64 from base64")
	}
	if len(decodedKey) != 32 {
		utils.Logger.Fatal("DBEncryptionKey must be 32 bytes for AES-256 encryption")
	}

	//----------------------------------------------------------------------
	// Default token and code expiries.
	//----------------------------------------------------------------------
	mobileTokenExpiry := DefaultTokenExpiry
	mobileRefreshTokenExpiry := DefaultRefreshTokenExpiry
	webTokenExpiry := DefaultTokenExpiry
	webRefreshTokenExpiry := DefaultRefreshTokenExpiry
	verificationCodeExpiry := DefaultVerificationCodeExpiry
	globalSMSLimit := DefaultGlobalSMSLimitPerHour
	globalEmailLimit := DefaultGlobalEmailLimitPerHour

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
	// Fetch the specified static flags from LaunchDarkly.
	//----------------------------------------------------------------------
	context := ldcontext.NewWithKind(ldcontext.Kind(LDServerContextKind), LDServerContextKey)

	sendgridFromEmailFlag, err := ldClient.StringVariation("sendgrid_from_email", context, "")
	if err != nil {
		ldClient.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving sendgrid_from_email flag")
	}
	if sendgridFromEmailFlag == "" {
		utils.Logger.Fatal("sendgrid_from_email flag is empty")
	}

	twilioFromPhoneFlag, err := ldClient.StringVariation("twilio_from_phone", context, "")
	if err != nil {
		ldClient.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving twilio_from_phone flag")
	}
	if twilioFromPhoneFlag == "" {
		utils.Logger.Fatal("twilio_from_phone flag is empty")
	}
	utils.Logger.Debugf("twilio_from_phone flag: %s", twilioFromPhoneFlag)

	shortTokenTTLFlag, err := ldClient.BoolVariation("short_token_ttl", context, false)
	if err != nil {
		ldClient.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving short_token_ttl flag")
	}
	utils.Logger.Debugf("short_token_ttl flag: %t", shortTokenTTLFlag)

	acceptFakePhonesEmailsFlag, err := ldClient.BoolVariation("accept_fake_phones_and_emails", context, false)
	if err != nil {
		ldClient.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving accept_fake_phones_and_emails flag")
	}
	utils.Logger.Debugf("accept_fake_phones_and_emails flag: %t", acceptFakePhonesEmailsFlag)

	sendgridSandboxModeFlag, err := ldClient.BoolVariation("sendgrid_sandbox_mode", context, false)
	if err != nil {
		ldClient.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving sendgrid_sandbox_mode flag")
	}
	utils.Logger.Debugf("sendgrid_sandbox_mode flag: %t", sendgridSandboxModeFlag)

	validatePhoneWithTwilioFlag, err := ldClient.BoolVariation("validate_phone_with_twilio", context, false)
	if err != nil {
		ldClient.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving validate_phone_with_twilio flag")
	}
	utils.Logger.Debugf("validate_phone_with_twilio flag: %t", validatePhoneWithTwilioFlag)

	validateEmailWithSendGridFlag, err := ldClient.BoolVariation("validate_email_with_sendgrid", context, false)
	if err != nil {
		ldClient.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving validate_email_with_sendgrid flag")
	}
	utils.Logger.Debugf("validate_email_with_sendgrid flag: %t", validateEmailWithSendGridFlag)

	usingIsolatedSchemaFlag, err := ldClient.BoolVariation("using_isolated_schema", context, false)
	if err != nil {
		ldClient.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving using_isolated_schema flag")
	}
	utils.Logger.Debugf("using_isolated_schema flag: %t", usingIsolatedSchemaFlag)

	//----------------------------------------------------------------------
	// If shortTokenTTLFlag is true, override expiries and global limits.
	//----------------------------------------------------------------------
	if shortTokenTTLFlag {
		mobileTokenExpiry = TestShortTokenExpiry
		mobileRefreshTokenExpiry = TestShortRefreshTokenExpiry
		webTokenExpiry = TestShortTokenExpiry
		webRefreshTokenExpiry = TestShortRefreshTokenExpiry
		verificationCodeExpiry = TestShortVerificationCodeExpiry
		globalSMSLimit = TestShortGlobalSMSLimit
		globalEmailLimit = TestShortGlobalEmailLimit
	}

	// Fetch LD_SDK_KEY_SHARED for shared LaunchDarkly flags
	ldSDKKeyShared, ok := sharedSecrets["LD_SDK_KEY_SHARED"]
	if !ok || ldSDKKeyShared == "" {
		utils.Logger.Fatal("LD_SDK_KEY_SHARED not found in HCP secrets (shared-env)")
	}

	// Fetch do_real_mobile_device_attestation flag from LaunchDarkly using LD_SDK_KEY_SHARED
	ldClientShared, err := ld.MakeClient(ldSDKKeyShared, LDConnectionTimeout)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to create shared LaunchDarkly client")
	}
	defer ldClientShared.Close()

	doRealMobileDeviceAttestation, err := ldClientShared.BoolVariation("do_real_mobile_device_attestation", context, false)
	if err != nil {
		ldClientShared.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving do_real_mobile_device_attestation flag")
	}
	utils.Logger.Debugf("do_real_mobile_device_attestation flag: %t", doRealMobileDeviceAttestation)

	corsHighSecurity, err := ldClientShared.BoolVariation("cors_high_security", context, false)
	if err != nil {
		ldClientShared.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving cors_high_security flag")
	}
	utils.Logger.Debugf("cors_high_security flag: %t", corsHighSecurity)

	var priv *ecdsa.PrivateKey
	var saJSON []byte
	if doRealMobileDeviceAttestation {
		keyPEM, _ := base64.StdEncoding.DecodeString(sharedSecrets["APPLE_DEVICE_CHECK_KEY_BASE64"])
		block, _ = pem.Decode(keyPEM)
		if block == nil {
			utils.Logger.Fatal("Failed to decode PEM block for Apple Device Check key")
		}
		privAny, _ := x509.ParsePKCS8PrivateKey(block.Bytes)
		priv = privAny.(*ecdsa.PrivateKey)
		saJSON, _ = base64.StdEncoding.DecodeString(sharedSecrets["PLAY_INTEGRITY_SA_JSON_BASE64"])
	}

	//----------------------------------------------------------------------
	// Build and return the configuration object.
	//----------------------------------------------------------------------
	return &Config{
		OrganizationName:             OrganizationName,
		AppName:                      AppName,
		AppPort:                      appPort,
		AppUrl:                       appUrl,
		DBUrl:                        dbUrl,
		DBEncryptionKey:              decodedKey,
		UniqueRunNumber:              UniqueRunNumber,
		UniqueRunnerID:               UniqueRunnerID,
		MobileTokenExpiry:            mobileTokenExpiry,
		MobileRefreshTokenExpiry:     mobileRefreshTokenExpiry,
		WebTokenExpiry:               webTokenExpiry,
		WebRefreshTokenExpiry:        webRefreshTokenExpiry,
		MaxLoginAttempts:             MaxLoginAttempts,
		AttemptWindow:                AttemptWindow,
		LockDuration:                 LockDuration,
		TwilioAccountSID:             twilioAccountSID,
		TwilioAuthToken:              twilioAuthToken,
		SendGridAPIKey:               sendGridAPIKey,
		VerificationCodeLength:       VerificationCodeLength,
		VerificationCodeExpiry:       verificationCodeExpiry,
		RSAPrivateKey:                privateKey,
		RSAPublicKey:                 publicKey,
		AppleDeviceCheckKey:          priv,
		PlayIntegritySAJSON:          saJSON,
		SMSLimitPerIPPerHour:         DefaultSMSLimitPerIPPerHour,
		SMSLimitPerNumberPerHour:     DefaultSMSLimitPerNumberPerHour,
		GlobalSMSLimitPerHour:        globalSMSLimit,
		EmailLimitPerIPPerHour:       DefaultEmailLimitPerIPPerHour,
		EmailLimitPerEmailPerHour:    DefaultEmailLimitPerEmailPerHour,
		GlobalEmailLimitPerHour:      globalEmailLimit,
		RateLimitWindow:              DefaultRateLimitWindow,
		LDFlag_SendgridFromEmail:     sendgridFromEmailFlag,
		LDFlag_TwilioFromPhone:       twilioFromPhoneFlag,
		LDFlag_ShortTokenTTL:         shortTokenTTLFlag,
		LDFlag_AcceptFakePhonesEmails: acceptFakePhonesEmailsFlag,
		LDFlag_SendgridSandboxMode:   sendgridSandboxModeFlag,
		LDFlag_ValidatePhoneWithTwilio: validatePhoneWithTwilioFlag,
		LDFlag_ValidateEmailWithSendGrid: validateEmailWithSendGridFlag,
		LDFlag_UsingIsolatedSchema:        usingIsolatedSchemaFlag,
		LDFlag_DoRealMobileDeviceAttestation: doRealMobileDeviceAttestation,
		LDFlag_CORSHighSecurity: corsHighSecurity,
	}
}

// Close cleans up any resources used by Config (e.g., the LD client).
func (c *Config) Close() {
}
