// go-utils/hash.go

package utils

import (
	"crypto/sha256"
	"encoding/base64"
)

func HashToken(raw string) string {
	hasher := sha256.New()
	hasher.Write([]byte(raw))
	return base64.URLEncoding.EncodeToString(hasher.Sum(nil))
}

// HashForPlayIntegrity computes the SHA-256 hash of the input data and then
// Base64-URL-encodes it, which is the format Play Integrity expects for the requestHash field.
func HashForPlayIntegrity(data string) string {
	hasher := sha256.New()
	hasher.Write([]byte(data))
	return base64.URLEncoding.EncodeToString(hasher.Sum(nil))
}
