package checkr

import (
	"context"
	"fmt"
)

// CreateContinuousCheck for a candidate. Body might have "type":"criminal", "work_locations", etc.
func (c *CheckrClient) CreateContinuousCheck(ctx context.Context, candidateID string, data map[string]any) (*ContinuousCheck, error) {
	endpoint := fmt.Sprintf("candidates/%s/continuous_checks", candidateID)
	var cc ContinuousCheck
	if err := c.doRequest(ctx, "POST", endpoint, data, &cc, nil); err != nil {
		return nil, fmt.Errorf("CreateContinuousCheck error: %w", err)
	}
	return &cc, nil
}

// ListContinuousChecks returns all continuous checks for a candidate.
func (c *CheckrClient) ListContinuousChecks(ctx context.Context, candidateID string) ([]ContinuousCheck, error) {
	endpoint := fmt.Sprintf("candidates/%s/continuous_checks", candidateID)
	var resp struct {
		Data []ContinuousCheck `json:"data,omitempty"`
	}
	if err := c.doRequest(ctx, "GET", endpoint, nil, &resp, nil); err != nil {
		return nil, fmt.Errorf("ListContinuousChecks error: %w", err)
	}
	return resp.Data, nil
}

// GetContinuousCheck fetches a single continuous check by ID.
func (c *CheckrClient) GetContinuousCheck(ctx context.Context, checkID string) (*ContinuousCheck, error) {
	endpoint := fmt.Sprintf("continuous_checks/%s", checkID)
	var cc ContinuousCheck
	if err := c.doRequest(ctx, "GET", endpoint, nil, &cc, nil); err != nil {
		return nil, fmt.Errorf("GetContinuousCheck error: %w", err)
	}
	return &cc, nil
}

// UpdateContinuousCheck modifies the node or work_locations, etc.
func (c *CheckrClient) UpdateContinuousCheck(ctx context.Context, checkID string, body map[string]any) (*ContinuousCheck, error) {
	endpoint := fmt.Sprintf("continuous_checks/%s", checkID)
	var cc ContinuousCheck
	if err := c.doRequest(ctx, "POST", endpoint, body, &cc, nil); err != nil {
		return nil, fmt.Errorf("UpdateContinuousCheck error: %w", err)
	}
	return &cc, nil
}

// CancelContinuousCheck cancels an existing continuous check by ID.
func (c *CheckrClient) CancelContinuousCheck(ctx context.Context, checkID string) (*ContinuousCheck, error) {
	endpoint := fmt.Sprintf("continuous_checks/%s", checkID)
	var cc ContinuousCheck
	if err := c.doRequest(ctx, "DELETE", endpoint, nil, &cc, nil); err != nil {
		return nil, fmt.Errorf("CancelContinuousCheck error: %w", err)
	}
	return &cc, nil
}

