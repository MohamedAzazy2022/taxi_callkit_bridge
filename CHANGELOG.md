## 0.0.15

* Preserve Agora's `Iris_InitDartApiDL` symbol in iOS release builds so
  `RtcEngine.initialize()` completes in TestFlight/App Store builds.
* Verify the symbol in the plugin's release-mode iOS CI build.
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
