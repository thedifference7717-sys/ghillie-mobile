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

/// lib/ui/sensitive.dart: while the 25 words are on screen ('on' ... 'off'):
///  * the app window is drawn inside the layer of a secure text field, the way iOS hides password fields from
///    screenshots and recordings, so screenshots and recordings of the words come out black;
///  * screenshots and screen recording / mirroring are still reported to Dart (warning, cover) in case a future iOS
///    changes how secure layers are captured.
final class GhillieSecure {
  static let shared = GhillieSecure()
  private var channel: FlutterMethodChannel?
  private var active = false
  private var field: UITextField?

  private var keyWindow: UIWindow? {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }.first { $0.isKeyWindow }
  }

  /// Moves the window's layer into a secure text field's layer once; afterwards only isSecureTextEntry is toggled.
  /// Returns whether the window is protected now.
  @discardableResult
  private func protect(_ on: Bool) -> Bool {
    if field == nil {
      guard on, let window = keyWindow, let host = window.layer.superlayer else { return false }
      let f = UITextField()
      f.isUserInteractionEnabled = false
      f.isSecureTextEntry = true
      window.addSubview(f)
      host.addSublayer(f.layer)
      // The secure container is the field's first sublayer before iOS 17 and its last from iOS 17 on.
      let container: CALayer?
      if #available(iOS 17.0, *) { container = f.layer.sublayers?.last } else { container = f.layer.sublayers?.first }
      guard let container else { f.removeFromSuperview(); return false }
      container.addSublayer(window.layer)
      field = f
    }
    field?.isSecureTextEntry = on
    return on
  }

  func attach(_ messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "org.camocoin.ghillie/secure", binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "on": self?.active = true; let p = self?.protect(true) ?? false; self?.reportCapture(); result(p)
      case "off": self?.active = false; self?.protect(false); result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    channel = ch
    let nc = NotificationCenter.default
    nc.addObserver(forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main) { [weak self] _ in
      guard let self, self.active else { return }
      self.channel?.invokeMethod("screenshot", arguments: self.field?.isSecureTextEntry == true)
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
