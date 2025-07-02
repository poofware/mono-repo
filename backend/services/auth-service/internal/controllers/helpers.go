package controllers

import (
    "time"

    "github.com/poofware/auth-service/internal/config"
    "github.com/poofware/go-utils"
)

type TokenPolicy struct {
	AccessTTL  time.Duration
	RefreshTTL time.Duration
}

// DecideTokenPolicy inspects the PlatformType and returns the matching
// AccessTTL / RefreshTTL from config. If IsMobile(platform) is true, it
// returns the mobile durations; otherwise it returns the web durations.
func DecideTokenPolicy(p utils.PlatformType, cfg *config.Config) TokenPolicy {
	if utils.IsMobile(p) {
		return TokenPolicy{
			AccessTTL:  cfg.MobileTokenExpiry,
			RefreshTTL: cfg.MobileRefreshTokenExpiry,
		}
	}
	return TokenPolicy{
		AccessTTL:  cfg.WebTokenExpiry,
		RefreshTTL: cfg.WebRefreshTokenExpiry,
	}
}

