import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // subscription reminders (flutter_local_notifications): show them while Ghillie is open too
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GhillieSecure") {
      GhillieSecure.shared.attach(registrar.messenger())
    }
  }
}

/// lib/ui/sensitive.dart: while the 25 words are on screen ('on' ... 'off'), report screenshots and screen
/// recording / mirroring to Dart. iOS does not let apps block screenshots, so Ghillie warns instead.
final class GhillieSecure {
  static let shared = GhillieSecure()
  private var channel: FlutterMethodChannel?
  private var active = false

  func attach(_ messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "org.camocoin.ghillie/secure", binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "on": self?.active = true; self?.reportCapture(); result(nil)
      case "off": self?.active = false; result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    channel = ch
    let nc = NotificationCenter.default
    nc.addObserver(forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main) { [weak self] _ in
      guard let self, self.active else { return }
      self.channel?.invokeMethod("screenshot", arguments: nil)
    }
    nc.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
      self?.reportCapture()
    }
  }

  private func reportCapture() {
    guard active else { return }
    let captured = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .contains { $0.screen.isCaptured }
    channel?.invokeMethod("captured", arguments: captured)
  }
}
