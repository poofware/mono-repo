package services

import (
	"sync"

	"github.com/poofware/mono-repo/backend/shared/go-utils"
	stripe "github.com/stripe/stripe-go/v82"
)

// StripeWebhookCheckService is used for ephemeral webhook delivery checks.
type StripeWebhookCheckService struct {
	mu     sync.Mutex
	events map[string]struct{}
}

func NewStripeWebhookCheckService() *StripeWebhookCheckService {
	return &StripeWebhookCheckService{
		events: make(map[string]struct{}),
	}
}

// HandlePaymentIntentCreated is called when a payment_intent.created event is received.
func (s *StripeWebhookCheckService) HandlePaymentIntentCreated(eventID string, pi *stripe.PaymentIntent) {
	s.mu.Lock()
	s.events[eventID] = struct{}{}
	s.mu.Unlock()
	utils.Logger.Infof("Captured webhook check event (payment_intent.created) with ID=%s", eventID)
}

// ConsumeWebhookCheckEvent checks for and consumes a webhook event ID.
func (s *StripeWebhookCheckService) ConsumeWebhookCheckEvent(eventID string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	_, found := s.events[eventID]
	if found {
		delete(s.events, eventID)
	}
	return found
}
