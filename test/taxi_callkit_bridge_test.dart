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
  final TaxiCallkitBridgePlatform initialPlatform = TaxiCallkitBridgePlatform.instance;

  test('$MethodChannelTaxiCallkitBridge is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelTaxiCallkitBridge>());
  });

  test('getPlatformVersion', () async {
    TaxiCallkitBridge taxiCallkitBridgePlugin = TaxiCallkitBridge();
    MockTaxiCallkitBridgePlatform fakePlatform = MockTaxiCallkitBridgePlatform();
    TaxiCallkitBridgePlatform.instance = fakePlatform;

    expect(await taxiCallkitBridgePlugin.getPlatformVersion(), '42');
  });
}
