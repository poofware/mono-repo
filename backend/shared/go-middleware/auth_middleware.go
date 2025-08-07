package middleware

import (
	"context"
	"crypto/rsa"
	"errors"
	"net/http"
	"strings"

	"github.com/golang-jwt/jwt/v5"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

type contextKey string

const (
	ContextKeyUserID = contextKey("userID")

	// Cookie names follow the __Host- prefix rule (no Domain attribute allowed)
	AccessTokenCookieName  = "__Host-accessToken"
	RefreshTokenCookieName = "auth_refreshToken"
)

// AuthMiddleware – for normal-protected endpoints. If token is missing or invalid, returns 401.
//   • If platform == web  => the JWT is read from the AccessTokenCookieName
//   • If platform != web  => the JWT is read from Authorization: Bearer ...
//   • The boolean `useRealAttestation` indicates if we do real or dummy checks in ValidateToken.
func AuthMiddleware(pub *rsa.PublicKey, useRealAttestation bool) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			platform := utils.GetClientPlatform(r)
			clientID := utils.GetClientIdentifier(r, platform)
			headerKeyID := r.Header.Get("X-Key-Id") // pass to JWT validation

			tokenStr, err := extractAccessToken(r, platform)
			if err != nil {
				utils.RespondErrorWithCode(
					w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, err.Error(), nil,
				)
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

			claims, ok := tok.Claims.(jwt.MapClaims)
			if !ok {
				utils.RespondErrorWithCode(
					w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, "Invalid claims", nil,
				)
				return
			}
			sub, ok := claims["sub"].(string)
			if !ok {
				utils.RespondErrorWithCode(
					w, http.StatusUnauthorized, utils.ErrCodeUnauthorized, "Missing subject", nil,
				)
				return
			}

			ctx := context.WithValue(r.Context(), ContextKeyUserID, sub)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// helper: read the token from cookie if web, or from Bearer if android/ios
func extractAccessToken(r *http.Request, p utils.PlatformType) (string, error) {
	if p == utils.PlatformWeb {
		c, err := r.Cookie(AccessTokenCookieName)
		if err != nil || c.Value == "" {
			return "", errors.New("missing access_token cookie")
		}
		return c.Value, nil
	}

	h := r.Header.Get("Authorization")
	if !strings.HasPrefix(h, "Bearer ") {
		return "", errors.New("missing Authorization header")
	}
	return strings.TrimPrefix(h, "Bearer "), nil
}

