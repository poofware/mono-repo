package middleware

import (
	"context"
	"crypto/rsa"
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/poofware/go-utils"
)

// TokenIssuer identifies the service that issues all access/refresh tokens.
const TokenIssuer = "Poof"

// ValidateToken checks the token's signature, standard claims, IP/Device-ID matching,
// and, if platform != web, checks the "att" claim. The boolean `useRealAttestation`
// determines if we expect real "play"/(ios-key) checks, or a dummy "FAKE-PLAY"/"FAKE-IOS".
//
// Any deviation returns a descriptive error.
func ValidateToken(
	ctx context.Context,
	tokenString string,
	clientIdentifier utils.ClientIdentifier,
	publicKey *rsa.PublicKey,
	platform utils.PlatformType,
	keyID string,
	useRealAttestation bool,
) (*jwt.Token, error) {

	token, err := jwt.Parse(tokenString, func(token *jwt.Token) (any, error) {
		if _, ok := token.Method.(*jwt.SigningMethodRSA); !ok {
			return nil, errors.New("unexpected signing method")
		}
		return publicKey, nil
	})
	if err != nil {
		return nil, err
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok || !token.Valid {
		return nil, errors.New("invalid token claims")
	}

	// ─── Standard claim checks ────────────────────────────────────────────────────
	exp, ok := claims["exp"].(float64)
	if !ok {
		return nil, errors.New("missing expiration claim")
	}
	if time.Unix(int64(exp), 0).Before(time.Now()) {
		return nil, jwt.ErrTokenExpired
	}

	iss, ok := claims["iss"].(string)
	if !ok {
		return nil, errors.New("missing issuer claim")
	}
	if iss != TokenIssuer {
		return nil, errors.New("invalid token issuer")
	}

	// ─── IP / Device-ID binding ───────────────────────────────────────────────────
	switch clientIdentifier.Type {
	case utils.ClientIDTypeIP:
		ipClaim, hasIP := claims["ip"].(string)
		if !hasIP {
			return nil, errors.New("missing IP claim in token (web)")
		}
		if ipClaim != clientIdentifier.Value {
			return nil, errors.New("IP address mismatch")
		}
	case utils.ClientIDTypeDeviceID:
		devIDClaim, hasDev := claims["device_id"].(string)
		if !hasDev {
			return nil, errors.New("missing device_id claim in token (mobile)")
		}
		if devIDClaim != clientIdentifier.Value {
			return nil, errors.New("device_id mismatch")
		}
	default:
		return nil, errors.New("unsupported platform in ValidateToken")
	}

	// ─── Mobile attestation check (real or dummy) ────────────────────────────────
	if platform != utils.PlatformWeb {
		attVal, _ := claims["att"].(string)

		if useRealAttestation {
			// Real checks
			switch platform {
			case utils.PlatformAndroid:
				if attVal != "play" || keyID != "play" {
					return nil, errors.New("attestation mismatch: android (expected both 'play')")
				}
			case utils.PlatformIOS:
				if attVal == "" || keyID == "" || attVal != keyID {
					return nil, errors.New("attestation mismatch: ios (att claim must equal X-Key-Id)")
				}
			default:
				return nil, errors.New("unsupported platform for attestation")
			}
		} else {
			// Dummy checks
			switch platform {
			case utils.PlatformAndroid:
				if attVal != "FAKE-PLAY" {
					return nil, errors.New("dummy attestation mismatch: android (expected 'FAKE-PLAY')")
				}
			case utils.PlatformIOS:
				if attVal != "FAKE-IOS" {
					return nil, errors.New("dummy attestation mismatch: ios (expected 'FAKE-IOS')")
				}
			default:
				return nil, errors.New("unsupported platform for dummy attestation")
			}
		}
	}

	return token, nil
}

