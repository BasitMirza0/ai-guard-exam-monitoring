import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = registrar(forPlugin: "AiGuardIosConfiguration") {
      let channel = FlutterMethodChannel(
        name: "aicheat/ios_configuration", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "googleSignInConfigured" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let info = Bundle.main.infoDictionary ?? [:]
        let clientID = info["GIDClientID"] as? String ?? ""
        let urls = info["CFBundleURLTypes"] as? [[String: Any]] ?? []
        let schemes = urls.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        let reversedID = clientID.split(separator: ".").reversed().joined(separator: ".")
        result(!clientID.isEmpty && schemes.contains(reversedID))
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
