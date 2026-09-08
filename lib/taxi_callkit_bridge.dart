import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';

import 'taxi_callkit_bridge_platform_interface.dart';

class TaxiCallkitBridge {
  static const MethodChannel _channel = MethodChannel('taxi_callkit_bridge');
  static const MethodChannel _iosCompatibilityChannel =
      MethodChannel('taxi_ios_voip_callkit');
  static const EventChannel _iosAgoraEventChannel =
      EventChannel('taxi_ios_agora_events');

  static Stream<Map<String, dynamic>>? _cachedIosAgoraEvents;
  static bool _androidCallPushHandlerRegistered = false;

  /// Registers the package-owned Android FCM handler without requiring the
  /// host application's main.dart to be edited.
  static Future<void> initializeAndroidCallPushHandling() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    if (_androidCallPushHandlerRegistered) {
      return;
    }

    FirebaseMessaging.onBackgroundMessage(
      taxiAndroidCallPushBackgroundHandler,
    );
    _androidCallPushHandlerRegistered = true;
  }

  static Stream<Map<String, dynamic>> get iosAgoraEvents {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return const Stream<Map<String, dynamic>>.empty();
    }

    return _cachedIosAgoraEvents ??= _iosAgoraEventChannel
        .receiveBroadcastStream()
        .where((dynamic event) => event is Map)
        .map(
          (dynamic event) => Map<String, dynamic>.from(event as Map),
        );
  }

  static Future<Map<String, dynamic>?> getInitialNativeCallAction() async {
    await initializeAndroidCallPushHandling();

    final result =
        await _channel.invokeMethod<dynamic>('getInitialNativeCallAction');

    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }

    return null;
  }

  static Future<String> getIosMicrophonePermissionStatus() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return 'notApplicable';
    }

    final status = await _iosCompatibilityChannel.invokeMethod<String>(
      'getMicrophonePermissionStatus',
    );

    return (status ?? 'unknown').trim().toLowerCase();
  }

  static Future<bool> requestIosMicrophonePermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return true;
    }

    return await _iosCompatibilityChannel.invokeMethod<bool>(
          'requestMicrophonePermission',
        ) ??
        false;
  }

  static Future<bool> configureIosVoiceAudioSession() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return true;
    }

    return await _iosCompatibilityChannel.invokeMethod<bool>(
          'configureVoiceAudioSession',
        ) ??
        false;
  }

  static Future<bool> isIosCallKitAudioActive() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }

    return await _iosCompatibilityChannel.invokeMethod<bool>(
          'isCallKitAudioActive',
        ) ??
        false;
  }

  static Future<Map<String, dynamic>> startIosAgoraVoiceCall({
    required String appId,
    required String token,
    required String channelName,
    required String userAccount,
    required String callId,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return <String, dynamic>{
        'native': false,
        'joining': false,
        'joined': false,
      };
    }

    final result = await _iosCompatibilityChannel.invokeMethod<dynamic>(
      'startIosAgoraVoiceCall',
      <String, dynamic>{
        'appId': appId,
        'token': token,
        'channelName': channelName,
        'userAccount': userAccount,
        'callId': callId,
      },
    );

    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> leaveIosAgoraVoiceCall() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return <String, dynamic>{
        'native': false,
        'joining': false,
        'joined': false,
      };
    }

    final result = await _iosCompatibilityChannel.invokeMethod<dynamic>(
      'leaveIosAgoraVoiceCall',
    );

    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  static Future<bool> setIosAgoraMicrophoneMuted(bool muted) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }

    return await _iosCompatibilityChannel.invokeMethod<bool>(
          'setIosAgoraMicrophoneMuted',
          <String, dynamic>{'muted': muted},
        ) ??
        false;
  }

  static Future<bool> setIosAgoraSpeakerEnabled(bool enabled) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }

    return await _iosCompatibilityChannel.invokeMethod<bool>(
          'setIosAgoraSpeakerEnabled',
          <String, dynamic>{'enabled': enabled},
        ) ??
        false;
  }

  static Future<bool> renewIosAgoraToken(String token) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }

    return await _iosCompatibilityChannel.invokeMethod<bool>(
          'renewIosAgoraToken',
          <String, dynamic>{'token': token},
        ) ??
        false;
  }

  static Future<Map<String, dynamic>> getIosAgoraVoiceState() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return <String, dynamic>{
        'native': false,
        'joining': false,
        'joined': false,
      };
    }

    final result = await _iosCompatibilityChannel.invokeMethod<dynamic>(
      'getIosAgoraVoiceState',
    );

    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  TaxiCallkitBridge();

  Future<String?> getPlatformVersion() {
    return TaxiCallkitBridgePlatform.instance.getPlatformVersion();
  }

  static Stream<CallEvent?> get onEvent => FlutterCallkitIncoming.onEvent;

  static String nativeIdFromCallId(String callId) {
    final clean = callId.trim().isEmpty
        ? DateTime.now().millisecondsSinceEpoch.toString()
        : callId.trim();

    int fnv32(String input, int seed) {
      int hash = 0x811c9dc5 ^ seed;
      for (final unit in input.codeUnits) {
        hash ^= unit;
        hash = (hash * 0x01000193) & 0xffffffff;
      }
      return hash;
    }

    String h8(int value) {
      return value.toRadixString(16).padLeft(8, '0').substring(0, 8);
    }

    final hex = [
      h8(fnv32(clean, 0x00000000)),
      h8(fnv32(clean, 0x12345678)),
      h8(fnv32(clean, 0x87654321)),
      h8(fnv32(clean, 0xabcdef01)),
    ].join();

    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '4${hex.substring(13, 16)}-'
        'a${hex.substring(17, 20)}-'
        '${hex.substring(20, 32)}';
  }

  static Future<void> requestCallPermissions() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        if (WidgetsBinding.instance.lifecycleState !=
            AppLifecycleState.resumed) {
          return;
        }

        final status = await getIosMicrophonePermissionStatus();
        final granted = status == 'granted' ||
            (status == 'undetermined' &&
                await requestIosMicrophonePermission());

        debugPrint(
          '[TaxiCallkitBridge] iOS microphone permission granted=$granted',
        );
      } catch (error) {
        debugPrint(
          '[TaxiCallkitBridge] iOS microphone permission failed: $error',
        );
      }

      return;
    }

    await initializeAndroidCallPushHandling();

    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        'title': 'السماح بإشعارات المكالمات',
        'rationaleMessagePermission':
            'نحتاج الإذن لعرض تنبيه المكالمة الواردة.',
        'postNotificationMessageRequired':
            'من فضلك فعّل إشعارات المكالمات من الإعدادات.',
      });
    } catch (_) {}

    try {
      final canUseFullScreen =
          await FlutterCallkitIncoming.canUseFullScreenIntent();

      if (canUseFullScreen != true) {
        await FlutterCallkitIncoming.requestFullIntentPermission();
      }
    } catch (_) {}
  }

  static Future<void> showIncomingCall({
    required String callId,
    required String callerName,
    String? channelName,
    String? callerUid,
    String? receiverUid,
    String? nativeCallId,
    int durationMs = 60000,
  }) async {
    final id = nativeCallId != null && nativeCallId.trim().isNotEmpty
        ? nativeCallId.trim()
        : nativeIdFromCallId(callId);

    final name = callerName.trim().isEmpty ? 'مكالمة واردة' : callerName.trim();

    final params = CallKitParams(
      id: id,
      nameCaller: name,
      appName: 'Taxi Madina',
      handle: name,
      type: 0,
      duration: durationMs,
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'مكالمة فائتة',
        callbackText: 'اتصال',
      ),
      callingNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'جاري الاتصال...',
        callbackText: 'إنهاء',
      ),
      extra: <String, dynamic>{
        'callId': callId,
        'channelName': channelName ?? '',
        'callerUid': callerUid ?? '',
        'receiverUid': receiverUid ?? '',
        'nativeCallId': id,
      },
      headers: const <String, dynamic>{},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#020617',
        actionColor: '#22C55E',
        textColor: '#FFFFFF',
        incomingCallNotificationChannelName: 'مكالمات تاكسي المدينة',
        missedCallNotificationChannelName: 'مكالمات فائتة',
        isShowCallID: false,
        isShowFullLockedScreen: true,
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: false,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'voiceChat',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  static Future<void> startOutgoingCall({
    required String callId,
    required String receiverName,
    String? channelName,
    String? callerUid,
    String? receiverUid,
    String? nativeCallId,
  }) async {
    final id = nativeCallId != null && nativeCallId.trim().isNotEmpty
        ? nativeCallId.trim()
        : nativeIdFromCallId(callId);

    final name =
        receiverName.trim().isEmpty ? 'جاري الاتصال' : receiverName.trim();

    final params = CallKitParams(
      id: id,
      nameCaller: name,
      appName: 'Taxi Madina',
      handle: name,
      type: 0,
      extra: <String, dynamic>{
        'callId': callId,
        'channelName': channelName ?? '',
        'callerUid': callerUid ?? '',
        'receiverUid': receiverUid ?? '',
        'nativeCallId': id,
      },
      headers: const <String, dynamic>{},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        isShowCallID: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#020617',
        actionColor: '#22C55E',
        textColor: '#FFFFFF',
        incomingCallNotificationChannelName: 'مكالمات تاكسي المدينة',
        missedCallNotificationChannelName: 'مكالمات فائتة',
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: false,
      ),
    );

    await FlutterCallkitIncoming.startCall(params);
  }

  static Future<void> setCallConnected(
    String callId, {
    String? nativeCallId,
  }) async {
    final id = nativeCallId != null && nativeCallId.trim().isNotEmpty
        ? nativeCallId.trim()
        : nativeIdFromCallId(callId);

    await FlutterCallkitIncoming.setCallConnected(id);
  }

  static Future<void> endCall(
    String callId, {
    String? nativeCallId,
    bool remoteEnded = false,
  }) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await _iosCompatibilityChannel.invokeMethod<void>(
        'endIosCall',
        <String, dynamic>{
          'callId': callId,
          'remoteEnded': remoteEnded,
        },
      );
      return;
    }

    final id = nativeCallId != null && nativeCallId.trim().isNotEmpty
        ? nativeCallId.trim()
        : nativeIdFromCallId(callId);

    await FlutterCallkitIncoming.endCall(id);
  }

  static Future<void> endAllCalls() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await _iosCompatibilityChannel.invokeMethod<void>('endAllIosCalls');
      return;
    }

    await FlutterCallkitIncoming.endAllCalls();
  }

  static Future<dynamic> activeCalls() async {
    return FlutterCallkitIncoming.activeCalls();
  }

  static Future<dynamic> getVoipToken() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return _iosCompatibilityChannel.invokeMethod<String>('getVoipToken');
    }

    return FlutterCallkitIncoming.getDevicePushTokenVoIP();
  }

  static Future<void> handleAndroidCallPushData(
    Map<String, dynamic> data, {
    DateTime? sentTime,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final type = (data['type'] ?? '').toString().trim().toLowerCase();
    final callId = (data['callId'] ?? '').toString().trim();

    if (callId.isEmpty) {
      return;
    }

    const terminalTypes = <String>{
      'agora_call_end',
      'agora_call_ended',
      'agora_call_cancel',
      'agora_call_declined',
      'agora_call_missed',
    };

    if (terminalTypes.contains(type)) {
      try {
        await endCall(callId, remoteEnded: true);
      } catch (_) {}
      return;
    }

    if (type != 'agora_call') {
      return;
    }

    if (sentTime != null &&
        DateTime.now().difference(sentTime).inSeconds > 75) {
      return;
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (currentUid.isEmpty) {
      return;
    }

    final payloadReceiverUid = (data['receiverUid'] ?? '').toString().trim();
    if (payloadReceiverUid.isNotEmpty && payloadReceiverUid != currentUid) {
      return;
    }

    final callSnapshot = await FirebaseFirestore.instance
        .collection('agoraCalls')
        .doc(callId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 8));

    if (!callSnapshot.exists) {
      return;
    }

    final callData = callSnapshot.data() ?? <String, dynamic>{};
    final status = (callData['status'] ?? '').toString().trim();
    if (status != 'ringing') {
      await endCall(callId, remoteEnded: true);
      return;
    }

    final receiverRef = callData['receiverRef'];
    final documentReceiverUid =
        (callData['receiverUid'] ?? '').toString().trim();
    final receiverMatches =
        receiverRef is DocumentReference && receiverRef.id == currentUid;
    if (!receiverMatches && documentReceiverUid != currentUid) {
      return;
    }

    final createdAt = callData['createdAt'];
    if (createdAt is Timestamp &&
        DateTime.now().difference(createdAt.toDate()).inSeconds > 75) {
      await endCall(callId, remoteEnded: true);
      return;
    }

    try {
      final calls = await activeCalls();
      if (_containsAndroidCall(calls, callId)) {
        return;
      }
    } catch (_) {}

    await showIncomingCall(
      callId: callId,
      callerName: (data['callerName'] ?? 'مكالمة واردة').toString(),
      channelName: (data['channelName'] ?? '').toString(),
      callerUid: (data['callerUid'] ?? '').toString(),
      receiverUid: currentUid,
    );
  }

  static bool _containsAndroidCall(dynamic value, String callId) {
    if (value is Map) {
      if ((value['callId'] ?? '').toString().trim() == callId) {
        return true;
      }

      final extra = value['extra'];
      if (extra is Map && (extra['callId'] ?? '').toString().trim() == callId) {
        return true;
      }

      return value.values.any(
        (dynamic nested) => _containsAndroidCall(nested, callId),
      );
    }

    if (value is Iterable) {
      return value.any(
        (dynamic item) => _containsAndroidCall(item, callId),
      );
    }

    return false;
  }
}

@pragma('vm:entry-point')
Future<void> taxiAndroidCallPushBackgroundHandler(
  RemoteMessage message,
) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return;
  }

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}

  try {
    await TaxiCallkitBridge.handleAndroidCallPushData(
      message.data,
      sentTime: message.sentTime,
    );
  } catch (error) {
    debugPrint(
      '[TaxiCallkitBridge] Android background call push failed: $error',
    );
  }
}

class CallScreenLock {
  static final CallScreenLock _instance = CallScreenLock._internal();

  factory CallScreenLock() => _instance;

  CallScreenLock._internal();

  String? _activeOpeningCallId;
  bool _isNavigatingToCall = false;

  bool shouldOpenCallScreen(String callId) {
    final normalizedCallId = callId.trim();

    if (normalizedCallId.isEmpty) {
      debugPrint('[CallScreenLock] Empty callId ignored.');
      return false;
    }

    if (_activeOpeningCallId == normalizedCallId || _isNavigatingToCall) {
      debugPrint(
        '[CallScreenLock] Duplicate call open ignored: $normalizedCallId',
      );
      return false;
    }

    _activeOpeningCallId = normalizedCallId;
    _isNavigatingToCall = true;
    return true;
  }

  void markNavigationComplete() {
    _isNavigatingToCall = false;
  }

  void releaseLockFor(String callId) {
    if (_activeOpeningCallId != callId.trim()) {
      return;
    }

    forceRelease();
  }

  void forceRelease() {
    _activeOpeningCallId = null;
    _isNavigatingToCall = false;
  }

  String? get activeCallId => _activeOpeningCallId;
}
