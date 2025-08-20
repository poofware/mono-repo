package services

import (
	"sync"

	"github.com/poofware/mono-repo/backend/shared/go-utils"
    stripe "github.com/stripe/stripe-go/v82"
)

type StripeWebhookCheckService struct {

	mu     sync.Mutex
    events map[string]struct{}

}

func NewStripeWebhookCheckService() *StripeWebhookCheckService {
	return &StripeWebhookCheckService{
		events: make(map[string]struct{}),
	}
}

// PaymentIntent Created for ephemeral "webhook_check" script
func (s *StripeWebhookCheckService) HandlePaymentIntentCreated(eventID string, pi *stripe.PaymentIntent) {
    s.mu.Lock()
    s.events[eventID] = struct{}{}
    s.mu.Unlock()
    utils.Logger.Infof("Captured webhook check event (payment_intent.created) with ID=%s", eventID)
}

// If ephemeral "webhook_check" route sees an event ID, it calls this
func (s *StripeWebhookCheckService) ConsumeWebhookCheckEvent(eventID string) bool {
    s.mu.Lock()
    defer s.mu.Unlock()

    _, found := s.events[eventID]
    if found {
        delete(s.events, eventID)
    }
    return found
}




