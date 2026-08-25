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

  private var nativeLayerStarted = false
  private var callKitAudioSessionActive = false
  private var lastVoipToken: String?
  private var initialVoipAction: [String: Any]?

  private var callProvider: CXProvider?
  private var activeCallUUIDByCallId: [String: UUID] = [:]
  private var activeCallDataByUUID: [UUID: [String: Any]] = [:]

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

    case "getInitialNativeCallAction":
      result(takeInitialVoipAction())

    case "getIosNativeOwnerState":
      result([
        "configuredOwner": configuredOwner.rawValue,
        "legacyAppDelegateDetected": legacyAppDelegateDetected,
        "pluginOwnsNativeLayer": pluginOwnsNativeLayer,
        "nativeLayerStarted": nativeLayerStarted
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
    switch call.method {
    case "requestMicrophonePermission":
      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        DispatchQueue.main.async {
          result(granted)
        }
      }

    case "configureVoiceAudioSession":
      result(configureVoiceAudioSession())

    case "isCallKitAudioActive":
      result(callKitAudioSessionActive)

    case "getVoipToken":
      result(lastVoipToken)

    case "getInitialVoipAction":
      result(takeInitialVoipAction())

    case "endIosCall":
      if
        let arguments = call.arguments as? [String: Any],
        let callId = arguments["callId"] as? String
      {
        endCall(callId: callId)
      }
      result(nil)

    case "endAllIosCalls":
      endAllCalls()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func takeInitialVoipAction() -> [String: Any]? {
    let action = initialVoipAction
    initialVoipAction = nil
    return action
  }

  private func configureVoiceAudioSession() -> Bool {
    let audioSession = AVAudioSession.sharedInstance()

    do {
      try audioSession.setCategory(
        .playAndRecord,
        mode: .voiceChat,
        options: [.allowBluetoothHFP, .defaultToSpeaker]
      )
      try audioSession.setActive(true)

      callKitAudioSessionActive = true

      compatibilityChannel?.invokeMethod(
        "iosAudioSessionActivated",
        arguments: [
          "active": true,
          "source": "direct"
        ]
      )

      return true
    } catch {
      NSLog(
        "[TaxiCallkitBridge] Failed to configure voice audio session: \(error)"
      )
      return false
    }
  }

  private func endCall(callId: String) {
    guard let uuid = activeCallUUIDByCallId[callId] else {
      return
    }

    callProvider?.reportCall(
      with: uuid,
      endedAt: Date(),
      reason: .remoteEnded
    )

    cleanupCall(uuid: uuid)
  }

  private func endAllCalls() {
    let uuids = Array(activeCallDataByUUID.keys)

    for uuid in uuids {
      callProvider?.reportCall(
        with: uuid,
        endedAt: Date(),
        reason: .remoteEnded
      )

      cleanupCall(uuid: uuid)
    }
  }

  private func cleanupCall(uuid: UUID) {
    if
      let data = activeCallDataByUUID[uuid],
      let callId = data["callId"] as? String
    {
      activeCallUUIDByCallId.removeValue(forKey: callId)
    }

    activeCallDataByUUID.removeValue(forKey: uuid)
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
