package utils

func Ptr[T any](v T) *T {
    return &v
}

// StrPtr is a simple helper to get a pointer to a string literal.
func StrPtr(s string) *string {
	return &s
}

func Val[T any](p *T) T {
    if p != nil {
        return *p
    }
    var zero T
    return zero
}
