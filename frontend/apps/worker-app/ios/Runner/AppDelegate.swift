import UIKit
import Flutter
import GoogleMaps // <-- Add this import

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // 1) Retrieve the Google Cloud API key from Info.plist
    if let gcpKey = Bundle.main.object(forInfoDictionaryKey: "GCPApiKey") as? String,
       !gcpKey.isEmpty {
      // 2) Explicitly provide the key to GMSServices
      GMSServices.provideAPIKey(gcpKey)
    } else {
      // Fallback or warning if key is missing
      print("[Error] GCPApiKey not found or empty in Info.plist")
      fatalError("[Error] GCPApiKey not found or empty in Info.plist")
    }

    // Register Flutter plugins
    GeneratedPluginRegistrant.register(with: self)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
      // This explicitly forwards URLs to Flutter
      return super.application(app, open: url, options: options)
  }
}

