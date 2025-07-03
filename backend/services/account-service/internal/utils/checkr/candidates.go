package checkr

import (
	"context"
	"errors"
	"fmt"
)

// CreateCandidate creates a new candidate.
// We'll do a small local check regarding no_middle_name vs. middle_name
// to avoid immediate 400 from the server if the user incorrectly sets both.
func (c *CheckrClient) CreateCandidate(ctx context.Context, cand Candidate) (*Candidate, error) {
	if cand.NoMiddleName && cand.MiddleName != "" {
		return nil, errors.New("cannot have 'no_middle_name=true' and also provide 'middle_name'")
	}

	var created Candidate
	if err := c.doRequest(ctx, "POST", "candidates", cand, &created, nil); err != nil {
		return nil, fmt.Errorf("CreateCandidate error: %w", err)
	}
	return &created, nil
}

// GetCandidate retrieves a candidate by ID.
func (c *CheckrClient) GetCandidate(ctx context.Context, candidateID string) (*Candidate, error) {
	endpoint := fmt.Sprintf("candidates/%s", candidateID)
	var cand Candidate
	if err := c.doRequest(ctx, "GET", endpoint, nil, &cand, nil); err != nil {
		return nil, fmt.Errorf("GetCandidate error: %w", err)
	}
	return &cand, nil
}

// UpdateCandidate updates fields on an existing candidate.
func (c *CheckrClient) UpdateCandidate(ctx context.Context, candidateID string, updates Candidate) (*Candidate, error) {
	// local check re: no_middle_name conflict
	if updates.NoMiddleName && updates.MiddleName != "" {
		return nil, errors.New("cannot have 'no_middle_name=true' and also provide 'middle_name'")
	}

	endpoint := fmt.Sprintf("candidates/%s", candidateID)
	var updated Candidate
	if err := c.doRequest(ctx, "POST", endpoint, updates, &updated, nil); err != nil {
		return nil, fmt.Errorf("UpdateCandidate error: %w", err)
	}
	return &updated, nil
}

