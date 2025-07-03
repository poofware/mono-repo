package middleware

import (
	"context"
	"crypto/rsa"
	"errors"
	"net/http"

	"github.com/golang-jwt/jwt/v5"
	"github.com/poofware/go-utils"
)

// OptionalAuthMiddleware is identical to AuthMiddleware
// except that it lets the request through if *no* token is present.
func OptionalAuthMiddleware(pub *rsa.PublicKey, useRealAttestation bool) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			platform := utils.GetClientPlatform(r)
			clientID := utils.GetClientIdentifier(r, platform)
			headerKeyID := r.Header.Get("X-Key-Id") // pass to JWT validation

			tokenStr, _ := extractAccessToken(r, platform) // ignore error here
			if tokenStr == "" {
				next.ServeHTTP(w, r) // unauthenticated – allowed
				return
			}

			tok, vErr := ValidateToken(
				r.Context(),
				tokenStr,
				clientID,
				pub,
				platform,
				headerKeyID,
				useRealAttestation,
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

			if claims, ok := tok.Claims.(jwt.MapClaims); ok {
				if sub, ok := claims["sub"].(string); ok {
					ctx := context.WithValue(r.Context(), ContextKeyUserID, sub)
					next.ServeHTTP(w, r.WithContext(ctx))
					return
				}
			}
			next.ServeHTTP(w, r)
		})
	}
}

