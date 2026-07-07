import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_callkit_bridge/taxi_callkit_bridge_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelTaxiCallkitBridge platform = MethodChannelTaxiCallkitBridge();
  const MethodChannel channel = MethodChannel('taxi_callkit_bridge');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        return '42';
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });
}
