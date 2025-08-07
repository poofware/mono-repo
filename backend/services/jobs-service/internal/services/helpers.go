// meta-service/services/jobs-service/internal/services/helpers.go

package services

import (
	"context"
	"fmt"
	"slices"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/poofware/mono-repo/backend/services/jobs-service/internal/constants"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-repositories"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
	"github.com/sendgrid/sendgrid-go"
	"github.com/sendgrid/sendgrid-go/helpers/mail"
	"github.com/twilio/twilio-go"
	twilioApi "github.com/twilio/twilio-go/rest/api/v2010"
)

// MODIFIED: Updated HTML with a more modern design, more details, and a prominent "I'm On It" button.
const internalEscalationEmailHTML = `<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Job Escalation Alert</title>
<style>
  body { font-family: -apple-system, 
BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; background-color: #fcf8e3;
 color: #8a6d3b; margin: 0; padding: 20px; }
  .container { max-width: 600px; margin: auto; background: #fff; border: 1px solid #faebcc; border-radius: 8px; }
  .header { background-color: #fcf8e3; padding: 15px 20px; border-bottom: 1px solid #faebcc; }
  .header h1 { margin: 0;
 font-size: 20px; color: #8a6d3b; }
  .content { padding: 20px; }
  .content p { margin-top: 0; }
  ul { list-style: none; padding: 0; }
  li { padding: 8px; border-bottom: 1px solid #eee; }
  li:last-child { border-bottom: none; }
   strong { color: #333; }
  .button-container { text-align: center; margin: 20px 0; }
  .button {
    background-color: #337ab7;
    color: white !important;
    padding: 12px 25px;
    text-decoration: none;
    border-radius: 5px;
    font-weight: bold;
    display: inline-block;
  }
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
         <li><strong>Address:</strong> %s</li>
        <li><strong>Alert Details:</strong> %s</li>
     <li><strong>Original Time Window:</strong> %s</li>
         <li><strong>Latest Start Time (No-Show):</strong> %s</li>
        <li><strong>Buildings & Units:</strong><ul>%s</ul></li>
        <li><strong>Timestamp (UTC):</strong> %s</li>
      </ul>
      <div class="button-container">
        <a href="%s" class="button">I'm On It</a>
      </div>
    </div>
  </div>
</body>
</html>`

// MODIFIED: Team notification now includes full job details.
const teamNotificationEmailHTML = `<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Team Job Alert</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; background-color: #f3f4f6; color: #1f2937; margin: 0; padding: 20px; }
  .container { max-width: 600px; margin: auto; background: #fff; border: 1px solid #e5e7eb; border-radius: 8px;
 }
  .header { background-color: #dbeafe; padding: 15px 20px; border-bottom: 1px solid #bfdbfe; }
  .header h1 { margin: 0; font-size: 20px; color: #1e40af; }
  .content { padding: 20px; }
  .content p { margin-top: 0; }
  ul { list-style: 
 none; padding: 0; }
  li { padding: 8px; border-bottom: 1px solid #eee; }
  li:last-child { border-bottom: none; }
  strong { color: #000; }
</style>
</head>
<body>
  <div class="container">
  
  <div class="header">
      <h1>%s</h1>
    </div>
    <div class="content">
      <p>This is an automated alert for the operations team.</p>
      <ul>
        <li><strong>Property:</strong> %s</li>
        <li><strong>Address:</strong> %s</li>
         <li><strong>Definition ID:</strong> %s</li>
        <li><strong>Alert Details:</strong> %s</li>
        <li><strong>Buildings & Units:</strong><ul>%s</ul></li>
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

// MODIFIED: This function has been updated to require a JobInstance and repositories to fetch human-readable data.
func NotifyOnCallAgents(
	ctx context.Context,
	appURL string,
	prop *models.Property,
	def *models.JobDefinition,
	inst *models.JobInstance,
	messageTitle string,
	messageBody string,
	agentRepo repositories.AgentRepository,
	ajcRepo repositories.AgentJobCompletionRepository,
	bldgRepo repositories.PropertyBuildingRepository,
	unitRepo repositories.UnitRepository,
	twClient *twilio.RestClient,
	sgClient *sendgrid.Client,
	fromPhone string,
	fromEmail string,
	orgName string,
	sendgridSandbox bool,
) {
	// 1) Fetch ALL on-call reps and filter by proximity in-memory.
	// This removes the dependency on the earthdistance PG extension.
	allReps, err := agentRepo.ListAll(ctx)
	if err != nil {
		utils.Logger.WithError(err).Error("NotifyOnCallAgents: list all reps failed")
		// Do not return here; we still want to notify the internal team.
	}

	var reps []*models.Agent
	if prop != nil {
		for _, r := range allReps {
			distMiles := utils.DistanceMiles(prop.Latitude, prop.Longitude, r.Latitude, r.Longitude)
			if distMiles <= constants.RadiusMilesToNotifyAgents {
				reps = append(reps, r)
			}
		}
	} else {
		reps = allReps
	}

	// 2) Prepare property name (if found) and final subject/body
	propertyName := "(Unknown Property)"
	propertyAddress := "(Unknown Address)"
	if prop != nil {
		if prop.PropertyName != "" {
			propertyName = prop.PropertyName
		}
		propertyAddress = fmt.Sprintf("%s, %s, %s %s", prop.Address, prop.City, prop.State, prop.ZipCode)
	}
	subject := fmt.Sprintf("%s: %s", messageTitle, propertyName)

	// MODIFIED: Extract and format job details for notifications.
	propLoc := loadPropertyLocation(prop.TimeZone)
	// For notifications, we assume "today" in the property's timezone is the relevant service date.
	serviceDate := dateOnlyInLocation(time.Now().In(propLoc), propLoc)
	eStartLocal := time.Date(serviceDate.Year(), serviceDate.Month(), serviceDate.Day(), def.EarliestStartTime.Hour(), def.EarliestStartTime.Minute(), 0, 0, propLoc)
	lStartLocal := time.Date(serviceDate.Year(), serviceDate.Month(), serviceDate.Day(), def.LatestStartTime.Hour(), def.LatestStartTime.Minute(), 0, 0, propLoc)
	noShowTimeLocal := lStartLocal.Add(-constants.NoShowCutoffBeforeLatestStart)

	timeWindowStr := fmt.Sprintf("%s - %s", eStartLocal.Format("3:04 PM"), lStartLocal.Format("3:04 PM MST"))
	noShowTimeStr := noShowTimeLocal.Format("3:04 PM MST")

	var buildingsAndUnits strings.Builder
	var buildingsAndUnitsPlainText strings.Builder
	for _, group := range def.AssignedUnitsByBuilding {
		bldg, err := bldgRepo.GetByID(ctx, group.BuildingID)
		if err != nil || bldg == nil {
			buildingsAndUnits.WriteString(fmt.Sprintf("<li>Building (ID: %s): %d units</li>", group.BuildingID, len(group.UnitIDs)))
			buildingsAndUnitsPlainText.WriteString(fmt.Sprintf("\n- Building (ID: %s): %d units", group.BuildingID, len(group.UnitIDs)))
			continue
		}

		var unitNumbers []string
		for _, unitID := range group.UnitIDs {
			unit, err := unitRepo.GetByID(ctx, unitID)
			if err == nil && unit != nil {
				unitNumbers = append(unitNumbers, unit.UnitNumber)
			}
		}
		sort.Strings(unitNumbers) // Sort for consistent output

		buildingsAndUnits.WriteString(fmt.Sprintf("<li><strong>%s:</strong> %s</li>", bldg.BuildingName, strings.Join(unitNumbers, ", ")))
		buildingsAndUnitsPlainText.WriteString(fmt.Sprintf("\n- %s: %s", bldg.BuildingName, strings.Join(unitNumbers, ", ")))
	}
	// END MODIFICATION

	// 3) Send notifications to each rep
	for _, r := range reps {
		// ---------- Generate and Store Token ----------
		token := uuid.NewString()
		completionRecord := &models.AgentJobCompletion{
			ID:            uuid.New(),
			JobInstanceID: inst.ID,
			AgentID:       r.ID,
			Token:         token,
			ExpiresAt:     time.Now().Add(24 * time.Hour),
		}
		if err := ajcRepo.Create(ctx, completionRecord); err != nil {
			utils.Logger.WithError(err).Warnf("Failed to create completion token for agent %s", r.ID)
			continue // Skip notification if token can't be created
		}
		confirmationLink := fmt.Sprintf("%s/api/v1/jobs/agent-complete/%s", appURL, token)

		// ---------- Prepare Email and SMS Content ----------
		// MODIFIED: Add more job details to the plain text body for SMS.
		plainTextBody := fmt.Sprintf(
			"%s\n\nProperty: %s\nAddress: %s\nTime Window: %s\nNo-Show Time: %s\n\nDetails:%s\n\nI'm On It: %s",
			messageBody,
			propertyName,
			propertyAddress,
			timeWindowStr,
			noShowTimeStr,
			buildingsAndUnitsPlainText.String(),
			confirmationLink,
		)

		// MODIFIED: Pass dynamic job details to the HTML template.
		htmlBody := fmt.Sprintf(
			internalEscalationEmailHTML,
			subject,
			propertyName,
			propertyAddress,
			messageBody,
			timeWindowStr,
			noShowTimeStr,
			buildingsAndUnits.String(),
			time.Now().UTC().Format(time.RFC1123Z),
			confirmationLink,
		)

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
			msg.TrackingSettings = &mail.TrackingSettings{
				ClickTracking: &mail.ClickTrackingSetting{
					Enable: utils.Ptr(false),
				},
			}
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

	// ---------- MODIFIED: Always send a detailed notification to the internal team ----------
	if sgClient != nil {
		teamEmail := "team@thepoofapp.com"
		teamSubject := fmt.Sprintf("[Internal Alert] %s", subject)
		teamPlainText := fmt.Sprintf(
			"An automated alert was triggered.\n\nTitle: %s\nProperty: %s\nAddress: %s\nDefinition ID: %s\nDetails: %s\nUnits:%s",
			messageTitle, propertyName, propertyAddress, def.ID.String(), messageBody, buildingsAndUnitsPlainText.String(),
		)
		teamHtmlBody := fmt.Sprintf(
			teamNotificationEmailHTML,
			teamSubject,
			propertyName,
			propertyAddress,
			def.ID.String(),
			messageBody,
			buildingsAndUnits.String(),
			time.Now().UTC().Format(time.RFC1123Z),
		)

		from := mail.NewEmail(fmt.Sprintf("%s Bot", orgName), fromEmail)
		to := mail.NewEmail("Poof Operations Team", teamEmail)
		msg := mail.NewSingleEmail(from, teamSubject, to, teamPlainText, teamHtmlBody)
		if sendgridSandbox {
			ms := mail.NewMailSettings()
			ms.SetSandboxMode(mail.NewSetting(true))
			msg.MailSettings = ms
		}
		if _, sgErr := sgClient.Send(msg); sgErr != nil {
			utils.Logger.WithError(sgErr).Errorf("Failed to send internal team notification to %s", teamEmail)
		} else {
			utils.Logger.Infof("Successfully sent internal team notification to %s for event: %s", teamEmail, messageTitle)
		}
	} else {
		utils.Logger.Warn("SendGrid client is nil, skipping internal team notification.")
	}
}
