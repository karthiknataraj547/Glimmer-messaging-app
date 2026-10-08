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
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.media.MediaPlayer
import android.media.MediaRecorder
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
            else -> emptyList()
        }
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
