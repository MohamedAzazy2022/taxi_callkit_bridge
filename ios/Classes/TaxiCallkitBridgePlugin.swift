import Flutter
import UIKit
import PushKit
import CallKit
import AVFoundation

public final class TaxiCallkitBridgePlugin: NSObject, FlutterPlugin {
  private enum IOSNativeOwnerMode: String {
    case auto
    case legacy
    case plugin
  }

  private static let ownerInfoPlistKey = "TaxiCallkitBridgeIosOwner"
  private static var sharedInstance: TaxiCallkitBridgePlugin?

  private let baseChannel: FlutterMethodChannel
  private var compatibilityChannel: FlutterMethodChannel?

  private let configuredOwner: IOSNativeOwnerMode
  private let legacyAppDelegateDetected: Bool
  private let pluginOwnsNativeLayer: Bool

  private init(
    baseChannel: FlutterMethodChannel,
    configuredOwner: IOSNativeOwnerMode,
    legacyAppDelegateDetected: Bool,
    pluginOwnsNativeLayer: Bool
  ) {
    self.baseChannel = baseChannel
    self.configuredOwner = configuredOwner
    self.legacyAppDelegateDetected = legacyAppDelegateDetected
    self.pluginOwnsNativeLayer = pluginOwnsNativeLayer

    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()

    let baseChannel = FlutterMethodChannel(
      name: "taxi_callkit_bridge",
      binaryMessenger: messenger
    )

    let configuredOwner = readConfiguredOwner()
    let legacyDetected = detectLegacyAppDelegateOwner()
    let ownsNativeLayer = resolveNativeOwnership(
      configuredOwner: configuredOwner,
      legacyAppDelegateDetected: legacyDetected
    )

    let instance = TaxiCallkitBridgePlugin(
      baseChannel: baseChannel,
      configuredOwner: configuredOwner,
      legacyAppDelegateDetected: legacyDetected,
      pluginOwnsNativeLayer: ownsNativeLayer
    )

    sharedInstance = instance

    registrar.addMethodCallDelegate(instance, channel: baseChannel)
    instance.registerCompatibilityChannelIfNeeded(messenger: messenger)

    NSLog(
      "[TaxiCallkitBridge] iOS owner mode=\(configuredOwner.rawValue), " +
      "legacyAppDelegateDetected=\(legacyDetected), " +
      "pluginOwnsNativeLayer=\(ownsNativeLayer), nativeLayerStarted=false"
    )
  }

  public func handle(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)

    case "getIosNativeOwnerState":
      result([
        "configuredOwner": configuredOwner.rawValue,
        "legacyAppDelegateDetected": legacyAppDelegateDetected,
        "pluginOwnsNativeLayer": pluginOwnsNativeLayer,
        "nativeLayerStarted": false
      ])

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func registerCompatibilityChannelIfNeeded(
    messenger: FlutterBinaryMessenger
  ) {
    guard pluginOwnsNativeLayer else {
      return
    }

    let channel = FlutterMethodChannel(
      name: "taxi_ios_voip_callkit",
      binaryMessenger: messenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(
          FlutterError(
            code: "bridge_unavailable",
            message: "TaxiCallkitBridgePlugin is unavailable.",
            details: nil
          )
        )
        return
      }

      self.handleCompatibilityCall(call, result: result)
    }

    compatibilityChannel = channel
  }

  private func handleCompatibilityCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    result(FlutterMethodNotImplemented)
  }

  private static func readConfiguredOwner() -> IOSNativeOwnerMode {
    guard
      let rawValue = Bundle.main.object(
        forInfoDictionaryKey: ownerInfoPlistKey
      ) as? String
    else {
      return .auto
    }

    let normalizedValue = rawValue
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()

    return IOSNativeOwnerMode(rawValue: normalizedValue) ?? .auto
  }

  private static func detectLegacyAppDelegateOwner() -> Bool {
    guard let appDelegate = UIApplication.shared.delegate else {
      return false
    }

    return
      (appDelegate is PKPushRegistryDelegate) ||
      (appDelegate is CXProviderDelegate)
  }

  private static func resolveNativeOwnership(
    configuredOwner: IOSNativeOwnerMode,
    legacyAppDelegateDetected: Bool
  ) -> Bool {
    switch configuredOwner {
    case .plugin:
      return true

    case .legacy:
      return false

    case .auto:
      return !legacyAppDelegateDetected
    }
  }
}
