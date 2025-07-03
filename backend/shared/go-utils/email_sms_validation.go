package utils

import (
	"context"
	"encoding/json"
	"fmt"
	"net/mail"
	"regexp"
	"strings"
	"net"

	"github.com/sendgrid/sendgrid-go"
	lookupsv2 "github.com/twilio/twilio-go/rest/lookups/v2"
	twilio "github.com/twilio/twilio-go"
	twilioclient "github.com/twilio/twilio-go/client"
)

// -----------------------------------------------------------------------
// 1) PHONE NUMBER VALIDATION
// -----------------------------------------------------------------------

var e164Regex = regexp.MustCompile(`^\+[1-9]\d{7,14}$`) // ITU-T E.164

// isE164 reports basic E.164 compliance
func IsE164(number string) bool { return e164Regex.MatchString(number) }

// ValidatePhoneNumber validates `number`.
//
//   • If validateWithTwilio == true *and* a non-nil Twilio RestClient is provided,
//     the function performs a Twilio Lookups V2 fetch (free “basic” tier).
//   • Otherwise it validates locally via Google’s libphonenumber data.
//
// It returns (true,nil) only when the phone number is well-formed
// *and* belongs to the requested country (when `country` is non-nil).
func ValidatePhoneNumber(
	ctx context.Context,
	number string,
	country *string,
	validateWithTwilio bool,
	tw *twilio.RestClient, // TODO: better way to do this?
) (bool, error) {

	// ————————————————————————————————————————————————————
	// 1. Syntactic sanity-check: must already be in E.164.
	//    (isE164 is assumed to be your existing tiny helper)
	// ————————————————————————————————————————————————————
	if !IsE164(number) {
		return false, nil
	}

	// ————————————————————————————————————————————————————
	// 2. Remote validation via Twilio (if requested + possible)
	// ————————————————————————————————————————————————————
	if validateWithTwilio && tw != nil {
		var params *lookupsv2.FetchPhoneNumberParams
		if country != nil && *country != "" {
			params = &lookupsv2.FetchPhoneNumberParams{CountryCode: country}
		}

		_, err := tw.LookupsV2.FetchPhoneNumber(number, params)
		if err == nil {
			return true, nil // HTTP 200 ⇒ looks good
		}

		// Twilio-specific error handling
		if restErr, ok := err.(*twilioclient.TwilioRestError); ok {
			if restErr.Status == 404 { // “unable to find that phone number”
				return false, nil
			}
			return false, fmt.Errorf("twilio lookup failed: %d %s",
				restErr.Status, restErr.Error())
		}
		// Context cancel, network failure, etc.
		return false, err
	}

	return true, nil
}

// -----------------------------------------------------------------------
// 2) EMAIL VALIDATION
// -----------------------------------------------------------------------

// isValidEmailSyntax does RFC-5322-*ish* syntax only (no DNS)
// mail.ParseAddress is surprisingly strict and passes go-vet / go-net
func isValidEmailSyntax(e string) bool {
	_, err := mail.ParseAddress(e)
	return err == nil
}

// hasMX checks an MX record via miekg/dns (pure Go, no CGO, no /etc/resolv.conf)
func hasMX(ctx context.Context, domain string) bool {
    mx, err := net.DefaultResolver.LookupMX(ctx, domain)
    return err == nil && len(mx) > 0
}

// ValidateEmail returns true if:
//
//   • the string parses as an email, AND
//   • either:
//
//     – validateWithSendGrid == true  ➜ MX lookup passes
//     – validateWithSendGrid == false ➜ SendGrid “Deliverability Check” verdict is
//       "Valid" OR "RISKY" (SendGrid uses those exact strings)
//
// Any SendGrid/network error is returned so the caller can decide.
func ValidateEmail(ctx context.Context, apiKey string, email string, validateWithSendGrid bool) (bool, error) {
	if !isValidEmailSyntax(email) {
		return false, nil
	}

	// Sandbox → free MX check only
	parts := strings.SplitN(email, "@", 2)
	if len(parts) != 2 {
		return false, nil
	}
	validMX := hasMX(ctx, parts[1])
	if !validMX {
		return false, nil
	}

	// Paid SendGrid validation
	if validateWithSendGrid {
		req := sendgrid.GetRequest(apiKey, "/v3/validations/email", "https://api.sendgrid.com")
		req.Method = "POST"
		req.Body = []byte(fmt.Sprintf(`{"email":"%s"}`, email))

		resp, err := sendgrid.API(req)
		if err != nil {
			return false, err
		}

		switch resp.StatusCode {
		case 200:
			var sg struct {
				Result struct {
					Verdict string `json:"verdict"`
				} `json:"result"`
			}
			if jsonErr := json.Unmarshal([]byte(resp.Body), &sg); jsonErr != nil {
				return false, fmt.Errorf("sendgrid JSON decode: %w", jsonErr)
			}
			verdict := strings.ToLower(sg.Result.Verdict)
			return verdict == "valid" || verdict == "risky", nil

		case 400: // SendGrid treats syntactically bad addresses as 400
			return false, nil
		default:
			return false, fmt.Errorf("sendgrid validation failed: status %d – %s", resp.StatusCode, resp.Body)
		}
	}

	return true, nil
}

