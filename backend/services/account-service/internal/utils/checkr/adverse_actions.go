package checkr

import (
	"context"
	"fmt"
)

// GetAdverseItems returns the items that might lead to a "consider" outcome
func (c *CheckrClient) GetAdverseItems(ctx context.Context, reportID string) ([]AdverseItem, error) {
	endpoint := fmt.Sprintf("reports/%s/adverse_items", reportID)
	var resp struct {
		Data []AdverseItem `json:"data,omitempty"`
	}
	if err := c.doRequest(ctx, "GET", endpoint, nil, &resp, nil); err != nil {
		return nil, fmt.Errorf("GetAdverseItems error: %w", err)
	}
	return resp.Data, nil
}

// CreateAdverseAction starts an Adverse Action. The body typically has "adverse_item_ids" and scheduling data.
func (c *CheckrClient) CreateAdverseAction(ctx context.Context, reportID string, body map[string]any) (*AdverseAction, error) {
	endpoint := fmt.Sprintf("reports/%s/adverse_actions", reportID)
	var aa AdverseAction
	if err := c.doRequest(ctx, "POST", endpoint, body, &aa, nil); err != nil {
		return nil, fmt.Errorf("CreateAdverseAction error: %w", err)
	}
	return &aa, nil
}

// GetAdverseAction fetches an existing Adverse Action by ID
func (c *CheckrClient) GetAdverseAction(ctx context.Context, adverseActionID string) (*AdverseAction, error) {
	endpoint := fmt.Sprintf("adverse_actions/%s", adverseActionID)
	var aa AdverseAction
	if err := c.doRequest(ctx, "GET", endpoint, nil, &aa, nil); err != nil {
		return nil, fmt.Errorf("GetAdverseAction error: %w", err)
	}
	return &aa, nil
}

// CancelAdverseAction cancels an existing, pending Adverse Action
func (c *CheckrClient) CancelAdverseAction(ctx context.Context, adverseActionID string) (*AdverseAction, error) {
	endpoint := fmt.Sprintf("adverse_actions/%s", adverseActionID)
	var aa AdverseAction
	if err := c.doRequest(ctx, "DELETE", endpoint, nil, &aa, nil); err != nil {
		return nil, fmt.Errorf("CancelAdverseAction error: %w", err)
	}
	return &aa, nil
}

