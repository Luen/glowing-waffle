import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerBackupExclusion(with: engineBridge)
  }

  /// Excludes a directory from iCloud/iTunes device backups (issue #20).
  ///
  /// iOS backs up Library/Application Support, and the downloaded TTS model is
  /// ~350 MB of re-downloadable data that would otherwise count against the
  /// user's iCloud quota on every backup. There is no Dart API for
  /// NSURLIsExcludedFromBackupKey, so lib/tts/backup_exclusion.dart calls this.
  private func registerBackupExclusion(with engineBridge: FlutterImplicitEngineBridge) {
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BackupExclusion")
    else { return }
    let channel = FlutterMethodChannel(
      name: "glowing_waffle/backup",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "excludeFromBackup",
            let path = call.arguments as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      var url = URL(fileURLWithPath: path)
      do {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        result(nil)
      } catch {
        result(
          FlutterError(
            code: "exclude_failed",
            message: error.localizedDescription,
            details: path
          )
        )
      }
    }
  }
}
