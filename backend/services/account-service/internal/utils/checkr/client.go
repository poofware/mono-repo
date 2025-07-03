package checkr

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"path"
	"strconv"
	"strings"
	"time"
)

// RateLimitError is returned when the server responds with HTTP 429.
type RateLimitError struct {
	Message        string
	ResetTimestamp time.Time // from X-RateLimit-Reset, if present
}

func (r *RateLimitError) Error() string {
	if !r.ResetTimestamp.IsZero() {
		return fmt.Sprintf("rate limit exceeded; retry after %s", r.ResetTimestamp.Format(time.RFC3339))
	}
	return fmt.Sprintf("rate limit exceeded: %s", r.Message)
}

// ConflictError is returned for 409 conflicts (e.g. duplicate candidate, idempotency collisions).
type ConflictError struct {
	Message string
}

func (c *ConflictError) Error() string {
	return fmt.Sprintf("conflict (409): %s", c.Message)
}

// CheckrClient manages communication with the Checkr API.
type CheckrClient struct {
	BaseURL          *url.URL
	APIKey           string
	HTTPCheckrClient *http.Client
	MaxRetries       int           // how many times to retry on 429
	RetryInitial     time.Duration // initial backoff
}

const (
	baseURL        = "https://api.checkr.com/v1"
	stagingBaseURL = "https://api.checkr-staging.com/v1"
)

// NewCheckrClient initializes a new Checkr client with the given API key.
// If baseURL is empty, defaults to "https://api.checkr.com/v1".
// maxRetries and retryInitial define how we handle 429 rate-limits.
func NewCheckrClient(apiKey string, stagingMode bool, maxRetries int, retryInitial time.Duration) (*CheckrClient, error) {
	base := baseURL
	if stagingMode {
		base = stagingBaseURL
	}
	parsed, err := url.Parse(base)
	if err != nil {
		return nil, fmt.Errorf("invalid baseURL: %w", err)
	}
	if maxRetries < 0 {
		maxRetries = 0
	}
	if retryInitial <= 0 {
		retryInitial = 1 * time.Second
	}

	return &CheckrClient{
		BaseURL:          parsed,
		APIKey:           apiKey,
		HTTPCheckrClient: &http.Client{Timeout: 30 * time.Second},
		MaxRetries:       maxRetries,
		RetryInitial:     retryInitial,
	}, nil
}

// requestOptions holds optional request-specific headers, e.g. for Idempotency keys, etc.
type requestOptions struct {
	IdempotencyKey string
}

// doRequest is a helper to build, execute, parse an HTTP request with minimal backoff for 429.
func (c *CheckrClient) doRequest(ctx context.Context, method, reqPath string, body any, out any, opts *requestOptions) error {
	var attempt int
	var backoff = c.RetryInitial

	for {
		err := c.doOnce(ctx, method, reqPath, body, out, opts)
		if err == nil {
			return nil
		}

		// Check if it's a RateLimitError
		var rlErr *RateLimitError
		if errors.As(err, &rlErr) {
			if attempt < c.MaxRetries {
				// Wait then retry
				attempt++
				time.Sleep(backoff)
				backoff *= 2 // simple exponential
				continue
			}
			// If max retries exceeded, return the rate-limit error
			return err
		}
		// For 409 conflicts or other errors, we won't auto-retry: return immediately
		return err
	}
}

// doOnce performs a single HTTP request attempt (no retries).
func (c *CheckrClient) doOnce(ctx context.Context, method, reqPath string, body any, out any, opts *requestOptions) error {
	// Build full URL
	u := *c.BaseURL
	u.Path = path.Join(c.BaseURL.Path, reqPath)

	var reqBody io.Reader
	if body != nil {
		jsonBytes, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("failed to marshal request body: %w", err)
		}
		reqBody = bytes.NewReader(jsonBytes)
	}

	req, err := http.NewRequestWithContext(ctx, method, u.String(), reqBody)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.SetBasicAuth(c.APIKey, "")

	if opts != nil && opts.IdempotencyKey != "" {
		req.Header.Set("Idempotency-Key", opts.IdempotencyKey)
	}

	resp, err := c.HTTPCheckrClient.Do(req)
	if err != nil {
		return fmt.Errorf("failed to make request: %w", err)
	}
	defer resp.Body.Close()

	// If non-2xx, parse the body for errors
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return c.handleHTTPError(resp)
	}

	// If out is nil, we discard the response body
	if out == nil {
		io.Copy(io.Discard, resp.Body)
		return nil
	}

	if err := json.NewDecoder(resp.Body).Decode(out); err != nil {
		return fmt.Errorf("failed to decode response: %w", err)
	}
	return nil
}

// handleHTTPError handles 4xx/5xx responses from Checkr, tries to parse the body, and returns an appropriate error.
func (c *CheckrClient) handleHTTPError(resp *http.Response) error {
	status := resp.StatusCode
	bodyBytes, _ := io.ReadAll(resp.Body)

	// Attempt to parse known error shape: { "error": "some message" }
	var apiErr ErrorResponse
	if err := json.Unmarshal(bodyBytes, &apiErr); err != nil {
		// If we cannot parse it as JSON, just store a generic message
		apiErr.Error = strings.TrimSpace(string(bodyBytes))
	}

	switch status {
	case 400:
		return fmt.Errorf("bad request (400): %s", apiErr.Error)
	case 401:
		return fmt.Errorf("unauthorized (401): %s", apiErr.Error)
	case 403:
		return fmt.Errorf("forbidden (403): %s", apiErr.Error)
	case 404:
		// Some endpoints return 404 "not found"
		return fmt.Errorf("not found (404): %s", apiErr.Error)
	case 409:
		// Likely a conflict error (duplicate candidate, etc.)
		return &ConflictError{Message: apiErr.Error}
	case 429:
		// Rate limit
		resetStr := resp.Header.Get("X-RateLimit-Reset")
		var resetTime time.Time
		if resetStr != "" {
			if sec, err := strconv.ParseInt(resetStr, 10, 64); err == nil {
				resetTime = time.Unix(sec, 0)
			}
		}
		return &RateLimitError{Message: apiErr.Error, ResetTimestamp: resetTime}
	default:
		return fmt.Errorf("http error (%d): %s", status, apiErr.Error)
	}
}

// NEW: CreateSessionToken creates a session token for the Web SDK.
func (c *CheckrClient) CreateSessionToken(ctx context.Context, candidateID string) (*SessionToken, error) {
	endpoint := "web_sdk/session_tokens"
	body := map[string]any{
		"scopes":       []string{"order"},
		"direct":		true,
	}
	var token SessionToken
	if err := c.doRequest(ctx, "POST", endpoint, body, &token, nil); err != nil {
		return nil, fmt.Errorf("CreateSessionToken error: %w", err)
	}
	return &token, nil
}
