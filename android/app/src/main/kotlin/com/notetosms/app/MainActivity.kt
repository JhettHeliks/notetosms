package com.notetosms.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.annotation.NonNull
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.content.FileProvider
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

open class MainActivity : FlutterActivity() {
    private val BUBBLE_CHANNEL_PRIMARY = "com.notetosms/bubbles"
    private val BUBBLE_CHANNEL_LEGACY = "com.chatnotes/bubbles"
    private val UPDATER_CHANNEL_PRIMARY = "com.notetosms/updater"
    private val UPDATER_CHANNEL_LEGACY = "com.chatnotes/updater"
    private val NOTIFICATION_CHANNEL_ID = "notetosms_bubble_conversations"
    private val NOTIFICATION_CHANNEL_NAME = "Note Bubbles"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Bubble MethodChannel handler
        val bubbleHandler = MethodChannel.MethodCallHandler { call, result ->
            when (call.method) {
                "bubbleRoom" -> {
                    val roomId = call.argument<String>("roomId") ?: "general"
                    val roomName = call.argument<String>("roomName") ?: "Note Room"
                    val iconName = call.argument<String>("icon") ?: "chat_bubble"

                    try {
                        createBubbleNotification(roomId, roomName, iconName)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("BUBBLE_ERROR", e.localizedMessage, e.stackTraceToString())
                    }
                }
                "isBubbleSupported" -> {
                    val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
                    result.success(supported)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BUBBLE_CHANNEL_PRIMARY)
            .setMethodCallHandler(bubbleHandler)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BUBBLE_CHANNEL_LEGACY)
            .setMethodCallHandler(bubbleHandler)

        // 2. APK Updater & Installer MethodChannel handler
        val updaterHandler = MethodChannel.MethodCallHandler { call, result ->
            when (call.method) {
                "canRequestPackageInstalls" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        result.success(packageManager.canRequestPackageInstalls())
                    } else {
                        result.success(true)
                    }
                }
                "openInstallPermissionSetting" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SETTING_ERROR", e.localizedMessage, e.stackTraceToString())
                        }
                    } else {
                        result.success(true)
                    }
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrBlank()) {
                        result.error("INVALID_ARGUMENT", "File path cannot be empty", null)
                        return@MethodCallHandler
                    }

                    val file = File(filePath)
                    if (!file.exists()) {
                        result.error("FILE_NOT_FOUND", "APK file does not exist at $filePath", null)
                        return@MethodCallHandler
                    }

                    try {
                        val uri = FileProvider.getUriForFile(
                            this,
                            "${applicationContext.packageName}.fileprovider",
                            file
                        )
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INSTALL_ERROR", e.localizedMessage, e.stackTraceToString())
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATER_CHANNEL_PRIMARY)
            .setMethodCallHandler(updaterHandler)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATER_CHANNEL_LEGACY)
            .setMethodCallHandler(updaterHandler)
    }

    private fun createBubbleNotification(roomId: String, roomName: String, iconName: String) {
        createNotificationChannelIfNeeded()

        // 1. Target URI for deep linking into the specific room in BubbleChatView
        val roomUri = Uri.parse("notetosms://room/$roomId")
        val bubbleIntent = Intent(Intent.ACTION_VIEW, roomUri, this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK
        }

        val pendingIntentFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val bubblePendingIntent = PendingIntent.getActivity(
            this,
            roomId.hashCode(),
            bubbleIntent,
            pendingIntentFlag
        )

        // 2. Icon & Person for Conversation Notification
        val iconRes = applicationInfo.icon.takeIf { it != 0 } ?: android.R.drawable.ic_dialog_info
        val iconCompat = IconCompat.createWithResource(this, iconRes)

        val person = Person.Builder()
            .setName(roomName)
            .setIcon(iconCompat)
            .setKey(roomId)
            .setImportant(true)
            .setBot(false)
            .build()

        val shortcutId = "bubble_shortcut_$roomId"

        // 3. Register dynamic shortcut for Android 11+ Conversation System
        val shortcut = ShortcutInfoCompat.Builder(this, shortcutId)
            .setShortLabel(roomName)
            .setLongLabel("Open $roomName note bubble")
            .setIcon(iconCompat)
            .setIntent(bubbleIntent)
            .setPerson(person)
            .setLongLived(true)
            .build()

        ShortcutManagerCompat.pushDynamicShortcut(this, shortcut)

        // 4. Build Bubble Metadata
        val bubbleMetadata = NotificationCompat.BubbleMetadata.Builder(bubblePendingIntent, iconCompat)
            .setDesiredHeight(600)
            .setAutoExpandBubble(true)
            .setSuppressNotification(false)
            .build()

        // 5. Build and post conversation notification
        val notificationBuilder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle(roomName)
            .setContentText("Active note head. Tap to pop out or expand.")
            .setSmallIcon(iconRes)
            .setBubbleMetadata(bubbleMetadata)
            .setShortcutInfo(shortcut)
            .addPerson(person)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setContentIntent(bubblePendingIntent)
            .setStyle(
                NotificationCompat.MessagingStyle(person)
                    .setConversationTitle(roomName)
                    .addMessage(
                        NotificationCompat.MessagingStyle.Message(
                            "Floating bubble activated for #$roomName",
                            System.currentTimeMillis(),
                            person
                        )
                    )
            )
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)

        val notificationManager = NotificationManagerCompat.from(this)
        try {
            notificationManager.notify(roomId.hashCode(), notificationBuilder.build())
        } catch (e: SecurityException) {
            // Android 13+ POST_NOTIFICATIONS permission check
            e.printStackTrace()
        }
    }

    private fun createNotificationChannelIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val existingChannel = notificationManager.getNotificationChannel(NOTIFICATION_CHANNEL_ID)

            if (existingChannel == null) {
                val channel = NotificationChannel(
                    NOTIFICATION_CHANNEL_ID,
                    NOTIFICATION_CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Active conversation bubbles for note rooms"
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        setAllowBubbles(true)
                    }
                }
                notificationManager.createNotificationChannel(channel)
            }
        }
    }
}
