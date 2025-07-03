package utils

import (
	"bytes"
	"encoding/base64"
	"os/exec"
	"strings"
	"testing"
)

func TestAESGCMEncryptionDecryption(t *testing.T) {
	encryptionKey := make([]byte, 32) // exactly 32 bytes
	for i := 0; i < 32; i++ {
		encryptionKey[i] = byte(i)
	}

	plaintext := "Hello, AES-GCM!"

	ciphertext, err := Encrypt(encryptionKey, plaintext)
	if err != nil {
		t.Fatalf("Encrypt returned error: %v", err)
	}

	decrypted, err := Decrypt(encryptionKey, ciphertext)
	if err != nil {
		t.Fatalf("Decrypt returned error: %v", err)
	}

	if decrypted != plaintext {
		t.Fatalf("Expected decrypted text '%s', got '%s'", plaintext, decrypted)
	}
}

func TestAESGCMInvalidKey(t *testing.T) {
	shortKey := []byte("not-32-bytes")
	_, err := Encrypt(shortKey, "some text")
	if err == nil {
		t.Fatal("Expected error with invalid key length, got no error")
	} else {
		t.Logf("Correctly got error for invalid key length: %v", err)
	}

	_, err = Decrypt(shortKey, "some ciphertext")
	if err == nil {
		t.Fatal("Expected error with invalid key length, got no error")
	} else {
		t.Logf("Correctly got error for invalid key length: %v", err)
	}
}

func TestOpenSSLSaltedRoundTrip(t *testing.T) {
	passphrase := []byte("mysecretpass")
	plaintext := "Hello from OpenSSL salted encrypt!"

	ciphertext, err := EncryptOpenSSLSalted(passphrase, plaintext)
	if err != nil {
		t.Fatalf("EncryptOpenSSLSalted returned error: %v", err)
	}

	decrypted, err := DecryptOpenSSLSalted(passphrase, ciphertext)
	if err != nil {
		t.Fatalf("DecryptOpenSSLSalted returned error: %v", err)
	}

	if decrypted != plaintext {
		t.Fatalf("Expected '%s', got '%s'", plaintext, decrypted)
	}
}

func TestOpenSSLSaltedEmptyPassphrase(t *testing.T) {
	emptyPass := []byte("")
	_, err := EncryptOpenSSLSalted(emptyPass, "some text")
	if err == nil {
		t.Fatal("Expected error for empty passphrase, got no error")
	} else {
		t.Logf("Correctly got error for empty passphrase (encrypt): %v", err)
	}

	_, err = DecryptOpenSSLSalted(emptyPass, "some ciphertext")
	if err == nil {
		t.Fatal("Expected error for empty passphrase, got no error")
	} else {
		t.Logf("Correctly got error for empty passphrase (decrypt): %v", err)
	}
}

// TestOpenSSLInterop checks cross-compatibility with the openssl CLI:
//  1) Encrypt with openssl (pbkdf2+salt+aes256-cbc), decrypt with our code
//  2) Encrypt with our code, decrypt with openssl
// We capture stderr to show OpenSSL error messages explicitly.
func TestOpenSSLInterop(t *testing.T) {
	// Check if openssl is available
	_, err := exec.LookPath("openssl")
	if err != nil {
		t.Fatalf("OpenSSL CLI not found in PATH. Error: %v", err)
	}

	// Log the openssl version for clarity
	versionCmd := exec.Command("openssl", "version")
	var versionOut bytes.Buffer
	versionCmd.Stdout = &versionOut
	if err := versionCmd.Run(); err != nil {
		t.Fatalf("Failed to get OpenSSL version: %v", err)
	}
	t.Logf("OpenSSL version: %s", strings.TrimSpace(versionOut.String()))

	passphrase := "mysecretpass"
	plaintext := "Hello from Go -> OpenSSL interop!"

	// 1) Encrypt with openssl -> Decrypt with Go
	// Force the same iteration count (10000) and digest (sha256) that our code uses
	cmdEnc := exec.Command("openssl", "enc",
		"-aes-256-cbc",
		"-salt",
		"-pbkdf2",
		"-iter", "10000",
		"-md", "sha256",
		"-base64",
		"-pass", "pass:"+passphrase,
	)
	cmdEnc.Stdin = strings.NewReader(plaintext)

	var outEnc, errEnc bytes.Buffer
	cmdEnc.Stdout = &outEnc
	cmdEnc.Stderr = &errEnc

	if err := cmdEnc.Run(); err != nil {
		if strings.Contains(errEnc.String(), "unknown option '-pbkdf2'") {
			t.Skipf("Skipping test; OpenSSL does not support '-pbkdf2'. Stderr: %s", errEnc.String())
		}
		t.Fatalf("OpenSSL encryption failed:\nError: %v\n=== stderr ===\n%s\n=== stdout ===\n%s",
			err, errEnc.String(), outEnc.String())
	}
	cipherFromOpenSSL := strings.TrimSpace(outEnc.String())

	t.Logf("OpenSSL->Go: ciphertext base64 length=%d", len(cipherFromOpenSSL))

	decrypted, err := DecryptOpenSSLSalted([]byte(passphrase), cipherFromOpenSSL)
	if err != nil {
		t.Fatalf("DecryptOpenSSLSalted failed (OpenSSL->Go): %v\nCiphertext:\n%s", err, cipherFromOpenSSL)
	}
	if decrypted != plaintext {
		t.Fatalf("Decryption mismatch.\nExpected: %s\nGot:      %s", plaintext, decrypted)
	}

	// 2) Encrypt with Go -> Decrypt with openssl
	myCipher, err := EncryptOpenSSLSalted([]byte(passphrase), plaintext)
	if err != nil {
		t.Fatalf("EncryptOpenSSLSalted failed (Go->OpenSSL): %v", err)
	}

	t.Logf("Go->OpenSSL: ciphertext base64 length=%d", len(myCipher))

	cmdDec := exec.Command("openssl", "enc",
		"-d",
		"-aes-256-cbc",
		"-salt",
		"-pbkdf2",
		"-iter", "10000",
		"-md", "sha256",
		"-base64",
		"-pass", "pass:"+passphrase,
	)
	// Add a newline so OpenSSL doesn’t complain about partial input
	cmdDec.Stdin = strings.NewReader(myCipher + "\n")

	var outDec, errDec bytes.Buffer
	cmdDec.Stdout = &outDec
	cmdDec.Stderr = &errDec

	if err := cmdDec.Run(); err != nil {
		// If the version is too old for -pbkdf2, skip. Otherwise, fail with full details
		if strings.Contains(errDec.String(), "unknown option '-pbkdf2'") {
			t.Skipf("Skipping test; OpenSSL does not support '-pbkdf2'. Stderr: %s", errDec.String())
		}
		t.Fatalf("OpenSSL decryption (Go->OpenSSL) failed: %v\n=== stderr ===\n%s\n=== stdout ===\n%s",
			err, errDec.String(), outDec.String())
	}
	decText := outDec.String()
	if decText != plaintext {
		t.Fatalf("Decryption mismatch.\nExpected: %s\nGot:      %s", plaintext, decText)
	}
}

func TestOpenSSLSaltedCorruption(t *testing.T) {
	passphrase := []byte("testing")
	plaintext := "Some data"
	ciphertext, err := EncryptOpenSSLSalted(passphrase, plaintext)
	if err != nil {
		t.Fatalf("EncryptOpenSSLSalted returned error: %v", err)
	}

	// Corrupt the ciphertext by chopping off some bytes
	corrupted := ciphertext[:len(ciphertext)-4]
	t.Logf("Corrupted ciphertext: %s", corrupted)

	_, err = DecryptOpenSSLSalted(passphrase, corrupted)
	if err == nil {
		t.Fatalf("Expected error while decrypting corrupted ciphertext, got no error")
	} else {
		t.Logf("Correctly got error while decrypting corrupted ciphertext: %v", err)
	}
}

func TestAESGCMCorruption(t *testing.T) {
	encryptionKey := make([]byte, 32)
	for i := 0; i < 32; i++ {
		encryptionKey[i] = byte(i)
	}
	plaintext := "Test AES-GCM Corruption"

	ciphertext, err := Encrypt(encryptionKey, plaintext)
	if err != nil {
		t.Fatalf("Encrypt returned error: %v", err)
	}

	// Flip a byte in the raw ciphertext
	raw, decodeErr := base64.URLEncoding.DecodeString(ciphertext)
	if decodeErr != nil {
		t.Fatalf("Base64 decode error: %v", decodeErr)
	}
	if len(raw) > 0 {
		raw[0] ^= 0xFF
	}
	corrupted := base64.URLEncoding.EncodeToString(raw)

	_, err = Decrypt(encryptionKey, corrupted)
	if err == nil {
		t.Fatal("Expected error while decrypting corrupted ciphertext, got no error")
	} else {
		t.Logf("Correctly got error while decrypting corrupted data: %v", err)
	}
}

func TestAESGCMShortCipher(t *testing.T) {
	encryptionKey := make([]byte, 32)
	// "Zm9v" -> "foo", obviously too short for 12-byte nonce + 16-byte tag
	_, err := Decrypt(encryptionKey, "Zm9v")
	if err == nil {
		t.Fatal("Expected error while decrypting too-short ciphertext, got no error")
	} else {
		t.Logf("Correctly got error for too-short ciphertext: %v", err)
	}
}

func TestAESGCMInvalidBase64(t *testing.T) {
	encryptionKey := make([]byte, 32)
	_, err := Decrypt(encryptionKey, "!!!NOT-BASE64!!!")
	if err == nil {
		t.Fatal("Expected base64 decode error, got no error")
	} else {
		t.Logf("Correctly got error for invalid base64: %v", err)
	}
}

func TestOpenSSLSaltedInvalidBase64(t *testing.T) {
	passphrase := []byte("testing")
	_, err := DecryptOpenSSLSalted(passphrase, "!!!NOT-BASE64!!!")
	if err == nil {
		t.Fatal("Expected base64 decode error, got no error")
	} else {
		t.Logf("Correctly got error for invalid base64: %v", err)
	}
}

func TestOpenSSLSaltedMissingSalt(t *testing.T) {
	passphrase := []byte("testing")
	// Valid base64, but won't start with "Salted__"
	b64 := base64.StdEncoding.EncodeToString([]byte("NOSALTATALL"))
	_, err := DecryptOpenSSLSalted(passphrase, b64)
	if err == nil {
		t.Fatal("Expected error for data missing 'Salted__' prefix, got none")
	} else {
		t.Logf("Correctly got error for missing 'Salted__' prefix: %v", err)
	}
}

func TestOpenSSLSaltedKeyTruncation(t *testing.T) {
	passphrase := []byte("testing")
	// Just "Salted__" in base64, no salt/ciphertext
	partial := base64.StdEncoding.EncodeToString([]byte("Salted__"))
	_, err := DecryptOpenSSLSalted(passphrase, partial)
	if err == nil {
		t.Fatal("Expected error for truncated salted data, got none")
	} else {
		t.Logf("Correctly got error for truncated salted data: %v", err)
	}
}

func TestOpenSSLSaltedTruncatedCipher(t *testing.T) {
	passphrase := []byte("testing")

	// Proper "Salted__" + 8-byte salt, but no ciphertext after
	prefix := []byte("Salted__")
	salt := make([]byte, 8)
	truncatedData := append(prefix, salt...) // no ciphertext appended

	b64 := base64.StdEncoding.EncodeToString(truncatedData)
	_, err := DecryptOpenSSLSalted(passphrase, b64)
	if err == nil {
		t.Fatal("Expected error for truncated ciphertext, got none")
	} else {
		t.Logf("Correctly got error for truncated ciphertext: %v", err)
	}
}

func TestEmptyTextAESGCM(t *testing.T) {
	encryptionKey := make([]byte, 32)
	emptyText := ""

	ciphertext, err := Encrypt(encryptionKey, emptyText)
	if err != nil {
		t.Fatalf("Encrypt returned error on empty string: %v", err)
	}

	decrypted, err := Decrypt(encryptionKey, ciphertext)
	if err != nil {
		t.Fatalf("Decrypt returned error on empty string: %v", err)
	}

	if decrypted != emptyText {
		t.Fatalf("Expected empty string, got '%s'", decrypted)
	}
}

func TestEmptyTextOpenSSLSalted(t *testing.T) {
	passphrase := []byte("somepass")
	emptyText := ""

	ciphertext, err := EncryptOpenSSLSalted(passphrase, emptyText)
	if err != nil {
		t.Fatalf("EncryptOpenSSLSalted returned error on empty string: %v", err)
	}

	decrypted, err := DecryptOpenSSLSalted(passphrase, ciphertext)
	if err != nil {
		t.Fatalf("DecryptOpenSSLSalted returned error on empty string: %v", err)
	}

	if decrypted != emptyText {
		t.Fatalf("Expected empty string, got '%s'", decrypted)
	}
}

func TestOpenSSLKeyMismatch(t *testing.T) {
	passphrase1 := []byte("pass1")
	passphrase2 := []byte("pass2")
	plaintext := "Mismatch test"

	cipher, err := EncryptOpenSSLSalted(passphrase1, plaintext)
	if err != nil {
		t.Fatalf("EncryptOpenSSLSalted error: %v", err)
	}

	// Attempt to decrypt with a different passphrase
	_, err = DecryptOpenSSLSalted(passphrase2, cipher)
	if err == nil {
		t.Fatal("Expected decryption error with mismatched passphrase, got none")
	} else {
		t.Logf("Correctly got error on mismatched passphrase: %v", err)
	}
}

func TestAESGCMKeyMismatch(t *testing.T) {
	key1 := make([]byte, 32)
	key2 := make([]byte, 32)
	for i := 0; i < 32; i++ {
		key1[i] = byte(i)
		key2[i] = byte(31 - i)
	}
	plaintext := "Mismatch test"

	ciphertext, err := Encrypt(key1, plaintext)
	if err != nil {
		t.Fatalf("Encrypt error: %v", err)
	}

	_, err = Decrypt(key2, ciphertext)
	if err == nil {
		t.Fatal("Expected error decrypting with a different key, got none")
	} else {
		t.Logf("Correctly got error with mismatched AES-GCM key: %v", err)
	}
}

