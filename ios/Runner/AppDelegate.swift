import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var reportChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    configureReportChannel(binaryMessenger: engineBridge.applicationRegistrar.messenger())
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
