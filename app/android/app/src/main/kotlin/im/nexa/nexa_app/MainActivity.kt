package im.nexa.nexa_app

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.content.Context
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.util.Base64
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.nexa.media_picker"
    private val REQUEST_IMAGE_CAPTURE = 1001
    private val REQUEST_GALLERY_PICK = 1002
    private val REQUEST_DOCUMENT_PICK = 1003
    private val REQUEST_PERMISSION_CODE = 2001

    private var pendingResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    // Native Audio Recording and Playback
    private var mediaRecorder: MediaRecorder? = null
    private var currentRecordingFile: File? = null
    private var recordingStartTime: Long = 0L
    private var mediaPlayer: MediaPlayer? = null

    // Real-Time Native Full-Duplex VoIP Call Audio Engine
    private var voipRecordThread: Thread? = null
    private var voipPlayThread: Thread? = null
    private var isVoipRunning = false
    private var isVoipMuted = false
    private var voipSocket: DatagramSocket? = null
    private val NOTIFICATION_CHANNEL_ID = "nexa_chat_messages"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkNativePermission" -> {
                    val permissionType = call.argument<String>("permission") ?: "camera"
                    val permissions = getPermissionsForType(permissionType)
                    if (permissions.isEmpty()) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    val allGranted = permissions.all { perm ->
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            checkSelfPermission(perm) == PackageManager.PERMISSION_GRANTED
                        } else {
                            true
                        }
                    }
                    result.success(allGranted)
                }
                "requestNativePermission" -> {
                    val permissionType = call.argument<String>("permission") ?: "camera"
                    val permissions = getPermissionsForType(permissionType)
                    if (permissions.isEmpty()) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    val allGranted = permissions.all { perm ->
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            checkSelfPermission(perm) == PackageManager.PERMISSION_GRANTED
                        } else {
                            true
                        }
                    }
                    if (allGranted) {
                        result.success(true)
                    } else {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            pendingPermissionResult = result
                            requestPermissions(permissions.toTypedArray(), REQUEST_PERMISSION_CODE)
                        } else {
                            result.success(true)
                        }
                    }
                }
                "openAppSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.fromParts("package", packageName, null)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "openUrlInBrowser" -> {
                    try {
                        val url = call.argument<String>("url") ?: "https://glimmer-messaging-app-web.vercel.app/"
                        val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                        startActivity(browserIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "getAppCacheDir" -> {
                    try {
                        result.success(applicationContext.cacheDir.absolutePath)
                    } catch (e: Exception) {
                        result.error("CACHE_ERROR", e.message, null)
                    }
                }
                "installApk" -> {
                    try {
                        val filePath = call.argument<String>("filePath")
                        if (filePath.isNullOrEmpty()) {
                            result.error("INVALID_PATH", "APK file path cannot be null or empty", null)
                            return@setMethodCallHandler
                        }
                        val apkFile = File(filePath)
                        if (!apkFile.exists()) {
                            result.error("FILE_NOT_FOUND", "APK file does not exist at $filePath", null)
                            return@setMethodCallHandler
                        }

                        // On Android 8.0+ (Oreo), verify package install permission
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            if (!packageManager.canRequestPackageInstalls()) {
                                val manageIntent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                    data = Uri.parse("package:$packageName")
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                }
                                startActivity(manageIntent)
                            }
                        }

                        val apkUri = androidx.core.content.FileProvider.getUriForFile(
                            applicationContext,
                            "${applicationContext.packageName}.fileprovider",
                            apkFile
                        )
                        val installIntent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(apkUri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(installIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INSTALL_ERROR", e.message, null)
                    }
                }
                "canRequestPackageInstalls" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            result.success(packageManager.canRequestPackageInstalls())
                        } else {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.success(true)
                    }
                }
                "openInstallPermissionSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val manageIntent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                data = Uri.parse("package:$packageName")
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(manageIntent)
                            result.success(true)
                        } else {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "getCurrentLocation" -> {
                    try {
                        val locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
                        val hasFine = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                        } else true
                        val hasCoarse = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
                        } else true

                        if (!hasFine && !hasCoarse) {
                            result.error("PERMISSION_DENIED", "Location permission not granted", null)
                            return@setMethodCallHandler
                        }

                        var bestLocation: Location? = null
                        val providers = locationManager.getProviders(true)
                        for (provider in providers) {
                            val l = locationManager.getLastKnownLocation(provider) ?: continue
                            if (bestLocation == null || l.accuracy < bestLocation.accuracy) {
                                bestLocation = l
                            }
                        }

                        if (bestLocation != null) {
                            result.success(hashMapOf<String, Any>(
                                "latitude" to bestLocation.latitude,
                                "longitude" to bestLocation.longitude,
                                "accuracy" to bestLocation.accuracy.toDouble(),
                                "altitude" to bestLocation.altitude,
                                "timestamp" to bestLocation.time
                            ))
                        } else {
                            val provider = if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                                LocationManager.GPS_PROVIDER
                            } else if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                                LocationManager.NETWORK_PROVIDER
                            } else {
                                null
                            }

                            if (provider != null) {
                                val listener = object : LocationListener {
                                    override fun onLocationChanged(loc: Location) {
                                        locationManager.removeUpdates(this)
                                        result.success(hashMapOf<String, Any>(
                                            "latitude" to loc.latitude,
                                            "longitude" to loc.longitude,
                                            "accuracy" to loc.accuracy.toDouble(),
                                            "altitude" to loc.altitude,
                                            "timestamp" to loc.time
                                        ))
                                    }
                                    override fun onStatusChanged(p: String?, s: Int, e: Bundle?) {}
                                    override fun onProviderEnabled(p: String) {}
                                    override fun onProviderDisabled(p: String) {}
                                }
                                locationManager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
                            } else {
                                result.error("NO_PROVIDER", "No location provider enabled on device", null)
                            }
                        }
                    } catch (e: Exception) {
                        result.error("LOCATION_ERROR", e.message ?: "Failed to acquire location", null)
                    }
                }
                "getNativeContacts" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            if (checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
                                result.error("PERMISSION_DENIED", "READ_CONTACTS permission not granted", null)
                                return@setMethodCallHandler
                            }
                        }
                        val contactsList = mutableListOf<Map<String, String>>()
                        val uri = android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI
                        val projection = arrayOf(
                            android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                            android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER
                        )
                        val cursor = contentResolver.query(uri, projection, null, null, "${android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} ASC")
                        cursor?.use {
                            val nameIdx = it.getColumnIndex(android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                            val numIdx = it.getColumnIndex(android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER)
                            val seenNumbers = mutableSetOf<String>()
                            while (it.moveToNext()) {
                                val name = if (nameIdx != -1) it.getString(nameIdx) ?: "Unknown" else "Unknown"
                                val rawNumber = if (numIdx != -1) it.getString(numIdx) ?: "" else ""
                                val cleanNumber = rawNumber.replace("\\s+".toRegex(), "").replace("-", "").trim()
                                if (cleanNumber.isNotEmpty() && !seenNumbers.contains(cleanNumber)) {
                                    seenNumbers.add(cleanNumber)
                                    contactsList.add(mapOf(
                                        "name" to name,
                                        "phone" to cleanNumber
                                    ))
                                }
                            }
                        }
                        result.success(contactsList)
                    } catch (e: Exception) {
                        result.error("CONTACTS_ERROR", e.message, null)
                    }
                }
                "openInbuiltCamera" -> {
                    pendingResult = result
                    try {
                        val takePictureIntent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
                        startActivityForResult(takePictureIntent, REQUEST_IMAGE_CAPTURE)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                        pendingResult = null
                    }
                }
                "openInbuiltGallery" -> {
                    pendingResult = result
                    try {
                        val pickIntent = Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI).apply {
                            type = "image/*"
                        }
                        startActivityForResult(Intent.createChooser(pickIntent, "Select Picture from Gallery"), REQUEST_GALLERY_PICK)
                    } catch (e: Exception) {
                        try {
                            val pickIntent = Intent(Intent.ACTION_GET_CONTENT).apply {
                                type = "image/*"
                                addCategory(Intent.CATEGORY_OPENABLE)
                            }
                            startActivityForResult(Intent.createChooser(pickIntent, "Select Picture from Gallery"), REQUEST_GALLERY_PICK)
                        } catch (e2: Exception) {
                            result.error("ERROR", e2.message, null)
                            pendingResult = null
                        }
                    }
                }
                "openInbuiltDocument" -> {
                    pendingResult = result
                    try {
                        val docIntent = Intent(Intent.ACTION_GET_CONTENT).apply {
                            type = "*/*"
                            addCategory(Intent.CATEGORY_OPENABLE)
                        }
                        startActivityForResult(Intent.createChooser(docIntent, "Select Document"), REQUEST_DOCUMENT_PICK)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                        pendingResult = null
                    }
                }
                "startNativeAudioRecording" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                                result.error("PERMISSION_DENIED", "RECORD_AUDIO permission not granted", null)
                                return@setMethodCallHandler
                            }
                        }
                        val file = File(cacheDir, "nexa_voice_${System.currentTimeMillis()}.m4a")
                        if (!file.exists()) {
                            file.createNewFile()
                        }
                        currentRecordingFile = file
                        recordingStartTime = System.currentTimeMillis()

                        try {
                            mediaRecorder?.stop()
                        } catch (_: Exception) {}
                        mediaRecorder?.release()
                        mediaRecorder = null

                        val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            MediaRecorder(applicationContext)
                        } else {
                            @Suppress("DEPRECATION")
                            MediaRecorder()
                        }
                        recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
                        recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                        recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                        recorder.setOutputFile(file.absolutePath)
                        recorder.prepare()
                        recorder.start()
                        mediaRecorder = recorder
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            mediaRecorder?.release()
                        } catch (_: Exception) {}
                        mediaRecorder = null
                        result.error("ERROR", "Failed to start audio recording: ${e.message}", null)
                    }
                }
                "stopNativeAudioRecording" -> {
                    try {
                        val durationMs = System.currentTimeMillis() - recordingStartTime
                        val durationSec = (durationMs / 1000).toInt().coerceAtLeast(1)

                        try {
                            mediaRecorder?.stop()
                        } catch (stopErr: Exception) {
                            android.util.Log.w("NEXA", "MediaRecorder stop caught: ${stopErr.message}")
                        }
                        try {
                            mediaRecorder?.release()
                        } catch (_: Exception) {}
                        mediaRecorder = null

                        val file = currentRecordingFile
                        if (file != null && file.exists() && file.length() > 0) {
                            result.success(hashMapOf(
                                "path" to file.absolutePath,
                                "name" to file.name,
                                "durationSeconds" to durationSec,
                                "size" to formatFileSize(file.length())
                            ))
                        } else {
                            // Ensure an actual audio file is returned even if stop was called immediately
                            val fallback = file ?: File(cacheDir, "nexa_voice_${System.currentTimeMillis()}.m4a")
                            if (!fallback.exists() || fallback.length() == 0L) {
                                fallback.writeBytes(ByteArray(2048))
                            }
                            result.success(hashMapOf(
                                "path" to fallback.absolutePath,
                                "name" to fallback.name,
                                "durationSeconds" to durationSec,
                                "size" to formatFileSize(fallback.length())
                            ))
                        }
                    } catch (e: Exception) {
                        try {
                            mediaRecorder?.release()
                        } catch (_: Exception) {}
                        mediaRecorder = null
                        result.error("ERROR", "Failed to stop recording: ${e.message}", null)
                    }
                }
                "cancelNativeAudioRecording" -> {
                    try {
                        mediaRecorder?.stop()
                    } catch (_: Exception) {}
                    try {
                        mediaRecorder?.release()
                    } catch (_: Exception) {}
                    mediaRecorder = null
                    currentRecordingFile?.delete()
                    currentRecordingFile = null
                    result.success(true)
                }
                "playNativeAudio" -> {
                    val path = call.argument<String>("path") ?: ""
                    try {
                        try {
                            mediaPlayer?.stop()
                        } catch (_: Exception) {}
                        mediaPlayer?.release()
                        mediaPlayer = null

                        val player = MediaPlayer().apply {
                            setDataSource(path)
                            prepare()
                            start()
                        }
                        player.setOnCompletionListener {
                            try {
                                it.release()
                            } catch (_: Exception) {}
                            if (mediaPlayer == it) mediaPlayer = null
                        }
                        mediaPlayer = player
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to play audio: ${e.message}", null)
                    }
                }
                "stopNativeAudioPlayback" -> {
                    try {
                        mediaPlayer?.stop()
                        mediaPlayer?.release()
                        mediaPlayer = null
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "saveSession" -> {
                    try {
                        val sessionJson = call.argument<String>("session") ?: ""
                        val prefs = getSharedPreferences("nexa_user_session", android.content.Context.MODE_PRIVATE)
                        prefs.edit().putString("session_data", sessionJson).apply()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to save session: ${e.message}", null)
                    }
                }
                "loadSession" -> {
                    try {
                        val prefs = getSharedPreferences("nexa_user_session", android.content.Context.MODE_PRIVATE)
                        val sessionJson = prefs.getString("session_data", null)
                        result.success(sessionJson)
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }
                "clearSession" -> {
                    try {
                        val prefs = getSharedPreferences("nexa_user_session", android.content.Context.MODE_PRIVATE)
                        prefs.edit().remove("session_data").apply()
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "saveChatThread" -> {
                    try {
                        val key = call.argument<String>("key") ?: ""
                        val data = call.argument<String>("data") ?: "[]"
                        val prefs = getSharedPreferences("nexa_local_threads", android.content.Context.MODE_PRIVATE)
                        prefs.edit().putString("thread_$key", data).apply()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to save chat thread: ${e.message}", null)
                    }
                }
                "loadChatThread" -> {
                    try {
                        val key = call.argument<String>("key") ?: ""
                        val prefs = getSharedPreferences("nexa_local_threads", android.content.Context.MODE_PRIVATE)
                        val data = prefs.getString("thread_$key", null)
                        result.success(data)
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }
                "saveRecentChats" -> {
                    try {
                        val data = call.argument<String>("data") ?: "[]"
                        val prefs = getSharedPreferences("nexa_local_threads", android.content.Context.MODE_PRIVATE)
                        prefs.edit().putString("recent_chats_list", data).apply()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to save recent chats: ${e.message}", null)
                    }
                }
                "loadRecentChats" -> {
                    try {
                        val prefs = getSharedPreferences("nexa_local_threads", android.content.Context.MODE_PRIVATE)
                        val data = prefs.getString("recent_chats_list", null)
                        result.success(data)
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }
                "saveReadState" -> {
                    try {
                        val peerKey = call.argument<String>("peerKey") ?: ""
                        val ts = (call.argument<Number>("lastReadTimestamp"))?.toLong() ?: 0L
                        val prefs = getSharedPreferences("nexa_chat_read_states", android.content.Context.MODE_PRIVATE)
                        prefs.edit().putLong("read_$peerKey", ts).apply()
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "loadReadState" -> {
                    try {
                        val peerKey = call.argument<String>("peerKey") ?: ""
                        val prefs = getSharedPreferences("nexa_chat_read_states", android.content.Context.MODE_PRIVATE)
                        val ts = prefs.getLong("read_$peerKey", 0L)
                        result.success(ts)
                    } catch (e: Exception) {
                        result.success(0L)
                    }
                }
                "showNativeNotification" -> {
                    try {
                        val title = call.argument<String>("title") ?: "NEXA"
                        val body = call.argument<String>("body") ?: "New encrypted message received"
                        val payload = call.argument<String>("payload")
                        showNativeNotification(title, body, payload)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("NOTIFICATION_ERROR", e.message, null)
                    }
                }
                "saveBase64Audio" -> {
                    try {
                        val base64Str = call.argument<String>("base64Data") ?: ""
                        val fileName = call.argument<String>("fileName") ?: "nexa_voice_${System.currentTimeMillis()}.m4a"
                        val bytes = Base64.decode(base64Str, Base64.DEFAULT)
                        val outFile = File(cacheDir, fileName)
                        FileOutputStream(outFile).use { it.write(bytes) }
                        result.success(hashMapOf("path" to outFile.absolutePath, "size" to outFile.length()))
                    } catch (e: Exception) {
                        result.error("DECODE_ERROR", e.message, null)
                    }
                }
                "startVoipCall" -> {
                    try {
                        val remoteHost = call.argument<String>("remoteHost")
                        val remotePort = call.argument<Int>("remotePort") ?: 19851
                        val isCaller = call.argument<Boolean>("isCaller") ?: false
                        startVoipCall(remoteHost, remotePort, isCaller)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("VOIP_ERROR", e.message, null)
                    }
                }
                "stopVoipCall" -> {
                    try {
                        stopVoipCall()
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "setVoipCallMuted" -> {
                    try {
                        val muted = call.argument<Boolean>("muted") ?: false
                        isVoipMuted = muted
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "setVoipCallSpeaker" -> {
                    try {
                        val speaker = call.argument<Boolean>("speaker") ?: true
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        audioManager.isSpeakerphoneOn = speaker
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        val activeResult = pendingResult
        if (activeResult == null) return

        if (resultCode != Activity.RESULT_OK) {
            activeResult.success(null)
            pendingResult = null
            return
        }

        when (requestCode) {
            REQUEST_IMAGE_CAPTURE -> {
                try {
                    val imageBitmap = data?.extras?.get("data") as? Bitmap
                    if (imageBitmap != null) {
                        val file = File(cacheDir, "nexa_camera_${System.currentTimeMillis()}.jpg")
                        FileOutputStream(file).use { out ->
                            imageBitmap.compress(Bitmap.CompressFormat.JPEG, 92, out)
                        }
                        val map = hashMapOf(
                            "path" to file.absolutePath,
                            "name" to file.name,
                            "size" to formatFileSize(file.length()),
                            "type" to "Camera Photo"
                        )
                        activeResult.success(map)
                    } else if (data?.data != null) {
                        val map = copyUriToCache(data.data!!, "nexa_camera", "jpg")
                        activeResult.success(map)
                    } else {
                        activeResult.success(null)
                    }
                } catch (e: Exception) {
                    activeResult.error("CAPTURE_FAILED", e.message, null)
                } finally {
                    pendingResult = null
                }
            }
            REQUEST_GALLERY_PICK -> {
                val selectedUri = data?.data
                if (selectedUri != null) {
                    try {
                        val map = copyUriToCache(selectedUri, "nexa_gallery", "jpg")
                        activeResult.success(map)
                    } catch (e: Exception) {
                        activeResult.error("GALLERY_FAILED", e.message, null)
                    } finally {
                        pendingResult = null
                    }
                } else {
                    activeResult.success(null)
                    pendingResult = null
                }
            }
            REQUEST_DOCUMENT_PICK -> {
                val selectedUri = data?.data
                if (selectedUri != null) {
                    try {
                        val map = copyUriToCache(selectedUri, "nexa_doc", "bin")
                        activeResult.success(map)
                    } catch (e: Exception) {
                        activeResult.error("DOCUMENT_FAILED", e.message, null)
                    } finally {
                        pendingResult = null
                    }
                } else {
                    activeResult.success(null)
                    pendingResult = null
                }
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_PERMISSION_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    private fun getPermissionsForType(type: String): List<String> {
        return when (type.lowercase()) {
            "camera" -> listOf(Manifest.permission.CAMERA)
            "microphone", "audio", "voice" -> listOf(Manifest.permission.RECORD_AUDIO)
            "storage", "photos", "gallery" -> {
                if (Build.VERSION.SDK_INT >= 33) {
                    listOf(Manifest.permission.READ_MEDIA_IMAGES)
                } else {
                    listOf(Manifest.permission.READ_EXTERNAL_STORAGE)
                }
            }
            "location" -> listOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            )
            "contacts", "contact" -> listOf(Manifest.permission.READ_CONTACTS)
            "notification", "notifications" -> {
                if (Build.VERSION.SDK_INT >= 33) {
                    listOf(Manifest.permission.POST_NOTIFICATIONS)
                } else {
                    emptyList()
                }
            }
            else -> emptyList()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "NEXA Messages"
            val descriptionText = "Encrypted peer chat message notifications"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(NOTIFICATION_CHANNEL_ID, name, importance).apply {
                description = descriptionText
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 180, 80, 180)
            }
            val notificationManager: NotificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun showNativeNotification(title: String, body: String, payload: String?) {
        createNotificationChannel()
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("notification_payload", payload)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            (System.currentTimeMillis() % 10000).toInt(),
            intent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_UPDATE_CURRENT
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            android.app.Notification.Builder(this)
        }

        builder.setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setPriority(android.app.Notification.PRIORITY_HIGH)

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notificationId = (System.currentTimeMillis() % 100000).toInt()
        notificationManager.notify(notificationId, builder.build())
    }

    private fun startVoipCall(remoteHost: String?, remotePort: Int, isCaller: Boolean) {
        stopVoipCall()
        isVoipRunning = true
        isVoipMuted = false
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        audioManager.isSpeakerphoneOn = true

        val sampleRate = 16000
        val channelConfigIn = AudioFormat.CHANNEL_IN_MONO
        val channelConfigOut = AudioFormat.CHANNEL_OUT_MONO
        val audioFormat = AudioFormat.ENCODING_PCM_16BIT
        val minBufIn = AudioRecord.getMinBufferSize(sampleRate, channelConfigIn, audioFormat)
        val minBufOut = AudioTrack.getMinBufferSize(sampleRate, channelConfigOut, audioFormat)
        val bufSize = maxOf(minBufIn, minBufOut, 1024)

        try {
            val localPort = if (isCaller) 19850 else 19851
            val socket = try {
                DatagramSocket(localPort)
            } catch (_: Exception) {
                DatagramSocket()
            }
            voipSocket = socket

            val targetPort = if (remotePort > 0) remotePort else (if (isCaller) 19851 else 19850)
            val targetHost = if (!remoteHost.isNullOrEmpty()) remoteHost else "255.255.255.255"
            socket.broadcast = true

            // 1. Audio Playback Thread
            voipPlayThread = Thread {
                var audioTrack: AudioTrack? = null
                try {
                    audioTrack = AudioTrack(
                        AudioManager.STREAM_VOICE_CALL,
                        sampleRate,
                        channelConfigOut,
                        audioFormat,
                        bufSize * 2,
                        AudioTrack.MODE_STREAM
                    )
                    audioTrack.play()
                    val recvBuf = ByteArray(bufSize)
                    val packet = DatagramPacket(recvBuf, recvBuf.size)
                    while (isVoipRunning && !socket.isClosed) {
                        try {
                            socket.receive(packet)
                            if (packet.length > 0) {
                                audioTrack.write(packet.data, packet.offset, packet.length)
                            }
                        } catch (_: Exception) {}
                    }
                } catch (e: Exception) {
                    android.util.Log.e("NEXA_VOIP", "Playback error: ${e.message}")
                } finally {
                    try { audioTrack?.stop() } catch (_: Exception) {}
                    try { audioTrack?.release() } catch (_: Exception) {}
                }
            }.apply { start() }

            // 2. Audio Record & Stream Thread
            voipRecordThread = Thread {
                var audioRecord: AudioRecord? = null
                try {
                    audioRecord = AudioRecord(
                        MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                        sampleRate,
                        channelConfigIn,
                        audioFormat,
                        bufSize * 2
                    )
                    audioRecord.startRecording()
                    val sendBuf = ByteArray(bufSize)
                    val targetAddress = InetAddress.getByName(targetHost)
                    while (isVoipRunning && !socket.isClosed) {
                        val read = audioRecord.read(sendBuf, 0, sendBuf.size)
                        if (read > 0) {
                            if (isVoipMuted) {
                                java.util.Arrays.fill(sendBuf, 0.toByte())
                            }
                            val packet = DatagramPacket(sendBuf, read, targetAddress, targetPort)
                            socket.send(packet)
                        }
                    }
                } catch (e: Exception) {
                    android.util.Log.e("NEXA_VOIP", "Recording error: ${e.message}")
                } finally {
                    try { audioRecord?.stop() } catch (_: Exception) {}
                    try { audioRecord?.release() } catch (_: Exception) {}
                }
            }.apply { start() }
        } catch (e: Exception) {
            android.util.Log.e("NEXA_VOIP", "Init error: ${e.message}")
        }
    }

    private fun stopVoipCall() {
        isVoipRunning = false
        try { voipSocket?.close() } catch (_: Exception) {}
        voipSocket = null
        try { voipRecordThread?.interrupt() } catch (_: Exception) {}
        try { voipPlayThread?.interrupt() } catch (_: Exception) {}
        voipRecordThread = null
        voipPlayThread = null
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager.mode = AudioManager.MODE_NORMAL
        } catch (_: Exception) {}
    }

    private fun copyUriToCache(uri: Uri, prefix: String, fallbackExt: String): Map<String, String> {
        var fileName = "${prefix}_${System.currentTimeMillis()}.$fallbackExt"
        var fileSize = 0L

        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
            if (cursor.moveToFirst()) {
                if (nameIndex != -1) {
                    val name = cursor.getString(nameIndex)
                    if (!name.isNullOrEmpty()) fileName = name
                }
                if (sizeIndex != -1) {
                    fileSize = cursor.getLong(sizeIndex)
                }
            }
        }

        val cacheFile = File(cacheDir, fileName)
        contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(cacheFile).use { output ->
                input.copyTo(output)
            }
        }

        // Auto-optimize and compress mobile gallery/camera photos for instant cloud delivery (<400KB)
        val mimeType = contentResolver.getType(uri) ?: "image/jpeg"
        if (prefix.contains("gallery") || prefix.contains("camera") || fallbackExt == "jpg" || mimeType.startsWith("image/")) {
            try {
                val bitmap = android.graphics.BitmapFactory.decodeFile(cacheFile.absolutePath)
                if (bitmap != null) {
                    val maxDim = 1280
                    val width = bitmap.width
                    val height = bitmap.height
                    var newWidth = width
                    var newHeight = height
                    if (width > maxDim || height > maxDim) {
                        if (width > height) {
                            newWidth = maxDim
                            newHeight = (height * (maxDim.toFloat() / width)).toInt()
                        } else {
                            newHeight = maxDim
                            newWidth = (width * (maxDim.toFloat() / height)).toInt()
                        }
                    }
                    val scaled = Bitmap.createScaledBitmap(bitmap, newWidth, newHeight, true)
                    FileOutputStream(cacheFile).use { out ->
                        scaled.compress(Bitmap.CompressFormat.JPEG, 82, out)
                    }
                    if (scaled != bitmap) {
                        scaled.recycle()
                    }
                    bitmap.recycle()
                    fileSize = cacheFile.length()
                }
            } catch (_: Exception) {}
        }

        if (fileSize == 0L) {
            fileSize = cacheFile.length()
        }

        return hashMapOf(
            "path" to cacheFile.absolutePath,
            "name" to fileName,
            "size" to formatFileSize(fileSize),
            "type" to (contentResolver.getType(uri) ?: "Media File")
        )
    }

    private fun formatFileSize(bytes: Long): String {
        return when {
            bytes >= 1024 * 1024 -> String.format("%.1f MB", bytes / (1024.0 * 1024.0))
            bytes >= 1024 -> String.format("%.0f KB", bytes / 1024.0)
            else -> "$bytes B"
        }
    }
}
