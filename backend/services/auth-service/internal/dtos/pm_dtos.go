package dtos

import (
    "github.com/poofware/go-dtos"
)

// ----------------------
// Requests
// ----------------------

type RegisterPMRequest struct {
    FirstName                string  `json:"first_name" validate:"required,min=1,max=100"`
    LastName                 string  `json:"last_name" validate:"required,min=1,max=100"`
    Email                    string  `json:"email" validate:"required,email"`
    PhoneNumber              *string `json:"phone_number,omitempty" validate:"omitempty"`
    BusinessName             string  `json:"business_name" validate:"required,min=1,max=255"`
    BusinessAddress          string  `json:"business_address" validate:"required,min=1,max=255"`
    City                     string  `json:"city" validate:"required,min=1,max=100"`
    State                    string  `json:"state" validate:"required,min=1,max=50"`
    ZipCode                  string  `json:"zip_code" validate:"required,min=1,max=20"`
    TOTPSecret               string  `json:"totp_secret" validate:"required"`
    TOTPToken                string  `json:"totp_token" validate:"required"`
}

type LoginPMRequest struct {
    Email    string `json:"email" validate:"required,email"`
    TOTPCode string `json:"totp_code" validate:"required,len=6,numeric"`
}

// ----------------------
// Responses
// ----------------------

type RegisterPMResponse struct {
    Message string `json:"message"`
}

type LoginPMResponse struct {
    PM           dtos.PropertyManager `json:"pm"`
    AccessToken  string                `json:"access_token,omitempty"`
    RefreshToken string                `json:"refresh_token,omitempty"`
}

