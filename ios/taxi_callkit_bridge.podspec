#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint taxi_callkit_bridge.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'taxi_callkit_bridge'
  s.version          = '0.0.15'
  s.summary          = 'A new Flutter plugin project.'
  s.description      = <<-DESC
A new Flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.frameworks = 'CallKit', 'PushKit', 'AVFoundation'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  # Agora loads Iris_InitDartApiDL dynamically. Release/App Store linking can
  # otherwise discard the object that exports it, leaving RtcEngine.initialize
  # waiting forever. Apply Agora's documented force-load fix to the host app.
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -ObjC -force_load "$(PODS_ROOT)/AgoraRtcEngine_iOS/AgoraRtcKit.xcframework/ios-arm64_armv7/AgoraRtcKit.framework/AgoraRtcKit"'
  }

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'taxi_callkit_bridge_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
