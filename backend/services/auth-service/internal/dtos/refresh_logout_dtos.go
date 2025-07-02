package dtos

// ----------------------
// Refresh Token
// ----------------------

type RefreshTokenRequest struct {
	RefreshToken string `json:"refresh_token" validate:"required,len=64"`
}

type RefreshTokenResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
}

// ----------------------
// Logout
// ----------------------

type LogoutRequest struct {
	RefreshToken string `json:"refresh_token" validate:"required,len=64"`
}

type LogoutResponse struct {
	Message string `json:"message"`
}

