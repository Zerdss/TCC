import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Brilho do usuário antes do modo noite (para restaurar depois).
  private var savedBrightness: CGFloat?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Tela sempre ligada com o app aberto (de novo a cada vez que ele volta à frente).
    application.isIdleTimerDisabled = true
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { _ in UIApplication.shared.isIdleTimerDisabled = true }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Modo noite: brilho da tela como luz de apoio para a câmera frontal.
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FatigueGuardScreen") else { return }
    let channel = FlutterMethodChannel(name: "fatigue_guard/screen", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
      case "getBrightness":
        result(Double(UIScreen.main.brightness))
      case "setBrightness":
        let v = (call.arguments as? NSNumber)?.doubleValue ?? -1
        if v < 0 {
          if let saved = self.savedBrightness {
            UIScreen.main.brightness = saved
            self.savedBrightness = nil
          }
        } else {
          if self.savedBrightness == nil { self.savedBrightness = UIScreen.main.brightness }
          UIScreen.main.brightness = CGFloat(min(max(v, 0.0), 1.0))
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
