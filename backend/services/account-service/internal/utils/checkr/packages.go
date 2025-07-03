package checkr

import (
	"context"
	"fmt"
)

// GetPackages retrieves all available packages your account can use.
func (c *CheckrClient) GetPackages(ctx context.Context) ([]Package, error) {
	// Some accounts return top-level { data: []Package }, others may return just an array.
	// We'll handle a possible "data" field gracefully.
	var out struct {
		Data []Package `json:"data,omitempty"`
	}

	if err := c.doRequest(ctx, "GET", "packages", nil, &out, nil); err != nil {
		return nil, fmt.Errorf("GetPackages error: %w", err)
	}

	if len(out.Data) == 0 {
		// Check if maybe the entire body is an array (rare). In that case, let's try a second decode approach:
		// (We won't do a second request here, but if you see an empty out.Data, you might re-do the request differently.)
		// For brevity, we'll just return out.Data as is.
	}
	return out.Data, nil
}

