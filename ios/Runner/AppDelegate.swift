import Flutter
import QuickLook
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var platform: HaulPlatform?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HaulPlatform") {
      platform = HaulPlatform(messenger: registrar.messenger())
    }
  }
}

/// iOS side of the `haul/platform` channel: preview (play) and share files
/// that remote mode copied onto the phone.
final class HaulPlatform: NSObject, QLPreviewControllerDataSource {
  private let channel: FlutterMethodChannel
  private var previewURL: URL?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "haul/platform", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "takeInitialShare":
      result(nil)
    case "openFile":
      guard let path = args?["path"] as? String, FileManager.default.fileExists(atPath: path) else {
        result(false)
        return
      }
      result(preview(URL(fileURLWithPath: path)))
    case "shareFile":
      guard let path = args?["path"] as? String, FileManager.default.fileExists(atPath: path) else {
        result(nil)
        return
      }
      share(URL(fileURLWithPath: path))
      result(nil)
    case "openUrl":
      if let s = args?["url"] as? String, let url = URL(string: s) {
        UIApplication.shared.open(url)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private var topController: UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  /// QuickLook plays video and audio inline, with its own share button.
  private func preview(_ url: URL) -> Bool {
    guard let top = topController else { return false }
    previewURL = url
    let ql = QLPreviewController()
    ql.dataSource = self
    top.present(ql, animated: true)
    return true
  }

  /// The system share sheet: Save Video (to Photos), AirDrop, Messages…
  private func share(_ url: URL) {
    guard let top = topController else { return }
    let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    if let pop = sheet.popoverPresentationController {
      // iPad: anchor the popover to the middle of the screen.
      pop.sourceView = top.view
      pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
      pop.permittedArrowDirections = []
    }
    top.present(sheet, animated: true)
  }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
    previewURL == nil ? 0 : 1
  }

  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
    previewURL! as NSURL
  }
}
