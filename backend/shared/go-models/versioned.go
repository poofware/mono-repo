// go-models/versioned.go
package models

// Versioned adds optimistic‑lock helpers. Embed it anonymously.
type Versioned struct {
	RowVersion int64 `json:"row_version"`
}

// ----- interface helpers -----
func (v *Versioned) GetRowVersion() int64   { return v.RowVersion }
func (v *Versioned) SetRowVersion(n int64)  { v.RowVersion = n }
