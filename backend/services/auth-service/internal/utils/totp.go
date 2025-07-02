package utils

import (
    "github.com/pquerna/otp/totp"
)

func GenerateTOTPSecret(appName string, accountName string) (string, error) {
    key, err := totp.Generate(totp.GenerateOpts{
        Issuer:      appName,
        AccountName: accountName,
    })
    if err != nil {
        return "", err
    }
    return key.Secret(), nil
}


func ValidateTOTPCode(secret, code string) bool {
    return totp.Validate(code, secret)
}
