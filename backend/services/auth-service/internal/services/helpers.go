package services

import (
	"math/big"
	"crypto/rand"
)

// Helper function for generating numeric codes
func generateVerificationCode(length int) (string, error) {
	const digits = "0123456789"
	code := make([]byte, length)
	for i := range length {
		num, err := rand.Int(rand.Reader, big.NewInt(int64(len(digits))))
		if err != nil {
			return "", err
		}
		code[i] = digits[num.Int64()]
	}
	return string(code), nil
}
