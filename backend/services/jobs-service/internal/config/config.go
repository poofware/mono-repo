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
	"github.com/launchdarkly/go-sdk-common/v3/ldcontext"
	ld "github.com/launchdarkly/go-server-sdk/v7"
	"github.com/poofware/go-utils"
)

type Config struct {
	OrganizationName string
	AppName          string
	AppPort          string
	AppUrl           string
	UniqueRunNumber  string
	UniqueRunnerID   string

	// Database
	DBUrl           string
	DBEncryptionKey []byte

	// External services
	GMapsRoutesAPIKey string

	// Twilio / SendGrid for JCAS notifications
	TwilioAccountSID string
	TwilioAuthToken  string
	SendGridAPIKey   string
	OpenAIAPIKey     string

	// Auth
	RSAPrivateKey *rsa.PrivateKey
	RSAPublicKey  *rsa.PublicKey

	AppleDeviceCheckKey *ecdsa.PrivateKey // Apple Device Check key for mobile attestation
	PlayIntegritySAJSON []byte            // Google Play Integrity service account JSON

	// LaunchDarkly flags
	LDFlag_UseGMapsRoutesAPI             bool
	LDFlag_UsingIsolatedSchema           bool
	LDFlag_TwilioFromPhone               string
	LDFlag_SendgridFromEmail             string
	LDFlag_SendgridSandboxMode           bool
	LDFlag_SeedDbWithTestData            bool
	LDFlag_DoRealMobileDeviceAttestation bool
	LDFlag_CORSHighSecurity              bool
	LDFlag_OpenAIPhotoVerification        bool
}

const (
	OrganizationName    = utils.OrganizationName
	LDConnectionTimeout = 5 * time.Second
)

// build-time overrides
var (
	AppName             string
	UniqueRunNumber     string
	UniqueRunnerID      string
	LDServerContextKey  string
	LDServerContextKind string
)

func LoadConfig() *Config {
	if AppName == "" {
		utils.Logger.Fatal("AppName ldflag missing")
	}
	if UniqueRunNumber == "" {
		utils.Logger.Fatal("UniqueRunNumber ldflag missing")
	}
	if UniqueRunnerID == "" {
		utils.Logger.Fatal("UniqueRunnerID ldflag missing")
	}
	if LDServerContextKey == "" || LDServerContextKind == "" {
		utils.Logger.Fatal("LD context ldflags missing")
	}

	utils.Logger.Info("Loading config for app: ", AppName)

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

	client, err := utils.NewBWSSecretsClient()
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to initialize BWSSecretsClient")
	}

	appSecretsName := fmt.Sprintf("%s-%s", AppName, env)
	appSecrets, err := client.GetBWSSecrets(appSecretsName)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to fetch app secrets from BWS")
	}

	sharedSecretsName := fmt.Sprintf("shared-%s", env)
	sharedSecrets, err := client.GetBWSSecrets(sharedSecretsName)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to fetch shared secrets from BWS")
	}

	// Required shared secrets
	dbEncB64, ok := sharedSecrets["DB_ENCRYPTION_KEY_BASE64"]
	if !ok || dbEncB64 == "" {
		utils.Logger.Fatalf("DB_ENCRYPTION_KEY_BASE64 not found in BWS (%s)", sharedSecretsName)
	}
	dbEncKey, err := base64.StdEncoding.DecodeString(dbEncB64)
	if err != nil || len(dbEncKey) != 32 {
		utils.Logger.Fatal("DB_ENCRYPTION_KEY_BASE64 invalid – expect 32-byte key")
	}

	privB64, ok := sharedSecrets["RSA_PRIVATE_KEY_BASE64"]
	if !ok || privB64 == "" {
		utils.Logger.Fatalf("RSA_PRIVATE_KEY_BASE64 not found in BWS (%s)", sharedSecretsName)
	}
	privPEM, _ := base64.StdEncoding.DecodeString(privB64)
	if block, _ := pem.Decode(privPEM); block == nil {
		utils.Logger.Fatal("Failed to decode PEM block for private key")
	}
	privKey, err := jwt.ParseRSAPrivateKeyFromPEM(privPEM)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to parse RSA private key")
	}

	pubB64, ok := sharedSecrets["RSA_PUBLIC_KEY_BASE64"]
	if !ok || pubB64 == "" {
		utils.Logger.Fatalf("RSA_PUBLIC_KEY_BASE64 not found in BWS (%s)", sharedSecretsName)
	}
	pubPEM, _ := base64.StdEncoding.DecodeString(pubB64)
	if block, _ := pem.Decode(pubPEM); block == nil {
		utils.Logger.Fatal("Failed to decode PEM block for public key")
	}
	pubKey, err := jwt.ParseRSAPublicKeyFromPEM(pubPEM)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to parse RSA public key")
	}

	// Twilio
	twilioSID, ok := sharedSecrets["TWILIO_ACCOUNT_SID"]
	if !ok || twilioSID == "" {
		utils.Logger.Fatal("TWILIO_ACCOUNT_SID missing in job-service secrets")
	}
	twilioToken, ok := sharedSecrets["TWILIO_AUTH_TOKEN"]
	if !ok || twilioToken == "" {
		utils.Logger.Fatal("TWILIO_AUTH_TOKEN missing in job-service secrets")
	}

	// SendGrid
	sgAPIKey, ok := sharedSecrets["SENDGRID_API_KEY"]
	if !ok || sgAPIKey == "" {
		utils.Logger.Fatal("SENDGRID_API_KEY missing in job-service secrets")
	}

	// App-specific secrets
	dbURL, ok := appSecrets["DB_URL"]
	if !ok || dbURL == "" {
		utils.Logger.Fatalf("DB_URL not found in BWS (%s)", appSecretsName)
	}
	ldSDKKey, ok := appSecrets["LD_SDK_KEY"]
	if !ok || ldSDKKey == "" {
		utils.Logger.Fatalf("LD_SDK_KEY not found in BWS (%s)", appSecretsName)
	}

	// GMaps
	var gmapsKey string

	ldClient, err := ld.MakeClient(ldSDKKey, LDConnectionTimeout)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to create LaunchDarkly client")
	}
	if !ldClient.Initialized() {
		ldClient.Close()
		utils.Logger.Fatal("LaunchDarkly client failed to initialize")
	}
	defer ldClient.Close()

	ctx := ldcontext.NewWithKind(ldcontext.Kind(LDServerContextKind), LDServerContextKey)

	useGMapsRoutesAPIFlag, err := ldClient.BoolVariation("use_gmaps_routes_api", ctx, false)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Error retrieving use_gmaps_routes_api flag")
	}
	utils.Logger.Debugf("use_gmaps_routes_api flag: %t", useGMapsRoutesAPIFlag)

	usingIsolatedSchemaFlag, err := ldClient.BoolVariation("using_isolated_schema", ctx, false)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Error retrieving using_isolated_schema flag")
	}
	utils.Logger.Debugf("using_isolated_schema flag: %t", usingIsolatedSchemaFlag)

	// Twilio from phone
	twilioFromFlag, err := ldClient.StringVariation("twilio_from_phone", ctx, "")
	if err != nil {
		utils.Logger.WithError(err).Fatal("Error retrieving twilio_from_phone flag")
	}
	utils.Logger.Debugf("twilio_from_phone flag: %s", twilioFromFlag)
	if twilioFromFlag == "" {
		utils.Logger.Warn("twilio_from_phone flag is empty, defaulting to +10005550006")
		twilioFromFlag = "+10005550006"
	}

	// SendGrid from email
	sgFromFlag, err := ldClient.StringVariation("sendgrid_from_email", ctx, "")
	if err != nil {
		utils.Logger.WithError(err).Fatal("Error retrieving sendgrid_from_email flag")
	}
	utils.Logger.Debugf("sendgrid_from_email flag: %s", sgFromFlag)
	if sgFromFlag == "" {
		utils.Logger.Warn("sendgrid_from_email flag is empty, defaulting to no-reply@thepoofapp.com")
		sgFromFlag = "no-reply@thepoofapp.com"
	}

	sgSandboxFlag, err := ldClient.BoolVariation("sendgrid_sandbox_mode", ctx, false)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Error retrieving sendgrid_sandbox_mode flag")
	}
	utils.Logger.Debugf("sendgrid_sandbox_mode flag: %t", sgSandboxFlag)

	seedDbWithTestDataFlag, err := ldClient.BoolVariation("seed_db_with_test_data", ctx, false)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Error retrieving seed_db_with_test_data flag")
	}
	utils.Logger.Debugf("seed_db_with_test_data flag: %t", seedDbWithTestDataFlag)

	openaiPhotoFlag, err := ldClient.BoolVariation("openai_photo_verification", ctx, false)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Error retrieving openai_photo_verification flag")
	}
	utils.Logger.Debugf("openai_photo_verification flag: %t", openaiPhotoFlag)

	var openaiKey string
	if openaiPhotoFlag {
		val, ok := appSecrets["OPENAI_API_KEY"]
		if !ok || val == "" {
			utils.Logger.Fatal("OPENAI_API_KEY secret missing but flag enabled")
		}
		openaiKey = val
	}

	if useGMapsRoutesAPIFlag {
		val, ok := appSecrets["GMAPS_ROUTES_API_KEY"]
		if !ok || val == "" {
			utils.Logger.Fatal("GMAPS_ROUTES_API_KEY secret missing but flag enabled")
		}
		gmapsKey = val
	}

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

	doRealMobileDeviceAttestation, err := ldClientShared.BoolVariation("do_real_mobile_device_attestation", ctx, false)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Error retrieving do_real_mobile_device_attestation flag")
	}
	utils.Logger.Debugf("do_real_mobile_device_attestation flag: %t", doRealMobileDeviceAttestation)

	corsHighSecurityFlag, err := ldClientShared.BoolVariation("cors_high_security", ctx, false)
	if err != nil {
		ldClientShared.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving cors_high_security flag")
	}
	utils.Logger.Debugf("cors_high_security flag: %t", corsHighSecurityFlag)

	var priv *ecdsa.PrivateKey
	var saJSON []byte
	if doRealMobileDeviceAttestation {
		keyPEM, _ := base64.StdEncoding.DecodeString(sharedSecrets["APPLE_DEVICE_CHECK_KEY_BASE64"])
		block, _ := pem.Decode(keyPEM)
		if block == nil {
			utils.Logger.Fatal("Failed to decode PEM block for Apple Device Check key")
		}
		privAny, _ := x509.ParsePKCS8PrivateKey(block.Bytes)
		priv = privAny.(*ecdsa.PrivateKey)
		saJSON, _ = base64.StdEncoding.DecodeString(sharedSecrets["PLAY_INTEGRITY_SA_JSON_BASE64"])
	}

	return &Config{
		OrganizationName:                     OrganizationName,
		AppName:                              AppName,
		AppPort:                              appPort,
		AppUrl:                               appUrl,
		UniqueRunNumber:                      UniqueRunNumber,
		UniqueRunnerID:                       UniqueRunnerID,
		DBUrl:                                dbURL,
		DBEncryptionKey:                      dbEncKey,
		GMapsRoutesAPIKey:                    gmapsKey,
		TwilioAccountSID:                     twilioSID,
		TwilioAuthToken:                      twilioToken,
		SendGridAPIKey:                       sgAPIKey,
		OpenAIAPIKey:                         openaiKey,
		RSAPrivateKey:                        privKey,
		RSAPublicKey:                         pubKey,
		AppleDeviceCheckKey:                  priv,
		PlayIntegritySAJSON:                  saJSON,
		LDFlag_UseGMapsRoutesAPI:             useGMapsRoutesAPIFlag,
		LDFlag_UsingIsolatedSchema:           usingIsolatedSchemaFlag,
		LDFlag_TwilioFromPhone:               twilioFromFlag,
		LDFlag_SendgridFromEmail:             sgFromFlag,
		LDFlag_SendgridSandboxMode:           sgSandboxFlag,
		LDFlag_SeedDbWithTestData:            seedDbWithTestDataFlag,
		LDFlag_DoRealMobileDeviceAttestation: doRealMobileDeviceAttestation,
		LDFlag_CORSHighSecurity:              corsHighSecurityFlag,
		LDFlag_OpenAIPhotoVerification:        openaiPhotoFlag,
	}
}

func (c *Config) Close() {}
