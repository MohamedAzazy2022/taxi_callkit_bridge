package com.example.taxi_callkit_bridge

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class TaxiCallkitBridgePlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel: MethodChannel
  private lateinit var appContext: Context

  private val prefsName = "taxi_callkit_pending_actions"
  private val keyAction = "pending_action"
  private val keyCallId = "pending_call_id"
  private val keyChannel = "pending_channel_name"
  private val keyCallerUid = "pending_caller_uid"
  private val keyReceiverUid = "pending_receiver_uid"

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    appContext = flutterPluginBinding.applicationContext
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "taxi_callkit_bridge")
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "getPlatformVersion" -> {
        result.success("Android ${android.os.Build.VERSION.RELEASE}")
      }

      "getInitialNativeCallAction" -> {
        val prefs = appContext.getSharedPreferences(prefsName, Context.MODE_PRIVATE)

        val action = prefs.getString(keyAction, null)
        val callId = prefs.getString(keyCallId, null)

        if (action.isNullOrBlank() || callId.isNullOrBlank()) {
          result.success(null)
          return
        }

        val data = hashMapOf<String, Any?>(
          "action" to action,
          "callId" to callId,
          "channelName" to prefs.getString(keyChannel, ""),
          "callerUid" to prefs.getString(keyCallerUid, ""),
          "receiverUid" to prefs.getString(keyReceiverUid, "")
        )

        prefs.edit().clear().apply()
        result.success(data)
      }

      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
}
