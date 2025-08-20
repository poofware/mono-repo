// backend/shared/go-dtos/error_dtos.go
package dtos

// ValidationErrorDetail is a shared DTO for structured validation error responses.
type ValidationErrorDetail struct {
	Field   string `json:"field"`
	Message string `json:"message"`
	Code    string `json:"code"`
}