## 0.0.19

- Register the Android data-only FCM call handler from the package, so the host
  FlutterFlow application does not need a custom main.dart.
- Show and end Android native call UI from high-priority call push payloads.
- Keep every existing native iOS Agora, PushKit, CallKit, and audio API intact.
## 0.0.17

* Restore the proven iOS voice audio session lifecycle: `.playAndRecord`,
  `.voiceChat`, Bluetooth HFP, speaker routing, and explicit activation from
  `CXProviderDelegate.provider(_:didActivate:)`.
* Run Agora voice calls through the native iOS RTC SDK instead of the Flutter
  Iris bridge, while Android continues to use the host app's Flutter Agora SDK.
* Preserve the complete `taxi_ios_voip_callkit` method and event contract.
* Add idempotent native join/leave, mute, speaker, token renewal, and a dedicated
  `taxi_ios_agora_events` stream for FlutterFlow call UI state.
* Remove the ineffective Iris symbol-retainer workaround.

## 0.0.16

* Retain `Iris_InitDartApiDL` when Agora is linked as a static CocoaPods
  framework in FlutterFlow iOS Release builds.
* Make the release-link CI check validate the final binary that owns the Iris
  symbol instead of assuming a separately embedded dynamic framework.

## 0.0.15

* Verify that Agora's `Iris_InitDartApiDL` symbol survives normal iOS release
  linking with the exact Agora 6.5.4 dependency used by the host app.
* Keep Agora owned by the host app and verify it through CocoaPods because
  Agora 6.5.4 is not compatible with Flutter's SwiftPM integration.
* Avoid obsolete `AgoraRtcEngine_iOS` force-load paths; Agora 6.5.4 uses
  `AgoraRtcEngine_Special_iOS` and iris_method_channel directly retains the
  Dart API entry point.

## 0.0.14

* Make the plugin the single iOS PushKit and CallKit owner.
* Route all incoming iOS states through CallKit and deduplicate VoIP pushes.
* Keep CallKit in control of incoming-call audio activation.
* Add explicit microphone permission status and lifecycle-safe requests.
* End local calls with `CXEndCallAction` and distinguish remote endings.
* Provide one shared `CallScreenLock` for FlutterFlow actions and widgets.

## 0.0.13

* Move the iOS PushKit and CallKit implementation into the plugin.
* Preserve the `taxi_ios_voip_callkit` MethodChannel contract.
* Add safe `auto`, `legacy`, and `plugin` ownership modes.
* Keep Android call behavior unchanged.

## 0.0.1

* Initial plugin release.
