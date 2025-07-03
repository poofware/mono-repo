// go-utils/attestation.go

package utils

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"crypto/subtle"
	"crypto/x509"
	"encoding/asn1"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"strings"
	"time"

	"github.com/fxamacker/cbor/v2"
	"github.com/go-playground/validator/v10"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"google.golang.org/api/option"
	play "google.golang.org/api/playintegrity/v1"
	"slices"
)

/* ───────── constants ───────── */

const (
	appleKeyTTL        = 5 * time.Minute
	androidMaxTokenAge = 5 * time.Minute

	appleProdURL = "https://api.devicecheck.apple.com/v1"

	appleDeviceCheckKID = "H84SRPC26Y"

	// Apple App Attestation Root CA – retrieved 2025-06-25
	appleAppAttestRootCA = `-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD
-----END CERTIFICATE-----`
)

var (
	validate = validator.New()
)

/* ───────── types ───────── */

type (
	// AttestationVerifier now includes a callback to consume a challenge.
	AttestationVerifier struct {
		applePriv           *ecdsa.PrivateKey
		appleKID, appleTeam string

		gcpSA []byte

		lookupKey        func(ctx context.Context, keyID []byte) ([]byte, error)
		saveKey          func(ctx context.Context, keyID, pub []byte) error
		consumeChallenge func(ctx context.Context, challengeToken uuid.UUID) (rawChallenge []byte, platform string, err error)
	}

	appAttestMessage struct {
		KeyID             string `json:"key_id"`
		Attestation       string `json:"attestation,omitempty"`
		Assertion         string `json:"assertion,omitempty"`
		ClientData        string `json:"client_data"`
		AuthenticatorData string `json:"authenticator_data,omitempty"`
	}

	AttestationPayload struct {
		IntegrityToken string `json:"integrity_token,omitempty" validate:"omitempty,max=8192"`
		KeyID          string `json:"key_id,omitempty"`
		Attestation    string `json:"attestation,omitempty" validate:"omitempty,max=12288"`
		Assertion      string `json:"assertion,omitempty"   validate:"omitempty,max=8192"`
		ClientData     string `json:"client_data,omitempty" validate:"omitempty,min=16,max=2048"`
		ChallengeToken string `json:"challenge_token"       validate:"required,uuid4"`
	}
)

/* ───────── constructor ───────── */

func NewAttestationVerifier(
	ctx context.Context,
	saJSON []byte,
	priv *ecdsa.PrivateKey,
	lookup func(context.Context, []byte) ([]byte, error),
	save func(context.Context, []byte, []byte) error,
	consume func(ctx context.Context, challengeToken uuid.UUID) (rawChallenge []byte, platform string, err error),
) (*AttestationVerifier, error) {
	return &AttestationVerifier{
		applePriv:        priv,
		appleKID:         appleDeviceCheckKID,
		appleTeam:        AppleTeamID,
		gcpSA:            saJSON,
		lookupKey:        lookup,
		saveKey:          save,
		consumeChallenge: consume,
	}, nil
}

func (p *AttestationPayload) Validate() error { return validate.Struct(p) }

// decodeFlexB64 handles URL-safe base64 with or without padding.
func decodeFlexB64(s string) ([]byte, error) {
	s = strings.NewReplacer("-", "+", "_", "/").Replace(s)
	if m := len(s) % 4; m != 0 {
		s += strings.Repeat("=", 4-m)
	}
	return base64.StdEncoding.DecodeString(s)
}

/* ───────── public API ───────── */

func (a *AttestationVerifier) VerifyMobileAttestation(
	ctx context.Context,
	platform PlatformType,
	payload AttestationPayload,
) (string, error) {
	payloadSummary := fmt.Sprintf(
		"ChallengeToken: %s, KeyID: %s, IntegrityTokenSize: %d, AttestationSize: %d, AssertionSize: %d, ClientDataSize: %d",
		payload.ChallengeToken,
		payload.KeyID,
		len(payload.IntegrityToken),
		len(payload.Attestation),
		len(payload.Assertion),
		len(payload.ClientData),
	)
	Logger.Debugf("[Attestation] Verifying for platform '%s' with payload: %s", platform, payloadSummary)

	challengeToken, err := uuid.Parse(payload.ChallengeToken)
	if err != nil {
		Logger.WithError(err).Warnf("[Attestation] Invalid challenge_token format in payload")
		return "", errors.New("invalid challenge_token format")
	}
	Logger.Debugf("[Attestation] Parsed challenge token: %s", challengeToken)

	rawChallenge, challengePlatform, err := a.consumeChallenge(ctx, challengeToken)
	if err != nil {
		Logger.WithError(err).Errorf("[Attestation] Error consuming challenge token %s", challengeToken)
		return "", fmt.Errorf("consuming challenge: %w", err)
	}
	if rawChallenge == nil {
		Logger.Warnf("[Attestation] Challenge %s not found or expired", challengeToken)
		return "", errors.New("challenge not found or expired")
	}
	Logger.Debugf("[Attestation] Consumed challenge successfully. Platform from DB: '%s'", challengePlatform)

	if challengePlatform != platform.String() {
		Logger.Warnf("[Attestation] Platform mismatch. Expected: '%s', Got from DB: '%s'", platform, challengePlatform)
		return "", fmt.Errorf("challenge platform mismatch: expected %s, got %s", platform, challengePlatform)
	}
	Logger.Debugf("[Attestation] Platform check passed.")

	switch platform {
	case PlatformAndroid:
		Logger.Debugf("[Attestation] Handing off to verifyPlayIntegrity...")
		return a.verifyPlayIntegrity(ctx, payload.IntegrityToken, rawChallenge)
	case PlatformIOS:
		Logger.Debugf("[Attestation] Handing off to verifyAppAttest...")
		return a.verifyAppAttest(ctx, payload, rawChallenge)
	default:
		Logger.Errorf("[Attestation] Unsupported platform type %s", platform)
		return "", fmt.Errorf("unsupported platform %s", platform)
	}
}

/* ───── Android (stateless) ───── */

func (a *AttestationVerifier) verifyPlayIntegrity(
	ctx context.Context,
	encToken string,
	rawChallenge []byte,
) (string, error) {
	Logger.Debugf("[PlayIntegrity] Starting verification...")
	svc, err := play.NewService(
		ctx,
		option.WithCredentialsJSON(a.gcpSA),
		option.WithScopes(play.PlayintegrityScope),
	)
	if err != nil {
		Logger.WithError(err).Error("[PlayIntegrity] Failed to create new Play Integrity service.")
		return "", fmt.Errorf("playintegrity.NewService: %w", err)
	}
	Logger.Debugf("[PlayIntegrity] Service client created.")

	resp, err := svc.V1.DecodeIntegrityToken(
		AndroidAppPackageName,
		&play.DecodeIntegrityTokenRequest{IntegrityToken: encToken},
	).Context(ctx).Do()
	if err != nil {
		Logger.WithError(err).Error("[PlayIntegrity] decodeIntegrityToken API call failed.")
		return "", fmt.Errorf("decodeIntegrityToken: %w", err)
	}
	Logger.Debugf("[PlayIntegrity] Token decoded successfully.")

	pl := resp.TokenPayloadExternal
	if pl == nil {
		Logger.Error("[PlayIntegrity] Decoded token payload is empty.")
		return "", errors.New("empty TokenPayloadExternal")
	}

	/* ── mandatory verdict checks ─────────────── */
	if !slices.Contains(pl.DeviceIntegrity.DeviceRecognitionVerdict, "MEETS_DEVICE_INTEGRITY") {
		Logger.Warnf("[PlayIntegrity] FAIL: Device integrity check. Verdict: %v", pl.DeviceIntegrity.DeviceRecognitionVerdict)
		return "", errors.New("device integrity NOT met")
	}
	Logger.Debugf("[PlayIntegrity] PASS: Device integrity check.")

	if !strings.Contains(pl.AccountDetails.AppLicensingVerdict, "LICENSED") {
		Logger.Warnf("[PlayIntegrity] FAIL: App licensing check. Verdict: %s", pl.AccountDetails.AppLicensingVerdict)
		return "", errors.New("app licensing NOT licensed")
	}
	Logger.Debugf("[PlayIntegrity] PASS: App licensing check.")

	if !strings.Contains(pl.AppIntegrity.AppRecognitionVerdict, "PLAY_RECOGNIZED") {
		Logger.Warnf("[PlayIntegrity] FAIL: App integrity check. Verdict: %s", pl.AppIntegrity.AppRecognitionVerdict)
		return "", errors.New("app integrity NOT recognized by Play Store")
	}
	Logger.Debugf("[PlayIntegrity] PASS: App integrity check.")

	if pl.RequestDetails.RequestPackageName != AndroidAppPackageName {
		Logger.Warnf("[PlayIntegrity] FAIL: Package name mismatch. Expected: '%s', Got: '%s'", AndroidAppPackageName, pl.RequestDetails.RequestPackageName)
		return "", errors.New("package name mismatch")
	}
	Logger.Debugf("[PlayIntegrity] PASS: Package name check.")

	if ts := pl.RequestDetails.TimestampMillis; ts > 0 &&
		time.Since(time.UnixMilli(ts)) > androidMaxTokenAge {
		Logger.Warnf("[PlayIntegrity] FAIL: Token is too old. Timestamp: %d ms", ts)
		return "", errors.New("integrity token too old")
	}
	Logger.Debugf("[PlayIntegrity] PASS: Timestamp check.")

	/* ── request binding (standard flow) ──────── */
	sum := sha256.Sum256(rawChallenge)
	expectedHash := base64.RawURLEncoding.EncodeToString(sum[:])

	if pl.RequestDetails.RequestHash == "" {
		Logger.Warn("[PlayIntegrity] FAIL: requestHash is missing from token payload.")
		return "", errors.New("requestHash missing in token")
	}
	if subtle.ConstantTimeCompare([]byte(pl.RequestDetails.RequestHash), []byte(expectedHash)) != 1 {
		Logger.Warnf("[PlayIntegrity] FAIL: requestHash mismatch. Expected: '%s', Got: '%s'", expectedHash, pl.RequestDetails.RequestHash)
		return "", errors.New("requestHash mismatch")
	}
	Logger.Debugf("[PlayIntegrity] PASS: requestHash matches challenge.")

	Logger.Info("[PlayIntegrity] Verification successful.")
	return "play", nil
}

/* ────── iOS (stateful) ────── */

func (a *AttestationVerifier) verifyAppAttest(
	ctx context.Context,
	payload AttestationPayload,
	rawChallenge []byte,
) (string, error) {
	Logger.Debugf("[AppAttest] Starting verification...")
	keyIDBytes, err := decodeFlexB64(payload.KeyID)
	if err != nil {
		Logger.WithError(err).Warnf("[AppAttest] Invalid key_id format in payload: %s", payload.KeyID)
		return "", errors.New("invalid key_id")
	}
	Logger.Debugf("[AppAttest] Decoded key_id. Looking up in DB.")

	pub, err := a.lookupKey(ctx, keyIDBytes)
	if err != nil {
		Logger.WithError(err).Errorf("[AppAttest] DB lookup for key_id failed.")
		return "", fmt.Errorf("lookupKey: %w", err)
	}

	/* ── first-time attestation ────────────────── */
	if pub == nil && payload.Attestation != "" {
		Logger.Debugf("[AppAttest] No public key found. Attempting first-time attestation flow.")
		attBytes, err := decodeFlexB64(payload.Attestation)
		if err != nil {
			Logger.WithError(err).Warnf("[AppAttest] Failed to decode attestation object from payload.")
			return "", fmt.Errorf("decode attestation: %w", err)
		}

		appID := a.appleTeam + "." + AppleAppID
		pubDER, err := verifyAttestationObject(attBytes, rawChallenge, appID)
		if err != nil {
			Logger.WithError(err).Warnf("[AppAttest] Attestation object verification failed.")
			return "", fmt.Errorf("attestation verify: %w", err)
		}
		Logger.Debugf("[AppAttest] PASS: Attestation object is valid.")

		pubKeyIfc, _ := x509.ParsePKIXPublicKey(pubDER)
		ecdsaPub, ok := pubKeyIfc.(*ecdsa.PublicKey)
		if !ok {
			return "", errors.New("unexpected public-key type")
		}

		// Build the 65-byte uncompressed point: 0x04 | X | Y
		pt := make([]byte, 65)
		pt[0] = 0x04
		ecdsaPub.X.FillBytes(pt[1:33]) // big-endian, left-pad to 32 bytes
		ecdsaPub.Y.FillBytes(pt[33:])  // big-endian, left-pad to 32 bytes

		pubHash := sha256.Sum256(pt) // Apple defines single SHA-256 hash
		if !bytes.Equal(pubHash[:], keyIDBytes) {
			Logger.Warn("[AppAttest] FAIL: keyID hash does not match public key hash.")
			return "", errors.New("keyID mismatch")
		}
		Logger.Debugf("[AppAttest] PASS: keyID hash matches public key.")

		if err := a.saveKey(ctx, keyIDBytes, pubDER); err != nil {
			Logger.WithError(err).Errorf("[AppAttest] Failed to save new public key to DB.")
			return "", fmt.Errorf("saveKey: %w", err)
		}
		Logger.Infof("[AppAttest] First-time attestation successful. Saved new key.")
		return payload.KeyID, nil
	}

	/* ── assertion verification ────────────────── */
	if pub != nil && payload.Assertion != "" {
		Logger.Debugf("[AppAttest] Public key found. Attempting assertion flow.")

		// --- NEW: sanity-check that the stored public key still matches key_id ---
		pubKeyIfc, err := x509.ParsePKIXPublicKey(pub)
		if err != nil {
			Logger.WithError(err).Warn("[AppAttest] Failed to parse stored public key DER.")
			return "", fmt.Errorf("parse pub: %w", err)
		}
		ecdsaPub, ok := pubKeyIfc.(*ecdsa.PublicKey)
		if !ok {
			return "", errors.New("unexpected public-key type")
		}
		// Re-create the 65-byte uncompressed point and hash it
		pt := elliptic.Marshal(elliptic.P256(), ecdsaPub.X, ecdsaPub.Y)
		gotHash := sha256.Sum256(pt)
		if subtle.ConstantTimeCompare(gotHash[:], keyIDBytes) != 1 {
			Logger.Warn("[AppAttest] FAIL: public-key hash mismatch vs key_id.")
			return "", errors.New("public-key hash mismatch")
		}
		Logger.Debugf("[AppAttest] PASS: public-key hash matches key_id.")

		clientJSON, err := decodeFlexB64(payload.ClientData)
		if err != nil {
			Logger.WithError(err).Warnf("[AppAttest] Failed to decode client_data from payload.")
			return "", fmt.Errorf("decode client_data: %w", err)
		}
		var cd struct {
			Challenge string `json:"challenge"`
		}
		if json.Unmarshal(clientJSON, &cd) != nil || cd.Challenge == "" {
			Logger.Warnf("[AppAttest] FAIL: clientData JSON missing 'challenge' field.")
			return "", errors.New("clientData lacks challenge")
		}

		challengeFromClient, err := decodeFlexB64(cd.Challenge)
		if err != nil {
			Logger.WithError(err).Warnf("[AppAttest] Failed to decode challenge from clientData.")
			return "", fmt.Errorf("decode challenge from clientData: %w", err)
		}
		if !bytes.Equal(challengeFromClient, rawChallenge) {
			Logger.Warnf("[AppAttest] FAIL: Challenge mismatch in clientData.")
			return "", errors.New("challenge mismatch in clientData")
		}
		Logger.Debugf("[AppAttest] PASS: clientData challenge matches.")

		if err := verifyAssertion(payload.Assertion, clientJSON, pub, a.appleTeam+"."+AppleAppID); err != nil {
			Logger.WithError(err).Warnf("[AppAttest] Assertion verification failed.")
			return "", fmt.Errorf("assertion verify: %w", err)
		}
		Logger.Debugf("[AppAttest] PASS: Assertion signature is valid.")

		if err := a.saveKey(ctx, keyIDBytes, pub); err != nil {
			Logger.WithError(err).Warn("[AppAttest] update last_seen failed")
		}
		Logger.Info("[AppAttest] Assertion verification successful.")
		return payload.KeyID, nil
	}

	// FINAL CHECK: If pub is nil but we received an assertion, it means the client
	// thinks it's registered but the key is gone from our DB. This is the specific
	// case where we must trigger a re-attestation on the client.
	if pub == nil && payload.Assertion != "" {
		return "", ErrKeyNotFoundForAssertion
	}

	return "", errors.New("invalid iOS attestation flow: unexpected state")
}

// verifyAttestationObject validates Apple's attestation object and
// returns the credential public key (DER) for later assertions.
func verifyAttestationObject(attBytes, challenge []byte, appID string) ([]byte, error) {

	var attObj struct {
		Format   string         `cbor:"fmt"`
		AttStmt  map[string]any `cbor:"attStmt"`
		AuthData []byte         `cbor:"authData"`
	}
	if err := cbor.Unmarshal(attBytes, &attObj); err != nil {
		return nil, fmt.Errorf("cbor: %w", err)
	}

	if attObj.Format != "apple-appattest" {
		return nil, errors.New("unexpected attestation format")
	}

	/* ───── certificate & nonce validation ───── */
	rawX5c, ok := attObj.AttStmt["x5c"]
	if !ok {
		return nil, errors.New("missing x5c")
	}
	x5cArr := rawX5c.([]any)
	leaf, _ := x509.ParseCertificate(x5cArr[0].([]byte))
	interPool := x509.NewCertPool()
	for _, v := range x5cArr[1:] {
		cert, _ := x509.ParseCertificate(v.([]byte))
		interPool.AddCert(cert)
	}
	roots := x509.NewCertPool()
	roots.AppendCertsFromPEM([]byte(appleAppAttestRootCA))
	if _, err := leaf.Verify(x509.VerifyOptions{
		Roots:         roots,
		Intermediates: interPool,
		CurrentTime:   time.Now(),
	}); err != nil {
		return nil, fmt.Errorf("cert verify: %w", err)
	}

	appleOID := asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 8, 2}
	var nonceExt []byte
	for _, ext := range leaf.Extensions {
		if !ext.Id.Equal(appleOID) {
			continue
		}

		var outer asn1.RawValue
		if _, err := asn1.Unmarshal(ext.Value, &outer); err != nil {
			return nil, fmt.Errorf("nonce outer parse: %w", err)
		}

		var ctx asn1.RawValue
		if _, err := asn1.Unmarshal(outer.Bytes, &ctx); err != nil {
			return nil, fmt.Errorf("nonce ctx parse: %w", err)
		}
		if ctx.Class != asn1.ClassContextSpecific || ctx.Tag != 1 {
			return nil, errors.New("unexpected nonce wrapper")
		}

		if _, err := asn1.Unmarshal(ctx.Bytes, &nonceExt); err != nil {
			return nil, fmt.Errorf("nonce inner parse: %w", err)
		}
		if len(nonceExt) != 32 {
			return nil, errors.New("nonce length ≠ 32")
		}
		break
	}
	if len(nonceExt) == 0 {
		return nil, errors.New("nonce extension missing")
	}

	base64Challenge := base64.RawURLEncoding.EncodeToString(challenge)
	chHash := sha256.Sum256([]byte(base64Challenge))
	expectedNonce := sha256.Sum256(append(attObj.AuthData, chHash[:]...))
	if !bytes.Equal(nonceExt, expectedNonce[:]) {
		return nil, errors.New("nonce mismatch")
	}

	/* ───── rpIdHash validation ───── */
	rpHash := sha256.Sum256([]byte(appID))
	if !bytes.Equal(attObj.AuthData[:32], rpHash[:]) {
		return nil, errors.New("rpIdHash mismatch")
	}

	/* ───── extract credential public key from authData ───── */
	const (
		rpHashLen     = 32
		flagsLen      = 1
		counterLen    = 4
		aaguidLen     = 16
		idLenBytes    = 2
		authDataFixed = rpHashLen + flagsLen + counterLen + aaguidLen + idLenBytes
	)
	if len(attObj.AuthData) < authDataFixed {
		return nil, errors.New("authData too short")
	}

	credIDLen := int(attObj.AuthData[rpHashLen+flagsLen+counterLen+aaguidLen])<<8 |
		int(attObj.AuthData[rpHashLen+flagsLen+counterLen+aaguidLen+1])

	cursor := authDataFixed + credIDLen
	if cursor > len(attObj.AuthData) {
		return nil, errors.New("credentialID overflow")
	}
	credPubKeyBytes := attObj.AuthData[cursor:]

	var cose map[int]any
	if err := cbor.Unmarshal(credPubKeyBytes, &cose); err != nil {
		return nil, fmt.Errorf("cose key parse: %w", err)
	}
	xBytes, _ := cose[-2].([]byte)
	yBytes, _ := cose[-3].([]byte)
	if len(xBytes) != 32 || len(yBytes) != 32 {
		return nil, errors.New("unexpected key size")
	}

	x := new(big.Int).SetBytes(xBytes)
	y := new(big.Int).SetBytes(yBytes)
	pub := ecdsa.PublicKey{Curve: elliptic.P256(), X: x, Y: y}

	return x509.MarshalPKIXPublicKey(&pub)
}

// verifyAssertion checks signature with stored key.
func verifyAssertion(assertionB64 string, clientDataJSON, pubDER []byte, appID string) error {
	Logger.Debugf("[verifyAssertion] Verifying for appID: %s", appID)

	raw, err := decodeFlexB64(assertionB64)
	if err != nil {
		Logger.WithError(err).Warn("[verifyAssertion] FAIL: Could not base64-decode assertion.")
		return fmt.Errorf("base64 decode assertion: %w", err)
	}

	var as struct {
		AuthenticatorData []byte `cbor:"authenticatorData"`
		Signature         []byte `cbor:"signature"`
	}
	if err := cbor.Unmarshal(raw, &as); err != nil {
		Logger.WithError(err).Warn("[verifyAssertion] FAIL: Could not CBOR-decode assertion.")
		return fmt.Errorf("cbor: %w", err)
	}

	sigDER := as.Signature

	var rs struct{ R, S *big.Int }
	if _, err := asn1.Unmarshal(sigDER, &rs); err != nil {
		Logger.Warn("[verifyAssertion] FAIL: ASN.1 parse error.")
		return fmt.Errorf("asn1: %w", err)
	}
	n := elliptic.P256().Params().N
	halfN := new(big.Int).Rsh(n, 1)
	if rs.S.Cmp(halfN) == 1 {
		rs.S.Sub(n, rs.S) // force low-S
		Logger.Debug("[AA-debug] S was high; normalised to low-S.")
	}

	authData := as.AuthenticatorData

	if len(authData) < 37 {
		Logger.Warn("[verifyAssertion] FAIL: AuthenticatorData is too short.")
		return errors.New("authenticatorData too short")
	}

	if len(authData) >= 37 {
		Logger.Debugf("[AA-debug] authData[0:37] (hex) = %x", authData[:37])
	}

	rpHash := sha256.Sum256([]byte(appID))
	if !bytes.Equal(authData[:32], rpHash[:]) {
		Logger.Warn("[verifyAssertion] FAIL: rpIdHash mismatch.")
		return errors.New("rpIdHash mismatch")
	}
	Logger.Debug("[verifyAssertion] PASS: rpIdHash matches.")

	cHash := sha256.Sum256(clientDataJSON)
	msg := append(authData, cHash[:]...)
	nonce := sha256.Sum256(msg)
	digest := sha256.Sum256(nonce[:])

	pub, _ := x509.ParsePKIXPublicKey(pubDER)
	if !ecdsa.Verify(pub.(*ecdsa.PublicKey), digest[:], rs.R, rs.S) {
		Logger.Warn("[verifyAssertion] FAIL: ECDSA signature verification failed.")
		return errors.New("invalid signature")
	}
	Logger.Debugf("[verifyAssertion] PASS: Signature is valid.")
	return nil
}

/* ───── Apple JWT helper ───── */

func (a *AttestationVerifier) appleAuthHeader() (string, error) {
	now := time.Now()
	claims := jwt.MapClaims{
		"iss": a.appleTeam,
		"iat": now.Unix(),
		"exp": now.Add(appleKeyTTL).Unix(),
		"aud": "devicecheck.apple.com",
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodES256, claims)
	tok.Header["kid"] = a.appleKID
	signed, err := tok.SignedString(a.applePriv)
	if err != nil {
		return "", fmt.Errorf("sign Apple JWT: %w", err)
	}
	return "Bearer " + signed, nil
}

/* ───── helpers ───── */

func defaultHTTPClient() *http.Client { return &http.Client{Timeout: 5 * time.Second} }
