import Flutter
import UIKit
import PushKit
import CallKit
import AVFoundation
import AgoraRtcKit

public final class TaxiCallkitBridgePlugin: NSObject,
  FlutterPlugin,
  FlutterStreamHandler,
  CXProviderDelegate,
  PKPushRegistryDelegate,
  AgoraRtcEngineDelegate
{
  private enum IOSNativeOwnerMode: String {
    case auto
    case legacy
    case plugin
  }

  private static let ownerInfoPlistKey = "TaxiCallkitBridgeIosOwner"
  private static var sharedInstance: TaxiCallkitBridgePlugin?

  private let baseChannel: FlutterMethodChannel
  private var compatibilityChannel: FlutterMethodChannel?
  private var agoraEventChannel: FlutterEventChannel?
  private var agoraEventSink: FlutterEventSink?
  private var lastAgoraEvent: [String: Any]?

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

  private var agoraEngine: AgoraRtcEngineKit?
  private var agoraAppId: String?
  private var agoraCallId: String?
  private var agoraChannelName: String?
  private var agoraUserAccount: String?
  private var agoraJoining = false
  private var agoraJoined = false
  private var agoraRemoteUids = Set<UInt>()
  private var agoraMicrophoneMuted = false
  private var agoraSpeakerEnabled = true

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
    instance.registerAgoraEventChannel(messenger: messenger)
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

  private func registerAgoraEventChannel(
    messenger: FlutterBinaryMessenger
  ) {
    let channel = FlutterEventChannel(
      name: "taxi_ios_agora_events",
      binaryMessenger: messenger
    )

    channel.setStreamHandler(self)
    agoraEventChannel = channel
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    agoraEventSink = events

    if let event = lastAgoraEvent {
      events(event)
    }

    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    agoraEventSink = nil
    return nil
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
      result(
        configureVoiceAudioSession(
          activate: !hasCallKitCall || callKitAudioSessionActive
        )
      )

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
      leaveAgoraVoiceCall(reason: "call_ended")
      result(nil)

    case "endAllIosCalls":
      endAllCalls()
      leaveAgoraVoiceCall(reason: "all_calls_ended")
      result(nil)

    case "startIosAgoraVoiceCall":
      startAgoraVoiceCall(
        arguments: call.arguments,
        result: result
      )

    case "leaveIosAgoraVoiceCall":
      leaveAgoraVoiceCall(reason: "flutter_leave")
      result(agoraState())

    case "setIosAgoraMicrophoneMuted":
      setAgoraMicrophoneMuted(
        arguments: call.arguments,
        result: result
      )

    case "setIosAgoraSpeakerEnabled":
      setAgoraSpeakerEnabled(
        arguments: call.arguments,
        result: result
      )

    case "renewIosAgoraToken":
      renewAgoraToken(
        arguments: call.arguments,
        result: result
      )

    case "getIosAgoraVoiceState":
      result(agoraState())

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
    var options: AVAudioSession.CategoryOptions = [.allowBluetoothHFP]

    if agoraSpeakerEnabled {
      options.insert(.defaultToSpeaker)
    }

    do {
      try audioSession.setCategory(
        .playAndRecord,
        mode: .voiceChat,
        options: options
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

  private func startAgoraVoiceCall(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard pluginOwnsNativeLayer else {
      result(
        FlutterError(
          code: "ios_native_owner_disabled",
          message: "The plugin does not own the iOS native call layer.",
          details: nil
        )
      )
      return
    }

    guard let values = arguments as? [String: Any] else {
      result(invalidAgoraArguments("Arguments are required."))
      return
    }

    let appId = normalizedString(values["appId"])
    let token = normalizedString(values["token"])
    let channelName = normalizedString(values["channelName"])
    let userAccount = normalizedString(values["userAccount"])
    let callId = normalizedString(values["callId"])

    guard !appId.isEmpty else {
      result(invalidAgoraArguments("appId is required."))
      return
    }

    guard !token.isEmpty else {
      result(invalidAgoraArguments("token is required."))
      return
    }

    guard !channelName.isEmpty else {
      result(invalidAgoraArguments("channelName is required."))
      return
    }

    guard !userAccount.isEmpty else {
      result(invalidAgoraArguments("userAccount is required."))
      return
    }

    if
      (agoraJoining || agoraJoined),
      agoraCallId == callId,
      agoraChannelName == channelName,
      agoraUserAccount == userAccount
    {
      result(agoraState())
      return
    }

    if agoraJoining || agoraJoined {
      result(
        FlutterError(
          code: "ios_agora_busy",
          message: "Another iOS Agora call is already active.",
          details: agoraState()
        )
      )
      return
    }

    guard microphonePermissionStatus() == "granted" else {
      result(
        FlutterError(
          code: "microphone_permission_required",
          message: "Microphone permission is required before joining Agora.",
          details: [
            "permissionStatus": microphonePermissionStatus()
          ]
        )
      )
      return
    }

    emitAgoraEvent(
      "initializing",
      extra: [
        "callId": callId,
        "channelName": channelName
      ]
    )

    if agoraEngine != nil && agoraAppId != appId {
      AgoraRtcEngineKit.destroy()
      agoraEngine = nil
      agoraAppId = nil
    }

    let engine: AgoraRtcEngineKit

    if let currentEngine = agoraEngine {
      engine = currentEngine
      engine.delegate = self
    } else {
      engine = AgoraRtcEngineKit.sharedEngine(
        withAppId: appId,
        delegate: self
      )
      agoraEngine = engine
      agoraAppId = appId
    }

    engine.setAudioSessionOperationRestriction(.all)

    let shouldActivateAudio =
      activeCallDataByUUID.isEmpty ||
      callKitAudioSessionActive

    guard configureVoiceAudioSession(activate: shouldActivateAudio) else {
      result(
        FlutterError(
          code: "ios_audio_session_failed",
          message: "Failed to configure the iOS voice audio session.",
          details: nil
        )
      )
      return
    }

    engine.enableAudio()
    engine.disableVideo()
    engine.enableLocalAudio(true)
    engine.muteLocalAudioStream(agoraMicrophoneMuted)
    engine.setDefaultAudioRouteToSpeakerphone(agoraSpeakerEnabled)
    engine.setEnableSpeakerphone(agoraSpeakerEnabled)

    let mediaOptions = AgoraRtcChannelMediaOptions()
    mediaOptions.channelProfile = .communication
    mediaOptions.clientRoleType = .broadcaster
    mediaOptions.publishMicrophoneTrack = true
    mediaOptions.publishCameraTrack = false
    mediaOptions.autoSubscribeAudio = true
    mediaOptions.autoSubscribeVideo = false

    agoraCallId = callId
    agoraChannelName = channelName
    agoraUserAccount = userAccount
    agoraJoining = true
    agoraJoined = false
    agoraRemoteUids.removeAll()

    emitAgoraEvent("joining")

    let joinCode = engine.joinChannel(
      byToken: token,
      channelId: channelName,
      userAccount: userAccount,
      mediaOptions: mediaOptions,
      joinSuccess: nil
    )

    guard joinCode == 0 else {
      agoraJoining = false
      emitAgoraEvent(
        "error",
        extra: [
          "code": Int(joinCode),
          "operation": "joinChannel"
        ]
      )

      result(
        FlutterError(
          code: "ios_agora_join_rejected",
          message: "Agora rejected the iOS join request.",
          details: [
            "nativeCode": Int(joinCode),
            "state": agoraState()
          ]
        )
      )
      return
    }

    result(agoraState())
  }

  private func invalidAgoraArguments(_ message: String) -> FlutterError {
    return FlutterError(
      code: "invalid_ios_agora_arguments",
      message: message,
      details: nil
    )
  }

  private func normalizedString(_ value: Any?) -> String {
    guard let value = value else {
      return ""
    }

    return "\(value)".trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func setAgoraMicrophoneMuted(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard
      let values = arguments as? [String: Any],
      let muted = values["muted"] as? Bool
    else {
      result(invalidAgoraArguments("muted is required."))
      return
    }

    agoraMicrophoneMuted = muted

    guard let engine = agoraEngine else {
      result(false)
      return
    }

    let code = engine.muteLocalAudioStream(muted)
    let succeeded = code == 0

    if succeeded {
      emitAgoraEvent(
        "microphoneChanged",
        extra: ["muted": muted]
      )
    }

    result(succeeded)
  }

  private func setAgoraSpeakerEnabled(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard
      let values = arguments as? [String: Any],
      let enabled = values["enabled"] as? Bool
    else {
      result(invalidAgoraArguments("enabled is required."))
      return
    }

    let previousValue = agoraSpeakerEnabled
    agoraSpeakerEnabled = enabled

    let shouldActivateAudio =
      activeCallDataByUUID.isEmpty ||
      callKitAudioSessionActive

    guard configureVoiceAudioSession(activate: shouldActivateAudio) else {
      agoraSpeakerEnabled = previousValue
      result(false)
      return
    }

    if let engine = agoraEngine {
      engine.setDefaultAudioRouteToSpeakerphone(enabled)
      engine.setEnableSpeakerphone(enabled)
    }

    emitAgoraEvent(
      "speakerChanged",
      extra: ["enabled": enabled]
    )
    result(true)
  }

  private func renewAgoraToken(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard
      let values = arguments as? [String: Any],
      !normalizedString(values["token"]).isEmpty
    else {
      result(invalidAgoraArguments("token is required."))
      return
    }

    guard let engine = agoraEngine else {
      result(false)
      return
    }

    let code = engine.renewToken(normalizedString(values["token"]))
    result(code == 0)
  }

  private func leaveAgoraVoiceCall(reason: String) {
    let previousCallId = agoraCallId ?? ""
    let previousChannelName = agoraChannelName ?? ""

    if let engine = agoraEngine, agoraJoining || agoraJoined {
      engine.leaveChannel(nil)
    }

    agoraJoining = false
    agoraJoined = false
    agoraCallId = nil
    agoraChannelName = nil
    agoraUserAccount = nil
    agoraRemoteUids.removeAll()

    emitAgoraEvent(
      "left",
      extra: [
        "callId": previousCallId,
        "channelName": previousChannelName,
        "reason": reason
      ]
    )
  }

  private func agoraState() -> [String: Any] {
    return [
      "native": true,
      "callId": agoraCallId ?? "",
      "channelName": agoraChannelName ?? "",
      "userAccount": agoraUserAccount ?? "",
      "joining": agoraJoining,
      "joined": agoraJoined,
      "remoteUserCount": agoraRemoteUids.count,
      "microphoneMuted": agoraMicrophoneMuted,
      "speakerEnabled": agoraSpeakerEnabled,
      "callKitAudioActive": callKitAudioSessionActive
    ]
  }

  private func emitAgoraEvent(
    _ name: String,
    extra: [String: Any] = [:]
  ) {
    var event = agoraState()
    event["event"] = name
    event["timestampMs"] = Int64(Date().timeIntervalSince1970 * 1000)

    for (key, value) in extra {
      event[key] = value
    }

    lastAgoraEvent = event

    DispatchQueue.main.async { [weak self] in
      self?.agoraEventSink?(event)
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

    let callData: [String: Any] = [
      "callId": callId,
      "callerName": callerName,
      "channelName": channelName,
      "callerUid": callerUid,
      "receiverUid": receiverUid,
      "nativeCallId": uuid.uuidString
    ]

    if UIApplication.shared.applicationState == .active {
      compatibilityChannel?.invokeMethod(
        "iosIncomingCallForeground",
        arguments: callData
      )
      completion()
      return
    }

    activeCallUUIDByCallId[callId] = uuid

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
    leaveAgoraVoiceCall(reason: "callkit_reset")
  }

  public func provider(
    _ provider: CXProvider,
    didActivate audioSession: AVAudioSession
  ) {
    let configured = configureVoiceAudioSession(activate: true)
    callKitAudioSessionActive = configured

    if configured, let engine = agoraEngine {
      engine.enableAudio()
      engine.enableLocalAudio(true)
      engine.muteLocalAudioStream(agoraMicrophoneMuted)
      engine.setDefaultAudioRouteToSpeakerphone(agoraSpeakerEnabled)
      engine.setEnableSpeakerphone(agoraSpeakerEnabled)
    }

    compatibilityChannel?.invokeMethod(
      "iosAudioSessionActivated",
      arguments: [
        "active": configured,
        "source": "callkit"
      ]
    )

    emitAgoraEvent(
      "audioSessionActivated",
      extra: ["configured": configured]
    )
  }

  public func provider(
    _ provider: CXProvider,
    didDeactivate audioSession: AVAudioSession
  ) {
    callKitAudioSessionActive = false
    agoraEngine?.muteLocalAudioStream(true)

    compatibilityChannel?.invokeMethod(
      "iosAudioSessionDeactivated",
      arguments: [
        "active": false
      ]
    )

    emitAgoraEvent("audioSessionDeactivated")
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

    leaveAgoraVoiceCall(reason: "callkit_end")
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

  public func rtcEngine(
    _ engine: AgoraRtcEngineKit,
    didJoinChannel channel: String,
    withUid uid: UInt,
    elapsed: Int
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else {
        return
      }

      self.agoraJoining = false
      self.agoraJoined = true

      self.emitAgoraEvent(
        "joined",
        extra: [
          "channelName": channel,
          "localUid": Int64(uid),
          "elapsedMs": elapsed
        ]
      )
    }
  }

  public func rtcEngine(
    _ engine: AgoraRtcEngineKit,
    didJoinedOfUid uid: UInt,
    elapsed: Int
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else {
        return
      }

      self.agoraRemoteUids.insert(uid)

      self.emitAgoraEvent(
        "remoteJoined",
        extra: [
          "remoteUid": Int64(uid),
          "elapsedMs": elapsed
        ]
      )
    }
  }

  public func rtcEngine(
    _ engine: AgoraRtcEngineKit,
    didOfflineOfUid uid: UInt,
    reason: AgoraUserOfflineReason
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else {
        return
      }

      self.agoraRemoteUids.remove(uid)

      self.emitAgoraEvent(
        "remoteOffline",
        extra: [
          "remoteUid": Int64(uid),
          "reason": reason.rawValue
        ]
      )
    }
  }

  public func rtcEngine(
    _ engine: AgoraRtcEngineKit,
    didOccurError errorCode: AgoraErrorCode
  ) {
    DispatchQueue.main.async { [weak self] in
      self?.emitAgoraEvent(
        "error",
        extra: [
          "code": errorCode.rawValue,
          "operation": "agoraDelegate"
        ]
      )
    }
  }

  public func rtcEngine(
    _ engine: AgoraRtcEngineKit,
    tokenPrivilegeWillExpire token: String
  ) {
    DispatchQueue.main.async { [weak self] in
      self?.emitAgoraEvent("tokenWillExpire")
    }
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
