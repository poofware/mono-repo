// meta-service/services/interest-service/internal/services/interest_service.go

package services

import (
	"context"
	"fmt"
	"time"

	"github.com/sendgrid/sendgrid-go"
	"github.com/sendgrid/sendgrid-go/helpers/mail"

	"github.com/poofware/mono-repo/backend/services/interest-service/internal/config"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

// HTML template for the public-facing acknowledgment email.
const ackEmailHTML = `<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Thanks for your interest!</title>
<style>
  body { font-family: 'Poppins', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; line-height: 1.6; color: #333; background-color: #f8f9fa; margin: 0; padding: 20px; }
  .container { max-width: 500px; margin: auto; background: #ffffff; border: 1px solid #e9ecef; border-radius: 8px; overflow: hidden; }
  .header { background-color: #743ee4; color: white; padding: 20px; text-align: center; }
  .header h1 { margin: 0; font-size: 24px; }
  .content { padding: 30px; text-align: left; }
  .footer { background-color: #f8f9fa; padding: 20px; text-align: center; font-size: 12px; color: #6c757d; }
  p { margin-bottom: 1em; }
</style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>Thanks for your interest in Poof!</h1>
    </div>
    <div class="content">
      <p>Hello,</p>
      <p>We've successfully received your information. A member of our team will be in touch with you shortly to discuss next steps.</p>
      <p>We're excited about the possibility of working with you!</p>
    </div>
    <div class="footer">
      © %d Poof. All rights reserved.
    </div>
  </div>
</body>
</html>`

// HTML template for the internal notification email.
const internalNotificationEmailHTML = `<!DOCTYPE html>
<html>
<head>
<style>
  body { font-family: 'Poppins', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; line-height: 1.6; color: #1f2937; background-color: #f5f3ff; margin: 0; padding: 20px; }
  .container { padding: 20px; max-width: 600px; margin: 20px auto; background-color: #ffffff; border: 1px solid #e9d5ff; border-radius: 8px; }
  .header { font-size: 24px; font-weight: bold; color: #743ee4; margin-bottom: 15px; }
  .content { padding: 20px; }
  .footer { margin-top: 20px; font-size: 12px; color: #6b7280; text-align: center; }
  p { margin-bottom: 1em; }
  ul { list-style: none; padding: 0; }
  li { margin-bottom: 10px; }
  strong { color: #000; }
</style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h2>New Prospect Interest</h2>
    </div>
    <div class="content">
      <ul>
        <li><strong>Account Type:</strong> %s</li>
        <li><strong>Email:</strong> %s</li>
        <li><strong>Timestamp (UTC):</strong> %s</li>
      </ul>
    </div>
    <div class="footer">
      © %d Poof. All rights reserved.
    </div>
  </div>
</body>
</html>`

// ------------------------------------------------------------------
// Service
// ------------------------------------------------------------------

type InterestService interface {
	SubmitWorkerInterest(ctx context.Context, email string) error
	SubmitPMInterest(ctx context.Context, email string) error
	Ping(ctx context.Context) error // tiny health-probe
}

type interestService struct {
	cfg            *config.Config
	sendgridClient *sendgrid.Client
}

func NewInterestService(cfg *config.Config) InterestService {
	return &interestService{
		cfg:            cfg,
		sendgridClient: sendgrid.NewSendClient(cfg.SendgridAPIKey),
	}
}

// ------------------------------------------------------------------
// Public API
// ------------------------------------------------------------------

func (s *interestService) SubmitWorkerInterest(ctx context.Context, email string) error {
	return s.submit(ctx, utils.WorkerAccountType, email)
}

func (s *interestService) SubmitPMInterest(ctx context.Context, email string) error {
	return s.submit(ctx, utils.PMAccountType, email)
}

func (s *interestService) Ping(_ context.Context) error {
	// nothing external to check yet; just ensure SendGrid key looks sane
	if len(s.cfg.SendgridAPIKey) < 10 {
		return fmt.Errorf("sendgrid key too short")
	}
	return nil
}

// ------------------------------------------------------------------
// internals
// ------------------------------------------------------------------

func (s *interestService) submit(ctx context.Context, kind string, email string) error {
	//-----------------------------------------------------------------
	// 1) Deliverability / syntax check – mirrors auth-service logic
	//-----------------------------------------------------------------
	ok, err := utils.ValidateEmail(ctx, s.cfg.SendgridAPIKey, email, s.cfg.LDFlag_ValidateEmailWithSG)
	if err != nil {
		return err
	}
	if !ok {
		return utils.ErrInvalidEmail
	}

	//-----------------------------------------------------------------
	// 2) Send internal notification
	//-----------------------------------------------------------------
	if err := s.sendInternal(kind, email); err != nil {
		return err
	}

	//-----------------------------------------------------------------
	// 3) Send acknowledgement to prospect
	//-----------------------------------------------------------------
	return s.sendAck(email)
}

func (s *interestService) sendInternal(kind, fromEmail string) error {
	from := mail.NewEmail(s.cfg.OrganizationName+" Interest-Bot", s.cfg.LDFlag_SendgridFromEmail)
	to := mail.NewEmail("Poof Team", "team@thepoofapp.com")

	subject := fmt.Sprintf("[Interest][%s] %s", kind, fromEmail)
	plainTextContent := fmt.Sprintf(
		`A new %s prospect submitted interest.%sEmail: %s`,
		kind, "\n\n", fromEmail,
	)
	htmlContent := fmt.Sprintf(
		internalNotificationEmailHTML,
		kind,
		fromEmail,
		time.Now().UTC().Format(time.RFC1123Z),
		time.Now().Year(),
	)

	msg := mail.NewSingleEmail(from, subject, to, plainTextContent, htmlContent)
	_, err := s.sendgridClient.Send(msg)
	return err
}

func (s *interestService) sendAck(toAddr string) error {
	from := mail.NewEmail(s.cfg.OrganizationName, s.cfg.LDFlag_SendgridFromEmail)
	to := mail.NewEmail("", toAddr)

	subject := "Thanks for your interest in Poof!"
	plainTextContent := "We received your info and will be in touch soon!\n\n— Team Poof"
	htmlContent := fmt.Sprintf(ackEmailHTML, time.Now().Year())

	msg := mail.NewSingleEmail(from, subject, to, plainTextContent, htmlContent)
	_, err := s.sendgridClient.Send(msg)
	return err
}
