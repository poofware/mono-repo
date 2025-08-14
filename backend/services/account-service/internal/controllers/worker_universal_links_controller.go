package controllers

import (
	"fmt"
	"net/http"

	"github.com/poofware/mono-repo/backend/services/account-service/internal/routes"
)

// fallbackTemplate is a simple HTML template that:
//  1) Attempts to open the Poof Worker app via a custom scheme on page load.
//  2) Displays a fallback message if the app isn't opened.
//  3) Provides a single button to open the universal link manually.
const fallbackTemplate = `<!DOCTYPE html>
<html>
<head>
    <title>Returning to Poof Worker App</title>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;600;700&display=swap" rel="stylesheet">
    <script>
        function openApp() {
            // Attempt to open the Poof Worker app via the custom scheme:
            window.location.href = "%s";

            // After 1500ms, if the app isn't opened, show the fallback install/open messages.
            setTimeout(function() {
                document.getElementById('fallback-message').style.display = 'block';
            }, 2000);
        }

        function openUniversalLink() {
            // Attempt to open via universal link:
            window.location.href = "%s";
        }

        window.onload = openApp;
    </script>
    <style>
      body {
        margin: 0;
        padding: 0;
        font-family: 'Poppins', sans-serif;
        background: #FAFAFA;
        color: #333;
      }
      .container {
        max-width: 600px;
        margin: 0 auto;
        padding: 2rem 1rem;
        text-align: center;
      }
      .logo {
        width: 96px;
        margin-bottom: 2rem;
      }
      h1 {
        font-size: 1.5rem;
        margin-bottom: 1rem;
      }
      p, li {
        line-height: 1.6;
        color: #6b7280;
      }
      #fallback-message {
        display: none;
        margin-top: 2rem;
        background: #fff;
        border: 1px solid #DDD;
        padding: 1.5rem;
        border-radius: 8px;
      }
      a {
        color: #743ee4;
        text-decoration: none;
      }
      a:hover {
        text-decoration: underline;
      }
      button {
        margin-top: 1rem;
        background-color: #743ee4;
        color: #fff;
        border: none;
        padding: 0.75rem 1.5rem;
        border-radius: 8px;
        cursor: pointer;
        font-family: 'Poppins', sans-serif;
        font-weight: 600;
        font-size: 1rem;
      }
      button:hover {
        opacity: 0.9;
      }
      ul {
        list-style: none;
        padding: 0;
        margin-top: 1rem;
      }
    </style>
</head>
<body>
    <div class="container">
      <img src="https://thepoofapp.com/assets/images/POOF_LOGO-LC_BW.svg" alt="Poof Logo" class="logo" />
      <h1>Returning to Poof Worker App...</h1>
      <p>Please wait while we attempt to open the Poof Worker app.</p>

      <div id="fallback-message">
        <p>
          If the app did not open automatically, please try opening it again with the button below.
        </p>
        <button onclick="openUniversalLink()">Open Poof Worker App</button>
        <p style="margin-top: 1.5rem;">Or simply open the Poof Worker app manually on your device.</p>
      </div>
    </div>
</body>
</html>
`

// fallbackHTML returns HTML with the deep link for the custom scheme (auto-triggered)
// and a corresponding universal link (manual button) injected.
func (c *WorkerUniversalLinksController) fallbackHTML(deepLinkRoute string) string {
	// Custom scheme: e.g., poofworker://poofworker/stripe-connect-return
	customSchemeLink := fmt.Sprintf("%s://%s", DeepLinkScheme, deepLinkRoute)

	// Universal link: e.g., https://YOURDOMAIN/poofworker/stripe-connect-return
	universalLink := fmt.Sprintf("%s%s", c.AppUrl, deepLinkRoute)

	return fmt.Sprintf(fallbackTemplate, customSchemeLink, universalLink)
}

// WorkerUniversalLinksController handles requests to universal link endpoints.
type WorkerUniversalLinksController struct {
	AppUrl string
}

// NewWorkerUniversalLinksController creates a new instance of WorkerUniversalLinksController.
func NewWorkerUniversalLinksController(appUrl string) *WorkerUniversalLinksController {
	return &WorkerUniversalLinksController{
		AppUrl: appUrl,
	}
}

// WorkerStripeConnectReturnHandler -> GET /poofworker/stripe-connect-return
func (c *WorkerUniversalLinksController) WorkerStripeConnectReturnHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)

	html := c.fallbackHTML(routes.WorkerUniversalLinkStripeConnectReturn)
	_, _ = w.Write([]byte(html))
}

// WorkerStripeConnectRefreshHandler -> GET /poofworker/stripe-connect-refresh
func (c *WorkerUniversalLinksController) WorkerStripeConnectRefreshHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)

	html := c.fallbackHTML(routes.WorkerUniversalLinkStripeConnectRefresh)
	_, _ = w.Write([]byte(html))
}

// WorkerStripeIdentityReturnHandler -> GET /poofworker/stripe-identity-return
func (c *WorkerUniversalLinksController) WorkerStripeIdentityReturnHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)

	html := c.fallbackHTML(routes.WorkerUniversalLinkStripeIdentityReturn)
	_, _ = w.Write([]byte(html))
}
