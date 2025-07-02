package dtos

import (
	shared_dtos "github.com/poofware/go-dtos"
)

// ----------------------
// Requests
// ----------------------

type RegisterWorkerRequest struct {
	FirstName   string `json:"first_name" validate:"required,min=1,max=100"`
	LastName    string `json:"last_name" validate:"required,min=1,max=100"`
	Email       string `json:"email" validate:"required,email"`
	PhoneNumber string `json:"phone_number" validate:"required"`
	TOTPSecret  string `json:"totp_secret" validate:"required"`
	TOTPToken   string `json:"totp_token" validate:"required"`
}

type LoginWorkerRequest struct {
	PhoneNumber string `json:"phone_number" validate:"required"`
	TOTPCode    string `json:"totp_code" validate:"required,len=6,numeric"`
}

// ----------------------
// Responses
// ----------------------

type RegisterWorkerResponse struct {
	Message string `json:"message"`
}

type LoginWorkerResponse struct {
	Worker       shared_dtos.Worker `json:"worker"`
	AccessToken  string             `json:"access_token"`
	RefreshToken string             `json:"refresh_token"`
}

type ChallengeResponse struct {
	ChallengeToken string `json:"challenge_token"`
	Challenge      string `json:"challenge"` // This will be the platform-specific challenge string
}

