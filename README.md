# taxi_callkit_bridge

Native call bridge used by the Galal / TaxiMadina Flutter application.

## iOS native ownership

The plugin supports the `TaxiCallkitBridgeIosOwner` Info.plist key:

- `auto`: Default. The plugin starts PushKit and CallKit only when no legacy AppDelegate owner is detected.
- `legacy`: AppDelegate remains responsible for PushKit, CallKit, and the compatibility MethodChannel.
- `plugin`: The plugin owns PushKit, CallKit, and `taxi_ios_voip_callkit`.

When forcing `plugin`, legacy AppDelegate setup calls must be disabled to prevent duplicate `PKPushRegistry`, `CXProvider`, or MethodChannel registration.

With a standard FlutterFlow-generated AppDelegate and no ownership key, `auto` selects the plugin automatically.

## Compatibility channel

The iOS channel name remains:

`taxi_ios_voip_callkit`

Existing Flutter method names and event names remain compatible.
