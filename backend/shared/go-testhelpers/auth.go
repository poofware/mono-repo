package testhelpers

import (
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/pquerna/otp/totp"
	"github.com/stretchr/testify/require"
)

// CreateMobileJWT creates a JWT for mobile clients (Worker) with device-specific claims.
func (h *TestHelper) CreateMobileJWT(userID uuid.UUID, deviceID, attestationValue string) string {
	now := time.Now().Unix()
	claims := jwt.MapClaims{
		"iss":       "Poof",
		"sub":       userID.String(),
		"iat":       now,
		"exp":       now + 15*60,
		"device_id": deviceID,
		"att":       attestationValue,
	}
	token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	signed, err := token.SignedString(h.PrivateKey)
	require.NoError(h.T, err, "Failed to sign test worker JWT (mobile style)")
	return signed
}

// CreateWebJWT creates a JWT for web clients (Property Manager) with an IP-based claim.
func (h *TestHelper) CreateWebJWT(userID uuid.UUID, ipAddress string) string {
	now := time.Now().Unix()
	claims := jwt.MapClaims{
		"iss": "Poof",
		"sub": userID.String(),
		"iat": now,
		"exp": now + 15*60,
		"ip":  ipAddress,
	}
	token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	signed, err := token.SignedString(h.PrivateKey)
	require.NoError(h.T, err, "Failed to sign test PM JWT (web style)")
	return signed
}

// GenerateTOTPCode generates a valid TOTP code for a given secret.
func (h *TestHelper) GenerateTOTPCode(secret string) string {
	code, err := totp.GenerateCode(secret, time.Now())
	require.NoError(h.T, err)
	return code
}
