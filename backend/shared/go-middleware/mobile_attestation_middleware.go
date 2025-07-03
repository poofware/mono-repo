package middleware

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"

	"github.com/poofware/go-utils"
)

// MobileAttestationMiddleware intercepts requests for "mobile" platforms.
// If `useRealAttestation` is true, it decodes a base64-encoded JSON payload from
// the X-Device-Integrity header and calls the AttestationVerifier.
// If `useRealAttestation` is false, it performs a dummy check for a static token.
// On success, it places the resulting fingerprint in request context.
func MobileAttestationMiddleware(
	useRealAttestation bool,
	attVerifier *utils.AttestationVerifier,
) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			platform := utils.GetClientPlatform(r)
			isMobile := utils.IsMobile(platform)

			if isMobile {
				integrityHeader := r.Header.Get("X-Device-Integrity")
				if integrityHeader == "" {
					utils.RespondErrorWithCode(
						w,
						http.StatusBadRequest,
						utils.ErrCodeInvalidPayload,
						"Missing X-Device-Integrity header for mobile device attestation",
						nil,
					)
					return
				}

				// We also need the device ID from X-Device-ID or fallback logic.
				clientID := utils.GetClientIdentifier(r, platform)
				if clientID.Type != utils.ClientIDTypeDeviceID || clientID.Value == "" {
					utils.RespondErrorWithCode(
						w,
						http.StatusBadRequest,
						utils.ErrCodeInvalidPayload,
						"Missing or invalid X-Device-ID header for mobile device attestation",
						nil,
					)
					return
				}

				var fp string
				var payloadJSON []byte
				var err error

				if useRealAttestation && attVerifier != nil {
					// REAL flow: Decode the base64 JSON payload from the header.
					payloadJSON, err = base64.StdEncoding.DecodeString(integrityHeader)
					if err != nil {
						utils.RespondErrorWithCode(
							w,
							http.StatusBadRequest,
							utils.ErrCodeInvalidPayload,
							"X-Device-Integrity header is not valid base64",
							err,
						)
						return
					}

					var payload utils.AttestationPayload
					if err := json.Unmarshal(payloadJSON, &payload); err != nil {
						utils.RespondErrorWithCode(
							w,
							http.StatusBadRequest,
							utils.ErrCodeInvalidPayload,
							"Failed to parse attestation payload from X-Device-Integrity header",
							err,
						)
						return
					}
					if err := payload.Validate(); err != nil {
						utils.RespondErrorWithCode(
							w,
							http.StatusBadRequest,
							utils.ErrCodeInvalidPayload,
							"Invalid attestation payload structure",
							nil,
							err,
						)
						return
					}

					fp, err = attVerifier.VerifyMobileAttestation(r.Context(), platform, payload)
					if err != nil {
						if errors.Is(err, utils.ErrKeyNotFoundForAssertion) {
							utils.RespondErrorWithCode(
								w,
								http.StatusUnauthorized,
								utils.ErrCodeKeyNotFoundForAssertion,
								"App Attest key not found; re-attestation required",
								err,
							)
						} else {
							utils.RespondErrorWithCode(
								w,
								http.StatusUnauthorized,
								utils.ErrCodeUnauthorized,
								"Mobile device attestation (REAL) failed",
								err,
							)
						}
						return
					}
				} else {
					// DUMMY flow: check that the integrity token
					// is exactly "FAKE_INTEGRITY_TOKEN", then produce
					// a fake att fingerprint.
					if integrityHeader != "FAKE_INTEGRITY_TOKEN" {
						utils.RespondErrorWithCode(
							w,
							http.StatusUnauthorized,
							utils.ErrCodeUnauthorized,
							"Mobile device attestation (FAKE) failed: invalid integrity token",
							nil,
						)
						return
					}
					switch platform {
					case utils.PlatformAndroid:
						fp = "FAKE-PLAY"
					case utils.PlatformIOS:
						fp = "FAKE-IOS"
					default:
						// Should never happen if isMobile is true,
						// but just in case:
						utils.RespondErrorWithCode(
							w,
							http.StatusBadRequest,
							utils.ErrCodeInvalidPayload,
							"Unsupported mobile platform",
							nil,
						)
						return
					}
				}

				// Attach attFingerprint to context so later code can embed it in the JWT.
				ctx := context.WithValue(r.Context(), utils.CtxKeyAttestation, fp)
				next.ServeHTTP(w, r.WithContext(ctx))
				return
			}

			// If not mobile, just pass through
			next.ServeHTTP(w, r)
		})
	}
}
