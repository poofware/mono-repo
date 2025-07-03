package checkr

import (
	"context"
	"fmt"
)

// CreateWebhook to register a new callback endpoint for your Checkr account.
func (c *CheckrClient) CreateWebhook(ctx context.Context, body map[string]any) (*Webhook, error) {
	var wh Webhook
	if err := c.doRequest(ctx, "POST", "webhooks", body, &wh, nil); err != nil {
		return nil, fmt.Errorf("CreateWebhook error: %w", err)
	}
	return &wh, nil
}

// ListWebhooks enumerates all webhooks in your account.
func (c *CheckrClient) ListWebhooks(ctx context.Context) ([]Webhook, error) {
	var resp struct {
		Object string    `json:"object,omitempty"`
		Data   []Webhook `json:"data,omitempty"`
		Count  int       `json:"count,omitempty"`
	}
	if err := c.doRequest(ctx, "GET", "webhooks", nil, &resp, nil); err != nil {
		return nil, fmt.Errorf("ListWebhooks error: %w", err)
	}
	return resp.Data, nil
}

// GetWebhook returns details for a single webhook ID.
func (c *CheckrClient) GetWebhook(ctx context.Context, webhookID string) (*Webhook, error) {
	endpoint := fmt.Sprintf("webhooks/%s", webhookID)
	var wh Webhook
	if err := c.doRequest(ctx, "GET", endpoint, nil, &wh, nil); err != nil {
		return nil, fmt.Errorf("GetWebhook error: %w", err)
	}
	return &wh, nil
}

// DeleteWebhook removes a webhook from your account.
func (c *CheckrClient) DeleteWebhook(ctx context.Context, webhookID string) (*Webhook, error) {
	endpoint := fmt.Sprintf("webhooks/%s", webhookID)
	var wh Webhook
	if err := c.doRequest(ctx, "DELETE", endpoint, nil, &wh, nil); err != nil {
		return nil, fmt.Errorf("DeleteWebhook error: %w", err)
	}
	return &wh, nil
}

