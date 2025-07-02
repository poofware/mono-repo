package dtos

// ------------------------------------------------------------------
//  Requests for “is this new value valid?” checks.
//  Success ⇒ HTTP 200 with an empty body.
//  Failure ⇒ non-200 with one of the error codes in utils/errors.go.
// ------------------------------------------------------------------

// ---------- Property-Manager ----------

type ValidatePMEmailRequest struct {
	Email string `json:"email" validate:"required,email"`
}

type ValidatePMPhoneRequest struct {
	PhoneNumber string `json:"phone_number" validate:"required,e164"`
}

// ---------- Worker ----------

type ValidateWorkerEmailRequest struct {
	Email string `json:"email" validate:"required,email"`
}

type ValidateWorkerPhoneRequest struct {
	PhoneNumber string `json:"phone_number" validate:"required,e164"`
}

