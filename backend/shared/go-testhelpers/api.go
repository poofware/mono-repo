package testhelpers

import (
	"bytes"
	"io"
	"net/http"
	"net/http/cookiejar"
	"strings"

	"github.com/poofware/go-middleware"
	"github.com/stretchr/testify/require"
)

// BuildAuthRequest sets standard headers for authenticated test requests.
// It now correctly handles cookie-based auth for "web" and bearer-token auth for mobile,
// including all required headers like X-Key-Id and X-Device-Integrity.
func (h *TestHelper) BuildAuthRequest(method, reqURL, jwtString string, body []byte, platform, platformVal string) *http.Request {
	req, err := http.NewRequest(method, reqURL, bytes.NewReader(body))
	require.NoError(h.T, err)

	req.Header.Set("X-Platform", platform)

	if platform == "web" {
		req.Header.Set("X-Forwarded-For", platformVal)
		if jwtString != "" {
			// Web platform uses cookies for auth.
			req.AddCookie(&http.Cookie{
				Name:  middleware.AccessTokenCookieName,
				Value: jwtString,
				Path:  "/",
			})
		}
	} else {
		// Mobile platforms use Authorization header and other device-specific headers.
		if jwtString != "" {
			req.Header.Set("Authorization", "Bearer "+jwtString)
		}
		req.Header.Set("X-Device-ID", platformVal)
		req.Header.Set("X-Device-Integrity", "FAKE_INTEGRITY_TOKEN")

		// Set the X-Key-Id to match the expected "att" claim in the dummy JWT.
		if platform == "android" {
			req.Header.Set("X-Key-Id", "FAKE-PLAY")
		} else if platform == "ios" {
			req.Header.Set("X-Key-Id", "FAKE-IOS")
		}
	}

	if (method == http.MethodPost || method == http.MethodPut || method == http.MethodPatch) &&
		!strings.Contains(req.Header.Get("Content-Type"), "multipart/form-data") &&
		len(body) > 0 {
		req.Header.Set("Content-Type", "application/json")
	}
	return req
}

// NewHTTPClient creates an HTTP client with a cookie jar for session management.
func (h *TestHelper) NewHTTPClient() *http.Client {
	jar, err := cookiejar.New(nil)
	require.NoError(h.T, err)
	return &http.Client{Jar: jar}
}

// DoRequest performs an HTTP request and asserts that no network-level error occurred.
func (h *TestHelper) DoRequest(req *http.Request, client *http.Client) *http.Response {
	if client.Jar != nil {
		client.Jar.SetCookies(req.URL, req.Cookies())
	}
	resp, err := client.Do(req)
	require.NoError(h.T, err, "HTTP request failed")
	return resp
}

// ReadBody reads the response body and returns it as a string for logging or inspection.
func (h *TestHelper) ReadBody(resp *http.Response) string {
	if resp == nil || resp.Body == nil {
		return "<nil response or body>"
	}
	bodyBytes, err := io.ReadAll(resp.Body)
	// After reading, we need to restore the body so it can be read again if needed.
	resp.Body = io.NopCloser(bytes.NewBuffer(bodyBytes))
	require.NoError(h.T, err, "Failed to read response body")
	return string(bodyBytes)
}
