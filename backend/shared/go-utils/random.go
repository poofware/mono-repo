// go-utils/random.go

package utils

import (
	"crypto/rand"
	"encoding/hex"
	"math/big"
)

func RandomString(length int) string {
	bytes := make([]byte, length)
	_, err := rand.Read(bytes)
	if err != nil {
		panic(err) // Handle error appropriately in production
	}
	return hex.EncodeToString(bytes)[:length]
}

// RandomNumericString generates a random string containing only digits.
func RandomNumericString(length int) string {
	const digits = "0123456789"
	b := make([]byte, length)
	for i := range b {
		num, err := rand.Int(rand.Reader, big.NewInt(int64(len(digits))))
		if err != nil {
			panic(err)
		}
		b[i] = digits[num.Int64()]
	}
	return string(b)
}
