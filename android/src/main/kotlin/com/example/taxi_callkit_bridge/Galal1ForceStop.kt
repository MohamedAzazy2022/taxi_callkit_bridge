package com.example.taxi_callkit_bridge

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build

internal object Galal1ForceStop {
  private const val galal1Package = "com.galal.pear.admin"
  private const val prefsName = "galal1_notification_startup"
  private const val lastLaunchKey = "last_launch_ms"
  private var inspected = false
  private var stoppedAt: Long? = null

  @Synchronized
  fun windowStart(context: Context): Long? {
    if (context.packageName != galal1Package || Build.VERSION.SDK_INT < 30) return null
    if (inspected) return stoppedAt

    val manager = context.getSystemService(ActivityManager::class.java)
    val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
    val lastLaunch = prefs.getLong(lastLaunchKey, 0L)
    val now = System.currentTimeMillis()
    val exit = manager.getHistoricalProcessExitReasons(galal1Package, 0, 1).firstOrNull()
    val explicitStop = exit != null &&
      exit.reason == ApplicationExitInfo.REASON_USER_REQUESTED &&
      exit.description?.startsWith("stop $galal1Package due to from pid ") == true

    stoppedAt = if (Build.VERSION.SDK_INT >= 35) {
      if (manager.getHistoricalProcessStartReasons(1).firstOrNull()?.wasForceStopped() == true) {
        when {
          explicitStop && exit!!.timestamp >= lastLaunch -> exit.timestamp
          exit != null && exit.timestamp >= lastLaunch -> exit.timestamp
          lastLaunch > 0L -> lastLaunch
          else -> null
        }
      } else null
    } else if (explicitStop && exit!!.timestamp >= lastLaunch) {
      exit.timestamp
    } else null
    if (stoppedAt != null && stoppedAt!! > now) stoppedAt = null
    prefs.edit().putLong(lastLaunchKey, now).apply()
    inspected = true
    return stoppedAt
  }
}
