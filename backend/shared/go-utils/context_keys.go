// go-utils/context_keys.go

package utils

// ctxKey is unexported to prevent collisions.
type ctxKey string

// CtxKeyAttestation stores the Play-Integrity / App-Attest fingerprint.
const CtxKeyAttestation ctxKey = "attestationFingerprint"

// CtxKeyChallenge stores the raw challenge string from the request header.
const CtxKeyChallenge ctxKey = "challenge"
