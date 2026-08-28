import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_callkit_bridge/taxi_callkit_bridge.dart';
import 'package:taxi_callkit_bridge/taxi_callkit_bridge_platform_interface.dart';
import 'package:taxi_callkit_bridge/taxi_callkit_bridge_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockTaxiCallkitBridgePlatform
    with MockPlatformInterfaceMixin
    implements TaxiCallkitBridgePlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final TaxiCallkitBridgePlatform initialPlatform =
      TaxiCallkitBridgePlatform.instance;

  test('$MethodChannelTaxiCallkitBridge is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelTaxiCallkitBridge>());
  });

  test('getPlatformVersion', () async {
    TaxiCallkitBridge taxiCallkitBridgePlugin = TaxiCallkitBridge();
    MockTaxiCallkitBridgePlatform fakePlatform =
        MockTaxiCallkitBridgePlatform();
    TaxiCallkitBridgePlatform.instance = fakePlatform;

    expect(await taxiCallkitBridgePlugin.getPlatformVersion(), '42');
  });

  test('CallScreenLock is shared and releases the active call', () {
    final firstReference = CallScreenLock();
    final secondReference = CallScreenLock();

    firstReference.forceRelease();

    expect(firstReference.shouldOpenCallScreen('call-1'), isTrue);
    expect(secondReference.shouldOpenCallScreen('call-1'), isFalse);
    expect(secondReference.activeCallId, 'call-1');

    secondReference.releaseLockFor('call-1');

    expect(firstReference.activeCallId, isNull);
    expect(firstReference.shouldOpenCallScreen('call-2'), isTrue);

    firstReference.forceRelease();
  });

  test('native iOS Agora methods keep the FlutterFlow bridge contract',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    final calls = <MethodCall>[];
    const channel = MethodChannel('taxi_ios_voip_callkit');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);

      if (call.method == 'startIosAgoraVoiceCall') {
        return <String, dynamic>{
          'native': true,
          'joining': true,
          'joined': false,
        };
      }

      if (call.method == 'getIosAgoraVoiceState' ||
          call.method == 'leaveIosAgoraVoiceCall') {
        return <String, dynamic>{
          'native': true,
          'joining': false,
          'joined': false,
        };
      }

      return true;
    });

    final startState = await TaxiCallkitBridge.startIosAgoraVoiceCall(
      appId: 'app-id',
      token: 'token',
      channelName: 'channel',
      userAccount: 'user-account',
      callId: 'call-id',
    );

    expect(startState['native'], isTrue);
    expect(startState['joining'], isTrue);
    expect(calls.first.method, 'startIosAgoraVoiceCall');
    expect(
      Map<String, dynamic>.from(calls.first.arguments as Map),
      <String, dynamic>{
        'appId': 'app-id',
        'token': 'token',
        'channelName': 'channel',
        'userAccount': 'user-account',
        'callId': 'call-id',
      },
    );

    expect(await TaxiCallkitBridge.setIosAgoraMicrophoneMuted(true), isTrue);
    expect(await TaxiCallkitBridge.setIosAgoraSpeakerEnabled(false), isTrue);
    expect(await TaxiCallkitBridge.renewIosAgoraToken('new-token'), isTrue);
    expect(
      (await TaxiCallkitBridge.getIosAgoraVoiceState())['native'],
      isTrue,
    );
    expect(
      (await TaxiCallkitBridge.leaveIosAgoraVoiceCall())['joined'],
      isFalse,
    );

    expect(
      calls.map((call) => call.method),
      containsAllInOrder(<String>[
        'startIosAgoraVoiceCall',
        'setIosAgoraMicrophoneMuted',
        'setIosAgoraSpeakerEnabled',
        'renewIosAgoraToken',
        'getIosAgoraVoiceState',
        'leaveIosAgoraVoiceCall',
      ]),
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });
}
