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

// verificationEmailHTML is a branded template for sending verification codes.
const verificationEmailHTML = `<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Your Verification Code</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; line-height: 1.6; color: #333; background-color: #f8f9fa; margin: 0; padding: 20px; }
  .container { max-width: 500px; margin: auto; background: #ffffff; border: 1px solid #e9ecef; border-radius: 8px; overflow: hidden; }
  .header { background-color: #5b3a9d; color: white; padding: 20px; text-align: center; }
  .header h1 { margin: 0; font-size: 24px; }
  .content { padding: 30px; text-align: center; }
  .code { font-size: 36px; font-weight: bold; letter-spacing: 8px; color: #5b3a9d; background-color: #f1f3f5; padding: 15px 20px; border-radius: 5px; display: inline-block; margin: 20px 0; }
  .footer { background-color: #f8f9fa; padding: 20px; text-align: center; font-size: 12px; color: #6c757d; }
  p { margin-bottom: 1em; }
</style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>Your Verification Code</h1>
    </div>
    <div class="content">
      <p>Please use the following code to complete your verification. This code will expire in 5 minutes.</p>
      <div class="code">%s</div>
      <p>If you did not request this code, you can safely ignore this email.</p>
    </div>
    <div class="footer">
      © %d Poof. All rights reserved.
    </div>
  </div>
</body>
</html>`
