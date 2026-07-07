import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'taxi_callkit_bridge_platform_interface.dart';

/// An implementation of [TaxiCallkitBridgePlatform] that uses method channels.
class MethodChannelTaxiCallkitBridge extends TaxiCallkitBridgePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('taxi_callkit_bridge');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
