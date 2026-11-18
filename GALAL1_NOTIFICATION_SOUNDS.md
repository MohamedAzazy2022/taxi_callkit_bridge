# Galal 1 notification sounds

The Android plugin registers versioned `galal1_*_v1` notification channels only
when the host package is `com.galal.pear.admin`. Existing channels and their
user-selected settings are left unchanged. Other application packages return
without registering channels.

The original MP3 recordings are bundled in `android/src/main/res/raw` under
stable names. `galal1_sounds_keep.xml` retains them in release builds. The FCM
sender must specify the matching channel ID and raw sound name; Flutter asset
paths cannot select Android system notification sounds.

| Event | Channel | Raw resource |
| --- | --- | --- |
| New order | `galal1_order_new_v1` | `galal1_order_new` |
| Pending order | `galal1_order_pending_v1` | `galal1_order_pending` |
| Cancelled order | `galal1_order_cancel_v1` | `galal1_order_cancel` |
| Private/group message | `galal1_chat_message_v1` | `galal1_chat_message` |
| Admin chat recording | `galal1_admin_chat_v1` | `galal1_admin_chat` |
| Regional order | `galal1_regional_order_v1` | `galal1_regional_order` |
| Payment | `galal1_payment_v1` | `galal1_payment` |
| General notification | `galal1_general_v1` | `galal1_general` |
| Additional original recording | `galal1_original_extra_v1` | `galal1_original_extra` |
| Muted group | `galal1_silent_v1` | No sound or vibration |

This change does not modify the CallKit fork, call handling, iOS behavior or the
dependency revision used by the original Galal project.

## adminAlex double alert (sound capability v2)

`galal1_alex_order_loud_v2` uses `raw/galal1_alex_order_loud.wav`.
The PCM recording contains two identical alert motifs with a short pause,
so one OS notification plays both alerts without duplicate pushes.
The channel has HIGH importance and notification audio usage. Existing v1
channels and user sound preferences are preserved. The method
`getGalal1NotificationSoundVersion` returns 2 only in builds with this resource.
The server selects it only for new regional orders addressed to Alex office
accounts with sound enabled and capability 2.
