import Flutter
import UIKit
import CoreLocation
import NetworkExtension

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, CLLocationManagerDelegate {
  private var reportChannel: FlutterMethodChannel?
  private var appInfoChannel: FlutterMethodChannel?
  private var wifiChannel: FlutterMethodChannel?
  private lazy var wifiLocation = CLLocationManager()
  private var wifiPermissionReply: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    configureReportChannel(binaryMessenger: engineBridge.applicationRegistrar.messenger())
    configureAppInfoChannel(binaryMessenger: engineBridge.applicationRegistrar.messenger())
    configureWifiChannel(binaryMessenger: engineBridge.applicationRegistrar.messenger())
  }

  private func configureWifiChannel(binaryMessenger: FlutterBinaryMessenger) {
    wifiLocation.delegate = self
    wifiChannel = FlutterMethodChannel(name: "voltraware/wifi", binaryMessenger: binaryMessenger)
    wifiChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "current" || call.method == "requestLocation" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "Wi-Fi info unavailable", details: nil))
        return
      }
      if call.method == "requestLocation" {
        self.requestWifiLocationPermission(result)
        return
      }
      // Permission is requested only after the user taps the button.
      guard CLLocationManager.locationServicesEnabled() else {
        result(FlutterError(code: "location_off", message: "Location services disabled", details: nil))
        return
      }
      let authorization = self.wifiLocation.authorizationStatus
      guard authorization == .authorizedWhenInUse || authorization == .authorizedAlways else {
        result(FlutterError(code: "permission", message: "Location permission required", details: nil))
        return
      }
      guard self.wifiLocation.accuracyAuthorization == .fullAccuracy else {
        result(FlutterError(code: "precise_location", message: "Precise location required", details: nil))
        return
      }
      NEHotspotNetwork.fetchCurrent { network in
        // Preserve the SSID exactly. Do not read or log credentials/location.
        result(network?.ssid)
      }
    }
  }

  private func requestWifiLocationPermission(_ result: @escaping FlutterResult) {
    guard CLLocationManager.locationServicesEnabled() else {
      result(FlutterError(code: "location_off", message: "Location services disabled", details: nil))
      return
    }
    guard wifiPermissionReply == nil else {
      result(FlutterError(code: "busy", message: "Permission request pending", details: nil))
      return
    }
    wifiPermissionReply = result
    if wifiLocation.authorizationStatus == .notDetermined {
      // No location updates are requested. Authorization only permits SSID
      // access; the user can still choose manual entry without granting it.
      wifiLocation.requestWhenInUseAuthorization()
    } else {
      finishWifiLocationPermission()
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    finishWifiLocationPermission()
  }

  private func finishWifiLocationPermission() {
    guard let result = wifiPermissionReply else { return }
    let status = wifiLocation.authorizationStatus
    guard status != .notDetermined else { return }
    wifiPermissionReply = nil
    if status == .authorizedWhenInUse || status == .authorizedAlways {
      result(nil)
    } else {
      result(FlutterError(code: "permission_permanently_denied", message: "Location permission denied", details: nil))
    }
  }

  private func configureAppInfoChannel(binaryMessenger: FlutterBinaryMessenger) {
    appInfoChannel = FlutterMethodChannel(
      name: "voltraware/app_info",
      binaryMessenger: binaryMessenger
    )
    appInfoChannel?.setMethodCallHandler { call, result in
      guard call.method == "installed" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let versionName = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
        !versionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        !buildNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        result(
          FlutterError(
            code: "metadata",
            message: "Installed app version is unavailable",
            details: nil
          )
        )
        return
      }
      result(["versionName": versionName, "buildNumber": buildNumber])
    }
  }

  private func configureReportChannel(binaryMessenger: FlutterBinaryMessenger) {
    reportChannel = FlutterMethodChannel(
      name: "voltraware/report",
      binaryMessenger: binaryMessenger
    )
    reportChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "share" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let text = args["text"] as? String,
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        result(
          FlutterError(
            code: "empty",
            message: "Report is empty",
            details: nil
          )
        )
        return
      }
      self?.shareReport(text: text, result: result)
    }
  }

  private func shareReport(text: String, result: FlutterResult) {
    guard let controller = topViewController() else {
      result(
        FlutterError(
          code: "unavailable",
          message: "No view controller is available",
          details: nil
        )
      )
      return
    }
    let activity = UIActivityViewController(
      activityItems: [text],
      applicationActivities: nil
    )
    if let popover = activity.popoverPresentationController {
      popover.sourceView = controller.view
      popover.sourceRect = CGRect(
        x: controller.view.bounds.midX,
        y: controller.view.bounds.midY,
        width: 0,
        height: 0
      )
      popover.permittedArrowDirections = []
    }
    controller.present(activity, animated: true)
    result(nil)
  }

  private func topViewController() -> UIViewController? {
    let sceneWindow = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first { $0.isKeyWindow }
    var controller = sceneWindow?.rootViewController ?? window?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }
}
