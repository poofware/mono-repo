package checkr

import (
	"context"
	"fmt"
)

// GetReport fetches a single report by ID.
func (c *CheckrClient) GetReport(ctx context.Context, reportID string) (*Report, error) {
	endpoint := fmt.Sprintf("reports/%s", reportID)
	var rep Report
	if err := c.doRequest(ctx, "GET", endpoint, nil, &rep, nil); err != nil {
		return nil, fmt.Errorf("GetReport error: %w", err)
	}
	return &rep, nil
}

// GetReportETA obtains the ETA for a given report (some screenings may take longer).
func (c *CheckrClient) GetReportETA(ctx context.Context, reportID string) (*ETAResponse, error) {
	endpoint := fmt.Sprintf("reports/%s/eta", reportID)
	var eta ETAResponse
	if err := c.doRequest(ctx, "GET", endpoint, nil, &eta, nil); err != nil {
		return nil, fmt.Errorf("GetReportETA error: %w", err)
	}
	return &eta, nil
}

// UpdateReport can update certain fields (like package or adjudication).
func (c *CheckrClient) UpdateReport(ctx context.Context, reportID string, updates map[string]any) (*Report, error) {
	endpoint := fmt.Sprintf("reports/%s", reportID)
	var rep Report
	if err := c.doRequest(ctx, "POST", endpoint, updates, &rep, nil); err != nil {
		return nil, fmt.Errorf("UpdateReport error: %w", err)
	}
	return &rep, nil
}

// CreateReport is for self-hosted flows (if you have candidate PII yourself).
func (c *CheckrClient) CreateReport(ctx context.Context, data map[string]any, opts *requestOptions) (*Report, error) {
	var rep Report
	// pass in optional IdempotencyKey, etc.
	if err := c.doRequest(ctx, "POST", "reports", data, &rep, opts); err != nil {
		return nil, fmt.Errorf("CreateReport error: %w", err)
	}
	return &rep, nil
}

