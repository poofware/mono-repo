package utils

import (
    "regexp"
)

const (
    OrganizationName = "Poof"
    CORSLowSecurityAllowedOriginLocalhost = "http://localhost:*"
    AppleTeamID = "U8G25F98S2"
    AppleAppID = "com.thepoofapp.worker"
    AppleAppName = "poofworker"
    AndroidAppPackageName = "com.thepoofapp.worker"
    WorkerAccountType = "worker"
    PMAccountType = "pm"
	TestPhoneNumberBase   = "+999"
	TestEmailSuffix       = "testing@thepoofapp.com"
	TestEmailRegexPattern = `^[0-9]+` + TestEmailSuffix + `$`
	GooglePlayStoreReviewerPhone = "+12025550110" 
	GooglePlayStoreReviewerBypassTOTP = "104232"

    WorkerBanThresholdScore     = 60
    WorkerSuspendThresholdScore = 75
    WorkerSuspensionDays        = 7
    WorkerScoreMin              = 0
    WorkerScoreMax              = 100
)

// Pre-compile the test email regex.
var TestEmailRegex = regexp.MustCompile(TestEmailRegexPattern)
