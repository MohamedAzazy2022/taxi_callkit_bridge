import Flutter
import UIKit
import PushKit
import CallKit
import AVFoundation

public final class TaxiCallkitBridgePlugin: NSObject, FlutterPlugin, CXProviderDelegate, PKPushRegistryDelegate {
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

  private var voipRegistry: PKPushRegistry?
  private var callProvider: CXProvider?
  private let callController = CXCallController()
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
    instance.startNativeLayerIfNeeded()

    NSLog(
      "[TaxiCallkitBridge] iOS owner mode=\(configuredOwner.rawValue), " +
      "legacyAppDelegateDetected=\(legacyDetected), " +
      "pluginOwnsNativeLayer=\(ownsNativeLayer), " +
      "nativeLayerStarted=\(instance.nativeLayerStarted)"
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

  private func startNativeLayerIfNeeded() {
    guard pluginOwnsNativeLayer else {
      nativeLayerStarted = false

      NSLog(
        "[TaxiCallkitBridge] Native iOS layer remains owned by AppDelegate."
      )

      return
    }

    setupCallKit()
    setupPushKit()

    nativeLayerStarted =
      callProvider != nil &&
      voipRegistry != nil

    if nativeLayerStarted {
      NSLog(
        "[TaxiCallkitBridge] Native iOS PushKit and CallKit layer started."
      )
    } else {
      NSLog(
        "[TaxiCallkitBridge] Native iOS layer failed to start completely."
      )
    }
  }

  private func handleCompatibilityCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "getMicrophonePermissionStatus":
      result(microphonePermissionStatus())

    case "requestMicrophonePermission":
      requestMicrophonePermission(result: result)

    case "configureVoiceAudioSession":
      let hasCallKitCall = !activeCallDataByUUID.isEmpty
      result(configureVoiceAudioSession(activate: !hasCallKitCall))

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
        let remoteEnded = arguments["remoteEnded"] as? Bool ?? false
        endCall(callId: callId, remoteEnded: remoteEnded)
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

  private func microphonePermissionStatus() -> String {
    switch AVAudioSession.sharedInstance().recordPermission {
    case .granted:
      return "granted"

    case .denied:
      return "denied"

    case .undetermined:
      return "undetermined"

    @unknown default:
      return "unknown"
    }
  }

  private func requestMicrophonePermission(
    result: @escaping FlutterResult
  ) {
    let audioSession = AVAudioSession.sharedInstance()

    switch audioSession.recordPermission {
    case .granted:
      result(true)

    case .denied:
      result(false)

    case .undetermined:
      guard UIApplication.shared.applicationState == .active else {
        result(false)
        return
      }

      audioSession.requestRecordPermission { granted in
        DispatchQueue.main.async {
          result(granted)
        }
      }

    @unknown default:
      result(false)
    }
  }

  private func configureVoiceAudioSession(activate: Bool) -> Bool {
    let audioSession = AVAudioSession.sharedInstance()

    do {
      try audioSession.setCategory(
        .playAndRecord,
        mode: .voiceChat,
        options: [.allowBluetoothHFP, .defaultToSpeaker]
      )
      if activate {
        try audioSession.setActive(true)
      }

      return true
    } catch {
      NSLog(
        "[TaxiCallkitBridge] Failed to configure voice audio session: \(error)"
      )
      return false
    }
  }

  private func setupPushKit() {
    guard voipRegistry == nil else {
      return
    }

    let registry = PKPushRegistry(queue: DispatchQueue.main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry
  }

  public func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate pushCredentials: PKPushCredentials,
    for type: PKPushType
  ) {
    guard type == .voIP else {
      return
    }

    let token = pushCredentials.token
      .map { String(format: "%02x", $0) }
      .joined()

    lastVoipToken = token

    compatibilityChannel?.invokeMethod(
      "voipTokenUpdated",
      arguments: [
        "token": token
      ]
    )
  }

  public func pushRegistry(
    _ registry: PKPushRegistry,
    didInvalidatePushTokenFor type: PKPushType
  ) {
    guard type == .voIP else {
      return
    }

    lastVoipToken = nil

    compatibilityChannel?.invokeMethod(
      "voipTokenInvalidated",
      arguments: nil
    )
  }

  public func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }

    let payloadDictionary = payload.dictionaryPayload

    let requestedCallId = payloadString(
      payloadDictionary,
      key: "callId"
    )

    let callId = requestedCallId.isEmpty
      ? UUID().uuidString
      : requestedCallId

    let requestedCallerName = payloadString(
      payloadDictionary,
      key: "callerName"
    )

    let callerName = requestedCallerName.isEmpty
      ? "مكالمة واردة"
      : requestedCallerName

    let channelName = payloadString(
      payloadDictionary,
      key: "channelName"
    )

    let callerUid = payloadString(
      payloadDictionary,
      key: "callerUid"
    )

    let receiverUid = payloadString(
      payloadDictionary,
      key: "receiverUid"
    )

    let reusedExistingCall = activeCallUUIDByCallId[callId] != nil
    let uuid = activeCallUUIDByCallId[callId] ?? UUID()

    activeCallUUIDByCallId[callId] = uuid

    let callData: [String: Any] = [
      "callId": callId,
      "callerName": callerName,
      "channelName": channelName,
      "callerUid": callerUid,
      "receiverUid": receiverUid,
      "nativeCallId": uuid.uuidString
    ]

    activeCallDataByUUID[uuid] = callData

    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(
      type: .generic,
      value: callerName
    )
    update.localizedCallerName = callerName
    update.hasVideo = false

    guard let provider = callProvider else {
      cleanupCall(uuid: uuid)

      NSLog(
        "[TaxiCallkitBridge] Incoming VoIP push received without CXProvider."
      )

      completion()
      return
    }

    provider.reportNewIncomingCall(
      with: uuid,
      update: update
    ) { [weak self] error in
      if let error = error {
        if !reusedExistingCall {
          self?.cleanupCall(uuid: uuid)
        }

        NSLog(
          "[TaxiCallkitBridge] Failed to report incoming call: \(error)"
        )
      } else {
        self?.compatibilityChannel?.invokeMethod(
          "iosIncomingCallShown",
          arguments: callData
        )
      }

      completion()
    }
  }

  private func payloadString(
    _ payload: [AnyHashable: Any],
    key: String
  ) -> String {
    if let value = payload[key] {
      return "\(value)"
    }

    if
      let data = payload["data"] as? [String: Any],
      let value = data[key]
    {
      return "\(value)"
    }

    if
      let data = payload["data"] as? [AnyHashable: Any],
      let value = data[key]
    {
      return "\(value)"
    }

    if
      let aps = payload["aps"] as? [String: Any],
      let value = aps[key]
    {
      return "\(value)"
    }

    if
      let aps = payload["aps"] as? [AnyHashable: Any],
      let value = aps[key]
    {
      return "\(value)"
    }

    return ""
  }

  private func setupCallKit() {
    guard callProvider == nil else {
      return
    }

    let configuration = CXProviderConfiguration(localizedName: "Galal")
    configuration.supportsVideo = false
    configuration.maximumCallGroups = 1
    configuration.maximumCallsPerCallGroup = 1
    configuration.supportedHandleTypes = [.generic]
    configuration.includesCallsInRecents = false

    let provider = CXProvider(configuration: configuration)
    provider.setDelegate(self, queue: nil)
    callProvider = provider
  }

  public func providerDidReset(_ provider: CXProvider) {
    callKitAudioSessionActive = false
    activeCallUUIDByCallId.removeAll()
    activeCallDataByUUID.removeAll()
  }

  public func provider(
    _ provider: CXProvider,
    didActivate audioSession: AVAudioSession
  ) {
    callKitAudioSessionActive = true

    compatibilityChannel?.invokeMethod(
      "iosAudioSessionActivated",
      arguments: [
        "active": true,
        "source": "callkit"
      ]
    )
  }

  public func provider(
    _ provider: CXProvider,
    didDeactivate audioSession: AVAudioSession
  ) {
    callKitAudioSessionActive = false

    compatibilityChannel?.invokeMethod(
      "iosAudioSessionDeactivated",
      arguments: [
        "active": false
      ]
    )
  }

  public func provider(
    _ provider: CXProvider,
    perform action: CXAnswerCallAction
  ) {
    let uuid = action.callUUID

    let callData = activeCallDataByUUID[uuid] ?? [
      "nativeCallId": uuid.uuidString
    ]

    var data = callData
    data["action"] = "accept"

    guard configureVoiceAudioSession(activate: false) else {
      action.fail()
      return
    }

    initialVoipAction = data

    compatibilityChannel?.invokeMethod(
      "iosCallAccepted",
      arguments: data
    )

    action.fulfill()
  }

  public func provider(
    _ provider: CXProvider,
    perform action: CXEndCallAction
  ) {
    let uuid = action.callUUID

    let callData = activeCallDataByUUID[uuid] ?? [
      "nativeCallId": uuid.uuidString
    ]

    var data = callData
    data["action"] = "ended"

    initialVoipAction = data

    compatibilityChannel?.invokeMethod(
      "iosCallEnded",
      arguments: data
    )

    cleanupCall(uuid: uuid)
    action.fulfill()
  }

  private func endCall(
    callId: String,
    remoteEnded: Bool = false
  ) {
    guard let uuid = activeCallUUIDByCallId[callId] else {
      return
    }

    if remoteEnded {
      callProvider?.reportCall(
        with: uuid,
        endedAt: Date(),
        reason: .remoteEnded
      )

      cleanupCall(uuid: uuid)
      return
    }

    let endAction = CXEndCallAction(call: uuid)
    let transaction = CXTransaction(action: endAction)

    callController.request(transaction) { [weak self] error in
      guard error != nil else {
        return
      }

      DispatchQueue.main.async {
        self?.callProvider?.reportCall(
          with: uuid,
          endedAt: Date(),
          reason: .failed
        )
        self?.cleanupCall(uuid: uuid)
      }
    }
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
