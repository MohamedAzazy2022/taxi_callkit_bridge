
import 'taxi_callkit_bridge_platform_interface.dart';

class TaxiCallkitBridge {
  Future<String?> getPlatformVersion() {
    return TaxiCallkitBridgePlatform.instance.getPlatformVersion();
  }
}
