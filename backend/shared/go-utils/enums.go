package utils

import "fmt"

// ------------------------------------------------------------------------
// PlatformType enumerates how the client is connecting.
// ------------------------------------------------------------------------
type PlatformType int

const (
	PlatformWeb PlatformType = iota
	PlatformAndroid
	PlatformIOS
)

func (p PlatformType) String() string {
	switch p {
	case PlatformWeb:
		return "web"
	case PlatformAndroid:
		return "android"
	case PlatformIOS:
		return "ios"
	default:
		return "unknown"
	}
}

// ParsePlatform converts strings ("web", "android", "ios") to the enum.
func ParsePlatform(s string) (PlatformType, error) {
	switch s {
	case "web":
		return PlatformWeb, nil
	case "android":
		return PlatformAndroid, nil
	case "ios":
		return PlatformIOS, nil
	default:
		return -1, fmt.Errorf("invalid platform: %q", s)
	}
}

// isMobile returns true if the platform is Android or iOS.
func IsMobile(platform PlatformType) bool {
	return platform == PlatformAndroid || platform == PlatformIOS
}


// ------------------------------------------------------------------------
// Client-identifier types (unchanged).
// ------------------------------------------------------------------------
type ClientIDType int

const (
	ClientIDTypeIP ClientIDType = iota
	ClientIDTypeDeviceID
)

func (c ClientIDType) String() string {
	switch c {
	case ClientIDTypeIP:
		return "IP"
	case ClientIDTypeDeviceID:
		return "DEVICE_ID"
	default:
		return "UNKNOWN"
	}
}

