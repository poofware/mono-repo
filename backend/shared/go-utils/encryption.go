package utils

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"io"

	"golang.org/x/crypto/pbkdf2"
)

// -----------------------------------------
// 1) AES-256-GCM (Recommended Modern Mode)
//    [nonce(12 bytes) || ciphertext... || tag(16 bytes)]
//    Base64-URL-encoded as one string
// ------------------------------------------

// Encrypt encrypts the provided plaintext with AES-256-GCM.
// The encryptionKey must be exactly 32 bytes (256 bits).
func Encrypt(encryptionKey []byte, text string) (string, error) {
	if len(encryptionKey) != 32 {
		return "", errors.New("encryption key must be 32 bytes for AES-256")
	}
	block, err := aes.NewCipher(encryptionKey)
	if err != nil {
		return "", err
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}

	plaintext := []byte(text)

	// GCM standard 12-byte nonce
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}

	// Seal appends ciphertext + 16-byte tag
	ciphertext := gcm.Seal(nil, nonce, plaintext, nil)

	// Combine [nonce || ciphertext+tag] into one blob
	data := append(nonce, ciphertext...)

	// Return URL-safe Base64 (like you had before)
	return base64.URLEncoding.EncodeToString(data), nil
}

// Decrypt decrypts data produced by the GCM-based Encrypt function above.
// It expects a single URL-safe Base64 string containing [nonce||ciphertext||tag].
func Decrypt(encryptionKey []byte, encoded string) (string, error) {
	if len(encryptionKey) != 32 {
		return "", errors.New("encryption key must be 32 bytes for AES-256")
	}

	raw, err := base64.URLEncoding.DecodeString(encoded)
	if err != nil {
		return "", err
	}
	block, err := aes.NewCipher(encryptionKey)
	if err != nil {
		return "", err
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}

	nonceSize := gcm.NonceSize()
	if len(raw) < nonceSize {
		return "", errors.New("malformed ciphertext (too short for nonce)")
	}
	nonce := raw[:nonceSize]
	ciphertextAndTag := raw[nonceSize:]

	plaintext, err := gcm.Open(nil, nonce, ciphertextAndTag, nil)
	if err != nil {
		return "", err
	}
	return string(plaintext), nil
}

// ---------------------------------------------
// 2) "Salted__" Format (AES-256-CBC + PBKDF2)
//    to match `openssl enc -aes-256-cbc -pbkdf2 -salt`
// ---------------------------------------------
//
// NOTE: Typically, OpenSSL's Salted__ approach uses a *passphrase*.
// Here, we treat your 32-byte 'encryptionKey' as that passphrase.
//
// The output is: Base64-URL-encoded("Salted__" + 8-byte salt + ciphertext).
// The salt is random, and we do PBKDF2 (SHA256, 10,000 iterations) => 48 bytes => 32 for key, 16 for IV.
//
// You can decrypt the result with:
//   echo "CIPHERTEXT" | base64 -d > cipher.bin
//   openssl enc -aes-256-cbc -d -salt -pbkdf2 -pass pass:"$(cat key.bin)" -in cipher.bin
//

// EncryptOpenSSLSalted replicates the OpenSSL salted format with AES-256-CBC + PBKDF2.
// The 32-byte 'encryptionKey' is used as the *passphrase* for PBKDF2.
func EncryptOpenSSLSalted(passphrase []byte, text string) (string, error) {
	if len(passphrase) == 0 {
		return "", errors.New("passphrase cannot be empty")
	}

	plaintext := []byte(text)

	// 1) 'Salted__' prefix + 8-byte random salt
	header := []byte("Salted__")
	salt := make([]byte, 8)
	if _, err := io.ReadFull(rand.Reader, salt); err != nil {
		return "", err
	}
	salted := append(header, salt...)

	// 2) Derive key + IV from PBKDF2(passphrase, salt)
	//    10,000 iterations, SHA256, 48 bytes => 32 for key, 16 for IV
	derived := pbkdf2.Key(passphrase, salt, 10000, 48, sha256.New)
	key := derived[:32]
	iv := derived[32:]

	// 3) AES-256-CBC encryption with PKCS#7
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}
	blockSize := block.BlockSize()
	paddingLen := blockSize - (len(plaintext) % blockSize)
	padText := bytes.Repeat([]byte{byte(paddingLen)}, paddingLen)
	plaintext = append(plaintext, padText...)

	ciphertext := make([]byte, len(plaintext))
	mode := cipher.NewCBCEncrypter(block, iv)
	mode.CryptBlocks(ciphertext, plaintext)

	// 4) Combine: "Salted__" + salt + ciphertext
	full := append(salted, ciphertext...)

	// 5) **Standard** Base64
	return base64.StdEncoding.EncodeToString(full), nil
}

// DecryptOpenSSLSalted decrypts data produced by EncryptOpenSSLSalted() or
//     openssl enc -aes-256-cbc -salt -pbkdf2 -base64 -pass pass:"MyPassphrase"
//
// It expects a standard Base64 string containing "Salted__" + 8-byte salt + ciphertext.
func DecryptOpenSSLSalted(passphrase []byte, b64Cipher string) (string, error) {
	if len(passphrase) == 0 {
		return "", errors.New("passphrase cannot be empty")
	}
	if b64Cipher == "" {
		return "", errors.New("ciphertext cannot be empty")
	}

	// 1) Standard Base64 decode
	raw, err := base64.StdEncoding.DecodeString(b64Cipher)
	if err != nil {
		return "", err
	}

	// Must have at least "Salted__" (8 bytes) + 8-byte salt = 16
	if len(raw) < 16 {
		return "", errors.New("invalid data: missing 'Salted__' header or salt")
	}
	if string(raw[:8]) != "Salted__" {
		return "", errors.New("data does not begin with 'Salted__'")
	}

	// 2) Extract salt + ciphertext
	salt := raw[8:16]
	ciphertext := raw[16:]
	if len(ciphertext) == 0 {
		return "", errors.New("no ciphertext data")
	}

	// 3) Derive key + IV with PBKDF2(passphrase, salt)
	derived := pbkdf2.Key(passphrase, salt, 10000, 48, sha256.New)
	key := derived[:32]
	iv := derived[32:]

	// 4) AES-256-CBC decryption
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}
	if len(ciphertext)%block.BlockSize() != 0 {
		return "", errors.New("ciphertext not multiple of block size")
	}
	mode := cipher.NewCBCDecrypter(block, iv)

	plaintext := make([]byte, len(ciphertext))
	mode.CryptBlocks(plaintext, ciphertext)

	// 5) Remove PKCS#7 padding
	paddingLen := int(plaintext[len(plaintext)-1])
	if paddingLen < 1 || paddingLen > block.BlockSize() {
		return "", errors.New("invalid padding length")
	}
	plaintext = plaintext[:len(plaintext)-paddingLen]

	return string(plaintext), nil
}
