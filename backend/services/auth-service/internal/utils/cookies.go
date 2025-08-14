// cookie_utils.go
//
// Hardened helper for issuing / clearing JWT cookies + the full
// security-header block (May 2025 best-practice checklist).

package utils

import (
	"fmt"
	"net/http"
	"time"

	"github.com/poofware/mono-repo/backend/shared/go-middleware" // ⟵ use the canonical constants
)

/*
   --------------------------------------------------------------------
   Public API
   --------------------------------------------------------------------
   SetAuthCookies(w,
       accessToken, refreshToken,
       accessTTL,   refreshTTL,
       refreshPath,            // e.g. "/auth/v1/pm/refresh_token"
       sameSiteHighSecurity,
   )

   ClearAuthCookies(w, refreshPath, sameSiteHighSecurity)
*/

// SetAuthCookies writes two secure cookies **and** every response
// header recommended for token-bearing responses.
func SetAuthCookies(
	w http.ResponseWriter,
	accessToken string,
	refreshToken string,
	accessTTL time.Duration,
	refreshTTL time.Duration,
	refreshPath string,
	sameSiteHighSecurity bool,
) {
	if accessToken == "" || refreshToken == "" {
		return
	}

	accessSameSitePolicy := "Lax"
	refreshSameSitePolicy := "Strict"
	if !sameSiteHighSecurity {
		accessSameSitePolicy = "None"
		refreshSameSitePolicy = "None"
	}

	writeCookie(
		w,
		middleware.AccessTokenCookieName,
		accessToken,
		"/", // Access token accompanies every API call
		int(accessTTL.Seconds()),
		accessSameSitePolicy,
	)

	writeCookie(
		w,
		middleware.RefreshTokenCookieName,
		refreshToken,
		refreshPath, // Only the refresh endpoint ever receives it
		int(refreshTTL.Seconds()),
		refreshSameSitePolicy,
	)

	addSecurityHeaders(w)
}

// ClearAuthCookies deletes both cookies (desktop logout).
func ClearAuthCookies(w http.ResponseWriter, refreshPath string, sameSiteHighSecurity bool) {
	expired := time.Now().Add(-1 * time.Hour).UTC().Format(http.TimeFormat)

	accessSameSitePolicy := "Lax"
	refreshSameSitePolicy := "Strict"
	if !sameSiteHighSecurity {
		accessSameSitePolicy = "None"
		refreshSameSitePolicy = "None"
	}

	w.Header().Add("Set-Cookie",
		fmt.Sprintf("%s=; Path=/; Expires=%s; Max-Age=0; SameSite=%s; Secure; HttpOnly; Priority=High",
			middleware.AccessTokenCookieName,
			expired,
			accessSameSitePolicy,
		))

	w.Header().Add("Set-Cookie",
		fmt.Sprintf("%s=; Path=%s; Expires=%s; Max-Age=0; SameSite=%s; Secure; HttpOnly; Priority=High",
			middleware.RefreshTokenCookieName,
			refreshPath,
			expired,
			refreshSameSitePolicy,
		))

	addSecurityHeaders(w)
}

//
// ────────────────────────── internal helpers ──────────────────────────
//

func writeCookie(
	w http.ResponseWriter,
	name, value, path string,
	maxAge int,
	sameSitePolicy string, // "Lax" or "Strict"
) {
	expires := time.Now().
		Add(time.Duration(maxAge) * time.Second).
		UTC().
		Format(http.TimeFormat)

	line := fmt.Sprintf("%s=%s; Path=%s; Max-Age=%d; Expires=%s; SameSite=%s; Secure; HttpOnly; Priority=High",
		name, value, path, maxAge, expires, sameSitePolicy)

	w.Header().Add("Set-Cookie", line)
}

// addSecurityHeaders applies the transport, CSP, COOP/COEP and
// privacy headers spelled out in the May 2025 checklist.
func addSecurityHeaders(w http.ResponseWriter) {
	// 1 transport / caching
	w.Header().Set("Strict-Transport-Security", "max-age=63072000; includeSubDomains; preload")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Pragma", "no-cache")

	// 2 content isolation & click-jacking
	w.Header().Set("Content-Security-Policy", "default-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("X-Frame-Options", "DENY") // legacy fallback

	// 3 Spectre / XS-leak mitigations
	w.Header().Set("Cross-Origin-Opener-Policy", "same-origin")
	w.Header().Set("Cross-Origin-Embedder-Policy", "require-corp")
	w.Header().Set("Cross-Origin-Resource-Policy", "same-site")

	// 4 referrer & feature scoping
	w.Header().Set("Referrer-Policy", "strict-origin-when-cross-origin")
	w.Header().Set("Permissions-Policy", "geolocation=(), camera=(), microphone=(), interest-cohort=()")
}

