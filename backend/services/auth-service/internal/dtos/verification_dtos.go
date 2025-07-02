package dtos

// ----------------------
// SMS Verification
// ----------------------

type RequestSMSCodeRequest struct {
    PhoneNumber string `json:"phone_number" validate:"required,e164"`
}
type RequestSMSCodeResponse struct {
    Message string `json:"message"`
}

type VerifySMSCodeRequest struct {
    PhoneNumber string `json:"phone_number" validate:"required,e164"`
    Code        string `json:"code" validate:"required,len=6,numeric"`
}
type VerifySMSCodeResponse struct {
    Message string `json:"message"`
}

// ----------------------
// Email Verification
// ----------------------

type RequestEmailCodeRequest struct {
    Email string `json:"email" validate:"required,email"`
}
type RequestEmailCodeResponse struct {
    Message string `json:"message"`
}

type VerifyEmailCodeRequest struct {
    Email string `json:"email" validate:"required,email"`
    Code  string `json:"code" validate:"required,len=6,numeric"`
}
type VerifyEmailCodeResponse struct {
    Message string `json:"message"`
}

