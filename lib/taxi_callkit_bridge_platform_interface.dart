import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'taxi_callkit_bridge_method_channel.dart';

abstract class TaxiCallkitBridgePlatform extends PlatformInterface {
  /// Constructs a TaxiCallkitBridgePlatform.
  TaxiCallkitBridgePlatform() : super(token: _token);

  static final Object _token = Object();

  static TaxiCallkitBridgePlatform _instance = MethodChannelTaxiCallkitBridge();

  /// The default instance of [TaxiCallkitBridgePlatform] to use.
  ///
  /// Defaults to [MethodChannelTaxiCallkitBridge].
  static TaxiCallkitBridgePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [TaxiCallkitBridgePlatform] when
  /// they register themselves.
  static set instance(TaxiCallkitBridgePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
