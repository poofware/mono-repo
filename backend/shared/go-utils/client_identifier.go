package utils

import (
    "net"
    "net/http"
    "strings"
)

// ClientIdentifier holds a typed value that can either be an IP address or a device ID.
type ClientIdentifier struct {
    Type  ClientIDType
    Value string
}

// GetClientPlatform reads the "X-Platform" header and returns an enum.
// Defaults to "web" if empty or invalid.
func GetClientPlatform(r *http.Request) PlatformType {
	raw := r.Header.Get("X-Platform")
	if raw == "" {
		raw = "web"
	}
	raw = strings.ToLower(raw)

	if p, err := ParsePlatform(raw); err == nil {
		return p
	}
	return PlatformWeb
}

// GetClientIdentifier returns either IP (web) or Device-ID (android/ios).
func GetClientIdentifier(r *http.Request, platform PlatformType) ClientIdentifier {
    if IsMobile(platform) {
		deviceID := r.Header.Get("X-Device-ID")
		return ClientIdentifier{Type: ClientIDTypeDeviceID, Value: deviceID}
	}
	// Otherwise use IP
	ip := detectIP(r)
	return ClientIdentifier{Type: ClientIDTypeIP, Value: ip}
}

// detectIP extracts the best IP address from typical headers or RemoteAddr.
func detectIP(r *http.Request) string {
    forwardedFor := r.Header.Get("X-Forwarded-For")
    if forwardedFor != "" {
        ips := strings.Split(forwardedFor, ",")
        for _, ip := range ips {
            cleanIP := strings.TrimSpace(ip)
            if isValidIP(cleanIP) {
                return cleanIP
            }
        }
    }

    cfConnectingIP := r.Header.Get("CF-Connecting-IP")
    if cfConnectingIP != "" && isValidIP(cfConnectingIP) {
        return cfConnectingIP
    }

    realIP := r.Header.Get("X-Real-IP")
    if realIP != "" && isValidIP(realIP) {
        return realIP
    }

    forwarded := r.Header.Get("Forwarded")
    if forwarded != "" {
        parts := strings.Split(forwarded, ";")
        for _, part := range parts {
            part = strings.TrimSpace(part)
            if strings.HasPrefix(part, "for=") {
                maybeIP := strings.TrimPrefix(part, "for=")
                maybeIP = strings.Trim(maybeIP, "\"")
                if isValidIP(maybeIP) {
                    return maybeIP
                }
            }
        }
    }

    ip, _, err := net.SplitHostPort(r.RemoteAddr)
    if err == nil && isValidIP(ip) {
        return ip
    }
    return ""
}

func isValidIP(ip string) bool {
    return net.ParseIP(ip) != nil
}

