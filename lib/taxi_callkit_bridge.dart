import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';

class TaxiCallkitBridge {
  TaxiCallkitBridge();

  Future<String?> getPlatformVersion() async {
    return 'Taxi CallKit Bridge';
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

    final name = callerName.trim().isEmpty
        ? 'مكالمة واردة'
        : callerName.trim();

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

    final name = receiverName.trim().isEmpty
        ? 'جاري الاتصال'
        : receiverName.trim();

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
  }) async {
    final id = nativeCallId != null && nativeCallId.trim().isNotEmpty
        ? nativeCallId.trim()
        : nativeIdFromCallId(callId);

    await FlutterCallkitIncoming.endCall(id);
  }

  static Future<void> endAllCalls() async {
    await FlutterCallkitIncoming.endAllCalls();
  }

  static Future<dynamic> activeCalls() async {
    return FlutterCallkitIncoming.activeCalls();
  }

  static Future<dynamic> getVoipToken() async {
    return FlutterCallkitIncoming.getDevicePushTokenVoIP();
  }
}
