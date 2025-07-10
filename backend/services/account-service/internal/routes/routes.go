package routes

const (
	// Health
	Health = "/health"

	// Worker (base)
	WorkerBase               = "/api/v1/account/worker"
	WorkerSubmitPersonalInfo = "/api/v1/account/worker/personal-info"

	// PM (base)
	PMBase       = "/api/v1/account/pm"
	PMProperties = "/api/v1/account/pm/properties"

	// ───────────────────────────────
	// Worker / Stripe
	// ───────────────────────────────
	WorkerStripeConnectFlowURL     = "/api/v1/account/worker/stripe/connect-flow"
	WorkerStripeConnectFlowReturn  = "/api/v1/account/worker/stripe/connect-flow-return"
	WorkerStripeConnectFlowRefresh = "/api/v1/account/worker/stripe/connect-flow-refresh"
	WorkerStripeConnectFlowStatus  = "/api/v1/account/worker/stripe/connect-flow-status"
	WorkerStripeExpressLoginLink   = "/api/v1/account/worker/stripe/express-login-link" // NEW

	WorkerStripeIdentityFlowURL    = "/api/v1/account/worker/stripe/identity-flow"
	WorkerStripeIdentityFlowReturn = "/api/v1/account/worker/stripe/identity-flow-return"
	WorkerStripeIdentityFlowStatus = "/api/v1/account/worker/stripe/identity-flow-status"

	// ───────────────────────────────
	// Stripe Webhook (all roles)
	// ───────────────────────────────
	AccountStripeWebhook      = "/api/v1/account/stripe/webhook"
	AccountStripeWebhookCheck = "/api/v1/account/stripe/webhook/check"

	// ───────────────────────────────
	// Universal / App‑links
	// ───────────────────────────────
	WorkerUniversalLinkStripeConnectReturn  = "/poofworker/stripe-connect-return"
	WorkerUniversalLinkStripeConnectRefresh = "/poofworker/stripe-connect-refresh"
	WorkerUniversalLinkStripeIdentityReturn = "/poofworker/stripe-identity-return"

	// ───────────────────────────────
	// Well‑known metadata
	// ───────────────────────────────
	WellKnownAppleAppSiteAssociation = "/.well-known/apple-app-site-association"
	WellKnownAssetLinksJson          = "/.well-known/assetlinks.json"

	// ───────────────────────────────
	// Checkr (background check)
	// ───────────────────────────────
	CheckrWebhook            = "/api/v1/account/checkr/webhook"
	WorkerCheckrInvitation   = "/api/v1/account/worker/checkr/invitation"
	WorkerCheckrStatus       = "/api/v1/account/worker/checkr/status"
	WorkerCheckrReportETA    = "/api/v1/account/worker/checkr/report-eta"
	WorkerCheckrOutcome      = "/api/v1/account/worker/checkr/outcome"
	WorkerCheckrSessionToken = "/api/v1/account/worker/checkr/session-token"

	// ───────────────────────────────
	// Admin Panel (Relative Paths)
	// ───────────────────────────────
	AdminBase       = "/api/v1/account/admin" // Base prefix for the admin sub-router
	AdminPM         = "/property-managers"
	AdminPMSearch   = "/property-managers/search"
	AdminPMSnapshot = "/property-manager/snapshot"
	AdminProperties = "/properties"
	AdminBuildings  = "/property-buildings"
	AdminUnits      = "/units"
	AdminDumpsters  = "/dumpsters"
)