package config

import (
	"fmt"
	"os"
	"time"

	"github.com/launchdarkly/go-sdk-common/v3/ldcontext"
	ld "github.com/launchdarkly/go-server-sdk/v7"
	"github.com/poofware/go-utils"
)

type Config struct {
	OrganizationName string
	AppName          string
	AppPort          string
	AppUrl           string
	SendgridAPIKey   string

	// Feature-flag snapshots
	LDFlag_SendgridFromEmail   string
	LDFlag_ValidateEmailWithSG bool

	ldClient *ld.LDClient
}

const (
	OrganizationName    = utils.OrganizationName
	LDConnectionTimeout = 5 * time.Second
)

// build-time overrides, set with -ldflags (same scheme as other services)
var (
	AppName             string
	UniqueRunNumber     string
	UniqueRunnerID      string
	LDServerContextKey  string
	LDServerContextKind string
)

// LoadConfig reproduces the exact ordering / logging style of account-service.
func LoadConfig() *Config {
	//----------------------------------------------------------------------
	// 1) Validate required ldflags
	//----------------------------------------------------------------------
	if AppName == "" {
		utils.Logger.Fatal("AppName was not provided via ldflags")
	}
	if UniqueRunNumber == "" {
		utils.Logger.Fatal("UniqueRunNumber was not provided via ldflags")
	}
	if UniqueRunnerID == "" {
		utils.Logger.Fatal("UniqueRunnerID was not provided via ldflags")
	}
	if LDServerContextKey == "" {
		utils.Logger.Fatal("LDServerContextKey was not provided via ldflags")
	}
	if LDServerContextKind == "" {
		utils.Logger.Fatal("LDServerContextKind was not provided via ldflags")
	}

	utils.Logger.Info("Loading config for app: ", AppName)

	//----------------------------------------------------------------------
	// 2) Runtime environment vars
	//----------------------------------------------------------------------
	env := os.Getenv("ENV")
	if env == "" {
		utils.Logger.Fatal("ENV env var is missing")
	}
	appURL := os.Getenv("APP_URL_FROM_ANYWHERE")
	if appURL == "" {
		utils.Logger.Fatal("APP_URL_FROM_ANYWHERE env var is missing")
	}
	appPort := os.Getenv("APP_PORT")
	if appPort == "" {
		utils.Logger.Fatal("APP_PORT env var is missing")
	}

	//----------------------------------------------------------------------
	// 3) BWS secrets (SendGrid + LD SDK key)
	//----------------------------------------------------------------------
	client, err := utils.NewBWSSecretsClient()
	if err != nil {
		utils.Logger.WithError(err).Fatal("Init BWS client")
	}
	bwsProjectName := fmt.Sprintf("%s-%s", AppName, env)
	appSecrets, err := client.GetBWSSecrets(bwsProjectName)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Fetch BWS secrets")
	}

	//----------------------------------------------------------------------
	// Fetch shared secrets from BWS (shared-env).
	//----------------------------------------------------------------------
	utils.Logger.Debugf("Fetching shared secrets from BWS for %s-%s", "shared", env)
	bwsSharedProjectName := fmt.Sprintf("shared-%s", env)
	sharedSecrets, err := client.GetBWSSecrets(bwsSharedProjectName)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to fetch shared secrets from BWS")
	}

	ldSDK, ok := appSecrets["LD_SDK_KEY"]
	if !ok || ldSDK == "" {
		utils.Logger.Fatal("LD_SDK_KEY missing in BWS secrets")
	}

	//----------------------------------------------------------------------
	// 4) LaunchDarkly client & flags
	//----------------------------------------------------------------------
	ldClient, err := ld.MakeClient(ldSDK, LDConnectionTimeout)
	if err != nil {
		utils.Logger.WithError(err).Fatal("Failed to create LaunchDarkly client")
	}
	if !ldClient.Initialized() {
		ldClient.Close()
		utils.Logger.Fatal("LaunchDarkly client failed to initialize")
	}
	defer ldClient.Close()

	ctx := ldcontext.NewWithKind(ldcontext.Kind(LDServerContextKind), LDServerContextKey)

	fromEmail, err := ldClient.StringVariation("sendgrid_from_email", ctx, "")
	if err != nil || fromEmail == "" {
		ldClient.Close()
		utils.Logger.Fatal("sendgrid_from_email flag error / empty")
	}
	utils.Logger.Debugf("sendgrid_from_email flag: %s", fromEmail)

	validateWithSG, err := ldClient.BoolVariation("validate_email_with_sendgrid", ctx, false)
	if err != nil {
		ldClient.Close()
		utils.Logger.Fatal("validate_email_with_sendgrid flag error")
	}
	utils.Logger.Debugf("validate_email_with_sendgrid flag: %t", validateWithSG)

	sgAPI, ok := sharedSecrets["SENDGRID_API_KEY"]
	if !ok || sgAPI == "" {
		utils.Logger.Fatal("SENDGRID_API_KEY missing in BWS secrets")
	}

	utils.Logger.Infof("Loaded config for %s (%s)", AppName, env)

	return &Config{
		OrganizationName:           OrganizationName,
		AppName:                    AppName,
		AppPort:                    appPort,
		AppUrl:                     appURL,
		SendgridAPIKey:             sgAPI,
		LDFlag_SendgridFromEmail:   fromEmail,
		LDFlag_ValidateEmailWithSG: validateWithSG,
		ldClient:                   ldClient,
	}
}

func (c *Config) Close() {
}
