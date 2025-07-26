package config

import (
	"crypto/rsa"
	"encoding/base64"
	"fmt"
	"os"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/launchdarkly/go-sdk-common/v3/ldcontext"
	ld "github.com/launchdarkly/go-server-sdk/v7"
	"github.com/poofware/go-utils"
)

type Config struct {
	OrganizationName                     string
	AppName                              string
	AppPort                              string
	AppUrl                               string
	DBUrl                                string
	DBEncryptionKey                      []byte
	StripeSecretKey                      string
	StripeWebhookSecret                  string
	SendgridAPIKey                       string
	RSAPrivateKey                        *rsa.PrivateKey
	RSAPublicKey                         *rsa.PublicKey
	UniqueRunNumber                      string
	UniqueRunnerID                       string
	LDFlag_UsingIsolatedSchema           bool
	LDFlag_DynamicStripeWebhookEndpoint  bool
	LDFlag_UseShortPayPeriod             bool
	LDFlag_DoRealMobileDeviceAttestation bool
	LDFlag_SendgridFromEmail             string
	LDFlag_SendgridSandboxMode           bool
	LDFlag_CORSHighSecurity              bool
	LDFlag_SeedDbWithTestData            bool
}

const (
	OrganizationName    = utils.OrganizationName
	LDConnectionTimeout = 5 * time.Second
)

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

	dbURL, ok := appSecrets["DB_URL"]
	if !ok || dbURL == "" {
		utils.Logger.Fatalf("DB_URL not found in BWS secrets (%s)", appSecretsName)
	}

	ldSDKKey, ok := appSecrets["LD_SDK_KEY"]
	if !ok || ldSDKKey == "" {
		utils.Logger.Fatalf("LD_SDK_KEY not found in BWS secrets (%s)", appSecretsName)
	}

	dbEncB64, ok := sharedSecrets["DB_ENCRYPTION_KEY_BASE64"]
	if !ok || dbEncB64 == "" {
		utils.Logger.Fatalf("DB_ENCRYPTION_KEY_BASE64 not found in BWS (%s)", sharedSecretsName)
	}
	dbEncKey, err := base64.StdEncoding.DecodeString(dbEncB64)
	if err != nil || len(dbEncKey) != 32 {
		utils.Logger.Fatal("DB_ENCRYPTION_KEY_BASE64 invalid – expect 32-byte key")
	}

	privB64, ok := sharedSecrets["RSA_PRIVATE_KEY_BASE64"]
	if !ok {
		utils.Logger.Fatalf("RSA_PRIVATE_KEY_BASE64 not found in BWS (%s)", sharedSecretsName)
	}
	privPEM, _ := base64.StdEncoding.DecodeString(privB64)
	privKey, err := jwt.ParseRSAPrivateKeyFromPEM(privPEM)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to parse RSA private key")
	}

	pubB64, ok := sharedSecrets["RSA_PUBLIC_KEY_BASE64"]
	if !ok {
		utils.Logger.Fatalf("RSA_PUBLIC_KEY_BASE64 not found in BWS (%s)", sharedSecretsName)
	}
	pubPEM, _ := base64.StdEncoding.DecodeString(pubB64)
	pubKey, err := jwt.ParseRSAPublicKeyFromPEM(pubPEM)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to parse RSA public key")
	}

	stripeSecretKey, ok := sharedSecrets["STRIPE_SECRET_KEY"]
	if !ok || stripeSecretKey == "" {
		utils.Logger.Fatal("STRIPE_SECRET_KEY not found in BWS secrets (shared-env)")
	}

	sendgridAPIKey, ok := sharedSecrets["SENDGRID_API_KEY"]
	if !ok || sendgridAPIKey == "" {
		utils.Logger.Fatalf("SENDGRID_API_KEY not found in BWS secrets (%s)", appSecretsName)
	}

	ldClient, err := ld.MakeClient(ldSDKKey, LDConnectionTimeout)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to create LaunchDarkly client")
	}
	defer ldClient.Close()

	ctx := ldcontext.NewWithKind(ldcontext.Kind(LDServerContextKind), LDServerContextKey)

	usingIsolatedSchemaFlag, err := ldClient.BoolVariation("using_isolated_schema", ctx, false)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Error retrieving using_isolated_schema flag")
	}
	utils.Logger.Debugf("using_isolated_schema flag: %t", usingIsolatedSchemaFlag)

	dynamicStripeWebhookFlag, err := ldClient.BoolVariation("dynamic_stripe_webhook_endpoint", ctx, false)
	if err != nil {
		ldClient.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving dynamic_stripe_webhook_endpoint flag")
	}
	utils.Logger.Debugf("dynamic_stripe_webhook_endpoint flag: %t", dynamicStripeWebhookFlag)

	useShortPayPeriodFlag, err := ldClient.BoolVariation("use_short_pay_period", ctx, false)
	if err != nil {
		ldClient.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving use_short_pay_period flag")
	}
	utils.Logger.Debugf("use_short_pay_period flag: %t", useShortPayPeriodFlag)

	sgFromFlag, err := ldClient.StringVariation("sendgrid_from_email", ctx, "")
	if err != nil {
		ldClient.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving sendgrid_from_email flag")
	}
	if sgFromFlag == "" {
		sgFromFlag = "no-reply@thepoofapp.com" // Fallback
	}

	sgSandboxFlag, err := ldClient.BoolVariation("sendgrid_sandbox_mode", ctx, false)
	if err != nil {
		ldClient.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving sendgrid_sandbox_mode flag")
	}

	seedDbWithTestDataFlag, err := ldClient.BoolVariation("seed_db_with_test_data", ctx, false)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Error retrieving seed_db_with_test_data flag")
	}
	utils.Logger.Debugf("seed_db_with_test_data flag: %t", seedDbWithTestDataFlag)

	ldSDKKeyShared, ok := sharedSecrets["LD_SDK_KEY_SHARED"]
	if !ok {
		utils.Logger.Fatal("LD_SDK_KEY_SHARED not found in BWS secrets (shared-env)")
	}

	ldClientShared, err := ld.MakeClient(ldSDKKeyShared, LDConnectionTimeout)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to create shared LaunchDarkly client")
	}
	defer ldClientShared.Close()

	doRealMobileDeviceAttestationFlag, err := ldClientShared.BoolVariation("do_real_mobile_device_attestation", ctx, false)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Error retrieving do_real_mobile_device_attestation flag")
	}
	utils.Logger.Debugf("do_real_mobile_device_attestation flag: %t", doRealMobileDeviceAttestationFlag)

	corsHighSecurityFlag, err := ldClientShared.BoolVariation("cors_high_security", ctx, false)
	if err != nil {
		ldClientShared.Close()
		utils.Logger.WithError(err).Fatal("Error retrieving cors_high_security flag")
	}
	utils.Logger.Debugf("cors_high_security flag: %t", corsHighSecurityFlag)

	var stripeWebhookSecret string
	if !dynamicStripeWebhookFlag {
		var ok bool
		stripeWebhookSecret, ok = sharedSecrets["STRIPE_WEBHOOK_SECRET"]
		if !ok || stripeWebhookSecret == "" {
			utils.Logger.Fatalf("STRIPE_WEBHOOK_SECRET not found in BWS secrets (%s)", sharedSecretsName)
		}
	}

	return &Config{
		OrganizationName:                     OrganizationName,
		AppName:                              AppName,
		AppPort:                              appPort,
		AppUrl:                               appUrl,
		DBUrl:                                dbURL,
		DBEncryptionKey:                      dbEncKey,
		StripeSecretKey:                      stripeSecretKey,
		StripeWebhookSecret:                  stripeWebhookSecret,
		SendgridAPIKey:                       sendgridAPIKey,
		RSAPrivateKey:                        privKey,
		RSAPublicKey:                         pubKey,
		UniqueRunNumber:                      UniqueRunNumber,
		UniqueRunnerID:                       UniqueRunnerID,
		LDFlag_UsingIsolatedSchema:           usingIsolatedSchemaFlag,
		LDFlag_DynamicStripeWebhookEndpoint:  dynamicStripeWebhookFlag,
		LDFlag_UseShortPayPeriod:             useShortPayPeriodFlag,
		LDFlag_DoRealMobileDeviceAttestation: doRealMobileDeviceAttestationFlag,
		LDFlag_SendgridFromEmail:             sgFromFlag,
		LDFlag_SendgridSandboxMode:           sgSandboxFlag,
		LDFlag_CORSHighSecurity:              corsHighSecurityFlag,
		LDFlag_SeedDbWithTestData:            seedDbWithTestDataFlag,
	}
}

func (c *Config) Close() {}
