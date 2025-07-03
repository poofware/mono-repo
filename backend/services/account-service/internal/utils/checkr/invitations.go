package checkr

import (
	"context"
	"fmt"
	"net/url"
)

// CreateInvitation to host the candidate apply flow on Checkr.
func (c *CheckrClient) CreateInvitation(ctx context.Context, inv Invitation) (*Invitation, error) {
	var created Invitation
	if err := c.doRequest(ctx, "POST", "invitations", inv, &created, nil); err != nil {
		return nil, fmt.Errorf("CreateInvitation error: %w", err)
	}
	return &created, nil
}

// GetInvitation fetches an existing invitation by ID.
func (c *CheckrClient) GetInvitation(ctx context.Context, invitationID string) (*Invitation, error) {
	endpoint := fmt.Sprintf("invitations/%s", invitationID)
	var inv Invitation
	if err := c.doRequest(ctx, "GET", endpoint, nil, &inv, nil); err != nil {
		return nil, fmt.Errorf("GetInvitation error: %w", err)
	}
	return &inv, nil
}

// DeleteInvitation (cancel) by ID.
func (c *CheckrClient) DeleteInvitation(ctx context.Context, invitationID string) error {
	endpoint := fmt.Sprintf("invitations/%s", invitationID)
	if err := c.doRequest(ctx, "DELETE", endpoint, nil, nil, nil); err != nil {
		return fmt.Errorf("DeleteInvitation error: %w", err)
	}
	return nil
}

// ListInvitations with optional candidateID, status, page, perPage
func (c *CheckrClient) ListInvitations(ctx context.Context, candidateID, status string, page, perPage int) ([]Invitation, error) {
	vals := url.Values{}
	if candidateID != "" {
		vals.Set("candidate_id", candidateID)
	}
	if status != "" {
		vals.Set("status", status)
	}
	// optional clamp for page/perPage
	if page < 1 {
		page = 1
	}
	if perPage < 1 {
		perPage = 25
	} else if perPage > 100 {
		perPage = 100
	}
	vals.Set("page", fmt.Sprintf("%d", page))
	vals.Set("per_page", fmt.Sprintf("%d", perPage))

	u := fmt.Sprintf("invitations?%s", vals.Encode())

	var resp struct {
		Object string       `json:"object,omitempty"`
		Data   []Invitation `json:"data,omitempty"`
		Count  int          `json:"count,omitempty"`
	}
	if err := c.doRequest(ctx, "GET", u, nil, &resp, nil); err != nil {
		return nil, fmt.Errorf("ListInvitations error: %w", err)
	}
	return resp.Data, nil
}

