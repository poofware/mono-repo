// meta-service/services/jobs-service/internal/services/helpers.go

package services

import (
	"context"
	"fmt"
	"slices"
	"time"

	"github.com/google/uuid"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-repositories"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
	"github.com/sendgrid/sendgrid-go"
	"github.com/sendgrid/sendgrid-go/helpers/mail"
	"github.com/twilio/twilio-go"
	twilioApi "github.com/twilio/twilio-go/rest/api/v2010"
)

// NEW: HTML template for internal escalation alerts.
const internalEscalationEmailHTML = `<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Job Escalation Alert</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; background-color: #fcf8e3; color: #8a6d3b; margin: 0; padding: 20px; }
  .container { max-width: 600px; margin: auto; background: #fff; border: 1px solid #faebcc; border-radius: 8px; }
  .header { background-color: #fcf8e3; padding: 15px 20px; border-bottom: 1px solid #faebcc; }
  .header h1 { margin: 0; font-size: 20px; color: #8a6d3b; }
  .content { padding: 20px; }
  .content p { margin-top: 0; }
  ul { list-style: none; padding: 0; }
  li { padding: 8px; border-bottom: 1px solid #eee; }
  li:last-child { border-bottom: none; }
  strong { color: #333; }
</style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>%s</h1>
    </div>
    <div class="content">
      <p>An automated escalation has occurred for the following job. Please review immediately.</p>
      <ul>
        <li><strong>Property:</strong> %s</li>
        <li><strong>Definition ID:</strong> %s</li>
        <li><strong>Alert Details:</strong> %s</li>
        <li><strong>Timestamp (UTC):</strong> %s</li>
      </ul>
    </div>
  </div>
</body>
</html>`

/*─────────────────── generic helpers (no GMaps deps) ──────────────────*/

func DateOnly(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, t.Location())
}

func inExceptions(list []time.Time, day time.Time) bool {
	for _, d := range list {
		if d.Year() == day.Year() && d.Month() == day.Month() && d.Day() == day.Day() {
			return true
		}
	}
	return false
}

func containsShort(arr []int16, val int16) bool {
	return slices.Contains(arr, val)
}

func lastDayOfMonth(t time.Time) time.Time {
	n := t.AddDate(0, 1, 0)
	return time.Date(n.Year(), n.Month(), 1, 0, 0, 0, 0, t.Location()).AddDate(0, 0, -1)
}

func formatTimeInLocation(t time.Time, loc *time.Location) string {
	if t.IsZero() {
		return ""
	}
	return t.In(loc).Format("15:04")
}

func loadPropertyLocation(tz string) *time.Location {
	if tz == "" {
		tz = "UTC"
	}
	loc, err := time.LoadLocation(tz)
	if err != nil {
		return time.UTC
	}
	return loc
}

// dateOnlyInLocation returns the exact instant of local midnight
// for the calendar day that 't' falls in when viewed in 'loc'.
// The Location is left as 'loc' so later .Weekday(), .Hour(), etc.
// all reflect the property’s own time-zone.
func dateOnlyInLocation(t time.Time, loc *time.Location) time.Time {
	y, m, d := t.In(loc).Date()
	return time.Date(y, m, d, 0, 0, 0, 0, loc)
}

func ContainsUUID(list []uuid.UUID, val uuid.UUID) bool {
	return slices.Contains(list, val)
}

// CombineDateTime combines a UTC date (d) with a time-of-day (t).
// `d` should be a date at midnight UTC.
// `t` is a time.Time where only the Hour, Minute, and Second are relevant.
func CombineDateTime(d time.Time, t time.Time) time.Time {
	if t.IsZero() {
		return time.Time{}
	}
	return time.Date(d.Year(), d.Month(), d.Day(), t.Hour(), t.Minute(), t.Second(), 0, time.UTC)
}

// NotifyOnCallAgents centralizes Twilio + SendGrid notifications for on-call staff.
func NotifyOnCallAgents(
	ctx context.Context,
	prop *models.Property,
	defID string,
	messageTitle string,
	messageBody string,
	agentRepo repositories.AgentRepository,
	twClient *twilio.RestClient,
	sgClient *sendgrid.Client,
	fromPhone string,
	fromEmail string,
	orgName string,
	sendgridSandbox bool,
) {
	// 1) Fetch on-call reps near the property's location (default radius 50 miles)
	var (
		reps []*models.Agent
		err  error
	)
	if prop != nil {
		reps, err = agentRepo.ListByProximity(ctx, prop.Latitude, prop.Longitude, 50)
	} else {
		reps, err = agentRepo.ListAll(ctx)
	}
	if err != nil {
		utils.Logger.WithError(err).Error("NotifyOnCallAgents: list reps failed")
		return
	}

	// 2) Prepare property name (if found) and final subject/body
	propertyName := "(Unknown Property)"
	if prop != nil && prop.PropertyName != "" {
		propertyName = prop.PropertyName
	}
	subject := fmt.Sprintf("%s (DefinitionID=%s)", messageTitle, defID)
	// Plain text version for SMS and email fallback
	plainTextBody := fmt.Sprintf(
		"%s\nProperty: %s\nDefinitionID: %s",
		messageBody,
		propertyName,
		defID,
	)
	// HTML version for email
	htmlBody := fmt.Sprintf(
		internalEscalationEmailHTML,
		subject,
		propertyName,
		defID,
		messageBody,
		time.Now().UTC().Format(time.RFC1123Z),
	)

	// 3) Send notifications to each rep
	for _, r := range reps {
		// ---------- Twilio SMS ----------
		if twClient != nil {
			params := &twilioApi.CreateMessageParams{}
			params.SetTo(r.PhoneNumber)
			params.SetFrom(fromPhone)
			params.SetBody(subject + " :: " + plainTextBody)
			_, smsErr := twClient.Api.CreateMessage(params)
			if smsErr != nil {
				utils.Logger.WithError(smsErr).Warnf("Failed to send on-call SMS to rep %s", r.ID)
			}
		} else {
			utils.Logger.Warnf("Twilio client is nil, skipping SMS to rep %s", r.ID)
		}

		// ---------- SendGrid Email ----------
		if sgClient != nil {
			from := mail.NewEmail(orgName, fromEmail)
			to := mail.NewEmail(r.Name, r.Email)
			msg := mail.NewSingleEmail(from, subject, to, plainTextBody, htmlBody)
			if sendgridSandbox {
				ms := mail.NewMailSettings()
				ms.SetSandboxMode(mail.NewSetting(true))
				msg.MailSettings = ms
			}
			if _, sgErr := sgClient.Send(msg); sgErr != nil {
				utils.Logger.WithError(sgErr).Warnf("Email send failure to rep %s", r.ID)
			}
		} else {
			utils.Logger.Warnf("SendGrid client is nil, skipping email to rep %s", r.ID)
		}
	}
}
