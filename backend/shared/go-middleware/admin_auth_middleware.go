package middleware

import (
	"context"
	"crypto/rsa"
	"errors"
	"net/http"

	"github.com/golang-jwt/jwt/v5"
	"github.com/poofware/go-utils"
)

// AdminAuthMiddleware validates a JWT and ensures it contains the "admin" role.
// It is intended for admin-only endpoints. It expects a web-style token from a cookie.
func AdminAuthMiddleware(pub *rsa.PublicKey) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Admins are always on the "web" platform
			platform := utils.PlatformWeb
			clientID := utils.GetClientIdentifier(r, platform)

			tokenStr, err := extractAccessToken(r, platform)
			if err != nil {
				utils.RespondErrorWithCode(
					w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, err.Error(), nil,
				)
				return
			}

			// Validate the token structure and signature, but without device attestation checks
			// as those are mobile-specific.
			tok, vErr := ValidateToken(
				r.Context(),
				tokenStr,
				clientID,
				pub,
				platform,
				"", // keyID is for mobile
				false, // useRealAttestation is for mobile
			)
			if vErr != nil || !tok.Valid {
				if errors.Is(vErr, jwt.ErrTokenExpired) {
					utils.RespondErrorWithCode(
						w, http.StatusUnauthorized, utils.ErrCodeTokenExpired, "Token expired", vErr,
					)
					return
				}
				utils.RespondErrorWithCode(
					w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, "Invalid token", vErr,
				)
				return
			}

			claims, ok := tok.Claims.(jwt.MapClaims)
			if !ok {
				utils.RespondErrorWithCode(
					w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, "Invalid claims", nil,
				)
				return
			}

			// Check for subject (the admin's user ID)
			sub, ok := claims["sub"].(string)
			if !ok {
				utils.RespondErrorWithCode(
					w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, "Missing subject", nil,
				)
				return
			}

			// Check for "admin" role
			role, ok := claims["role"].(string)
			if !ok || role != "admin" {
				utils.RespondErrorWithCode(
					w, http.StatusForbidden, utils.ErrCodeUnauthorized, "Insufficient permissions", nil,
				)
				return
			}

			ctx := context.WithValue(r.Context(), ContextKeyUserID, sub)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}