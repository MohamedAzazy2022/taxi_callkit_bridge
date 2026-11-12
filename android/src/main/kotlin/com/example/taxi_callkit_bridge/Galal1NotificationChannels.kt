package com.example.taxi_callkit_bridge

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build

/** Channels for Galal 1 only. The original Galal application's channels are untouched. */
internal object Galal1NotificationChannels {
  private const val applicationId = "com.galal.pear.admin"

  private val names = linkedMapOf(
    "order_new" to "استقبال أوردر جديد",
    "order_pending" to "إعادة تعليق الأوردر",
    "order_cancel" to "إلغاء الأوردر",
    "chat_message" to "رسائل المحادثات",
    "admin_chat" to "رسائل الإدارة",
    "regional_order" to "أوردرات المحافظات",
    "payment" to "إشعارات الدفع",
    "general" to "الإشعارات العامة",
    "original_extra" to "الإشعارات الصوتية الإضافية",
  )

  fun register(context: Context): Int {
    if (context.packageName != applicationId || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return 0
    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    val attributes = AudioAttributes.Builder()
      .setUsage(AudioAttributes.USAGE_NOTIFICATION)
      .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
      .build()

    for ((key, label) in names) {
      val id = "galal1_${key}_v1"
      // Existing channels may contain the user's sound, volume or mute preference.
      if (manager.getNotificationChannel(id) != null) continue
      val resource = "galal1_$key"
      check(context.resources.getIdentifier(resource, "raw", applicationId) != 0) {
        "Missing notification sound resource: $resource"
      }
      val channel = NotificationChannel(id, label, NotificationManager.IMPORTANCE_HIGH)
      channel.description = "صوت جلال 1 الأصلي — $label"
      // Use a stable resource name instead of an integer ID, which can change on upgrades.
      channel.setSound(Uri.parse("android.resource://$applicationId/raw/$resource"), attributes)
      channel.enableVibration(true)
      channel.setShowBadge(true)
      manager.createNotificationChannel(channel)
    }
    if (manager.getNotificationChannel("galal1_silent_v1") == null) {
      val silent = NotificationChannel("galal1_silent_v1", "إشعارات بدون صوت", NotificationManager.IMPORTANCE_HIGH)
      silent.setSound(null, null)
      silent.enableVibration(false)
      manager.createNotificationChannel(silent)
    }
    return names.size
  }
}
