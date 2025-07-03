package dtos

type InterestRequest struct {
	Email string `json:"email" validate:"required,email"`
}

type InterestResponse struct {
	Message string `json:"message"`
}

