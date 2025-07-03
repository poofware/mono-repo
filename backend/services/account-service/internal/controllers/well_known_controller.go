package controllers

import (
	"encoding/json"
	"net/http"

	"github.com/poofware/go-utils"
)

// AppleAppSiteAssociation represents the JSON structure returned by the iOS universal link handler.
type AppleAppSiteAssociation struct {
	Applinks struct {
		Apps    []string `json:"apps"`
		Details []struct {
			AppID string   `json:"appID"`
			Paths []string `json:"paths"`
		} `json:"details"`
	} `json:"applinks"`
}

// AssetLink represents the JSON structure for an Android asset link target.
type AssetLink struct {
	Relation []string `json:"relation"`
	Target   struct {
		Namespace                string   `json:"namespace"`
		PackageName              string   `json:"package_name"`
		Sha256CertFingerprints   []string `json:"sha256_cert_fingerprints"`
	} `json:"target"`
}

// WellKnownController serves iOS and Android app-link metadata files:
//   - /.well-known/apple-app-site-association
//   - /.well-known/assetlinks.json
type WellKnownController struct{}

func NewWellKnownController() *WellKnownController {
	return &WellKnownController{}
}

// AppleAppSiteAssociationHandler -> GET /.well-known/apple-app-site-association
func (c *WellKnownController) AppleAppSiteAssociationHandler(w http.ResponseWriter, r *http.Request) {
	utils.Logger.Debug("apple-app-site-association requested")

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)

	// Build the iOS universal link structure
	data := AppleAppSiteAssociation{}
	data.Applinks.Apps = []string{}
	data.Applinks.Details = []struct {
		AppID string   `json:"appID"`
		Paths []string `json:"paths"`
	}{
		{
			AppID: utils.AppleTeamID + "." + utils.AppleAppID,
			Paths: []string{"/" + utils.AppleAppName + "/*"},
		},
	}

	_ = json.NewEncoder(w).Encode(data)
}

// AssetLinksHandler -> GET /.well-known/assetlinks.json
func (c *WellKnownController) AssetLinksHandler(w http.ResponseWriter, r *http.Request) {
	utils.Logger.Debug("assetlinks.json requested")

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)

	// Build the Android App Links structure
	assetLinks := []AssetLink{
		{
			Relation: []string{"delegate_permission/common.handle_all_urls"},
			Target: struct {
				Namespace              string   `json:"namespace"`
				PackageName            string   `json:"package_name"`
				Sha256CertFingerprints []string `json:"sha256_cert_fingerprints"`
			}{
				Namespace:              "android_app",
				PackageName:            utils.AndroidAppPackageName,
				Sha256CertFingerprints: []string{AndroidSHA256CertLocalDebug, AndroidSHA256CertLocalRelease, AndroidSHA256CertPlay},
			},
		},
	}

	_ = json.NewEncoder(w).Encode(assetLinks)
}

