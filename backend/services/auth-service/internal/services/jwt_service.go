package services

import (
    "context"
    "crypto/rand"
    "crypto/rsa"
    "errors"
    "math/big"
    "time"

    "github.com/golang-jwt/jwt/v5"
    "github.com/google/uuid"
    "github.com/poofware/auth-service/internal/config"
    "github.com/poofware/auth-service/internal/models"
    "github.com/poofware/auth-service/internal/repositories"
    "github.com/poofware/go-middleware"
    "github.com/poofware/go-utils"
)

// ---------------------------------------------------------------------
// JWTService interface
// ---------------------------------------------------------------------

type JWTService interface {
    // Now includes an optional attFingerprint param to embed "att" if not empty
    GenerateAccessToken(
        ctx context.Context,
        subjectID uuid.UUID,
        clientIdentifier utils.ClientIdentifier,
        tokenExpiry time.Duration,
        refreshExpiry time.Duration,
        attFingerprint string, // optional, for device attestation
    ) (string, error)

    GenerateRefreshToken(
        ctx context.Context,
        subjectID uuid.UUID,
        clientIdentifier utils.ClientIdentifier,
        refreshExpiry time.Duration,
    ) (*models.RefreshToken, error)

    // Now also includes an attFingerprint param for embedding "att"
    RefreshToken(
        ctx context.Context,
        refreshTokenString string,
        clientIdentifier utils.ClientIdentifier,
        tokenExpiry time.Duration,
        refreshExpiry time.Duration,
        attFingerprint string,
    ) (string, string, error)

    Logout(ctx context.Context, refreshTokenString string) error
}

// ---------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------

type jwtService struct {
    privateKey *rsa.PrivateKey
    publicKey  *rsa.PublicKey
    tokenRepo  repositories.TokenRepository
}

func NewJWTService(cfg *config.Config, tokenRepo repositories.TokenRepository) JWTService {
    return &jwtService{
        privateKey: cfg.RSAPrivateKey,
        publicKey:  cfg.RSAPublicKey,
        tokenRepo:  tokenRepo,
    }
}

// ---------------------------------------------------------------------
// GenerateAccessToken
//  now conditionally includes "att" if attFingerprint != ""
// ---------------------------------------------------------------------

func (j *jwtService) GenerateAccessToken(
    ctx context.Context,
    subjectID uuid.UUID,
    clientIdentifier utils.ClientIdentifier,
    tokenExpiry time.Duration,
    refreshExpiry time.Duration, // note: we only need tokenExpiry to set 'exp'
    attFingerprint string,
) (string, error) {

    tokenID := uuid.NewString()
    claims := jwt.MapClaims{
        "iss": middleware.TokenIssuer, // e.g., "Poof"
        "sub": subjectID.String(),
        "exp": time.Now().Add(tokenExpiry).Unix(),
        "iat": time.Now().Unix(),
        "jti": tokenID,
    }

    // IP or device
    switch clientIdentifier.Type {
    case utils.ClientIDTypeIP:
        claims["ip"] = clientIdentifier.Value
    case utils.ClientIDTypeDeviceID:
        claims["device_id"] = clientIdentifier.Value
    }

    // optional "att" claim
    if attFingerprint != "" {
        claims["att"] = attFingerprint
    }

    // sign
    return j.signClaims(claims)
}

// ---------------------------------------------------------------------
// GenerateRefreshToken
// ---------------------------------------------------------------------

func (j *jwtService) GenerateRefreshToken(
    ctx context.Context,
    subjectID uuid.UUID,
    clientIdentifier utils.ClientIdentifier,
    refreshExpiry time.Duration,
) (*models.RefreshToken, error) {

    if j.tokenRepo == nil {
        return nil, errors.New("jwtService has nil tokenRepo")
    }

    rawToken := generateSecureToken(64)
    expiresAt := time.Now().Add(refreshExpiry)

    rt := &models.RefreshToken{
        ID:        uuid.New(),
        UserID:    subjectID,
        Token:     rawToken,
        ExpiresAt: expiresAt,
        CreatedAt: time.Now(),
        Revoked:   false,
    }

    // store IP or device
    switch clientIdentifier.Type {
    case utils.ClientIDTypeIP:
        rt.IPAddress = clientIdentifier.Value
    case utils.ClientIDTypeDeviceID:
        rt.DeviceID = clientIdentifier.Value
    }

    err := j.tokenRepo.CreateRefreshToken(ctx, rt)
    if err != nil {
        return nil, err
    }

    return rt, nil
}

// ---------------------------------------------------------------------
// RefreshToken
//  now also sets "att" if attFingerprint != ""
// ---------------------------------------------------------------------

func (j *jwtService) RefreshToken(
    ctx context.Context,
    refreshTokenString string,
    clientIdentifier utils.ClientIdentifier,
    tokenExpiry time.Duration,
    refreshExpiry time.Duration,
    attFingerprint string,
) (string, string, error) {

    if j.tokenRepo == nil {
        return "", "", errors.New("jwtService has nil tokenRepo")
    }

    oldToken, err := j.tokenRepo.GetRefreshToken(ctx, refreshTokenString)
    if err != nil || oldToken == nil || oldToken.Revoked {
        utils.Logger.WithError(err).Error("invalid or missing refresh token in jwtService.RefreshToken")
        return "", "", errors.New("invalid refresh token")
    }

    if oldToken.IsExpired() {
        utils.Logger.Error("refresh token expired in jwtService.RefreshToken")
        return "", "", errors.New("refresh token expired")
    }

    // check IP/device_id mismatch
    switch clientIdentifier.Type {
    case utils.ClientIDTypeIP:
        if oldToken.IPAddress != "" && oldToken.IPAddress != clientIdentifier.Value {
            utils.Logger.Error("IP mismatch in jwtService.RefreshToken")
            return "", "", errors.New("ip mismatch")
        }
    case utils.ClientIDTypeDeviceID:
        if oldToken.DeviceID != "" && oldToken.DeviceID != clientIdentifier.Value {
            utils.Logger.Error("device_id mismatch in jwtService.RefreshToken")
            return "", "", errors.New("device_id mismatch")
        }
    }

    // remove old refresh
    if err := j.tokenRepo.RemoveRefreshToken(ctx, oldToken.ID); err != nil {
        utils.Logger.WithError(err).Error("failed to remove old refresh token in jwtService.RefreshToken")
        return "", "", errors.New("failed to remove old token")
    }

    // Now issue new Access + Refresh
    newAccess, aErr := j.GenerateAccessToken(ctx, oldToken.UserID, clientIdentifier, tokenExpiry, refreshExpiry, attFingerprint)
    if aErr != nil {
        return "", "", aErr
    }

    newRT, rErr := j.GenerateRefreshToken(ctx, oldToken.UserID, clientIdentifier, refreshExpiry)
    if rErr != nil {
        return "", "", rErr
    }

    return newAccess, newRT.Token, nil
}

// ---------------------------------------------------------------------
// Logout
// ---------------------------------------------------------------------

func (j *jwtService) Logout(ctx context.Context, refreshTokenString string) error {
    if j.tokenRepo == nil {
        return errors.New("jwtService has nil tokenRepo")
    }

    oldToken, err := j.tokenRepo.GetRefreshToken(ctx, refreshTokenString)
    if err != nil {
        utils.Logger.WithError(err).Error("logout fetch refresh token error in jwtService")
        return errors.New("logout server error")
    }
    if oldToken == nil {
        // already not found => no-op
        return nil
    }

    if err := j.tokenRepo.RemoveRefreshToken(ctx, oldToken.ID); err != nil {
        utils.Logger.WithError(err).Error("failed to remove token in jwtService.Logout")
        return errors.New("logout server error")
    }
    return nil
}

// ---------------------------------------------------------------------
// signClaims – helper for RSA signing
// ---------------------------------------------------------------------

func (j *jwtService) signClaims(claims jwt.MapClaims) (string, error) {
    token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
    return token.SignedString(j.privateKey)
}

// ---------------------------------------------------------------------
// Secure random generator
// ---------------------------------------------------------------------

func generateSecureToken(length int) string {
    const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    b := make([]byte, length)
    for i := range b {
        b[i] = charset[secureRandomInt(len(charset))]
    }
    return string(b)
}

func secureRandomInt(max int) int {
    n, err := rand.Int(rand.Reader, big.NewInt(int64(max)))
    if err != nil {
        panic(err)
    }
    return int(n.Int64())
}

