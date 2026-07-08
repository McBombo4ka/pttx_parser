package com.example.pptx_parsing

import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {

    private val CHANNEL = "downloads_saver"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->

                if (call.method == "saveToDownloads") {

                    val name = call.argument<String>("name") ?: "file.html"
                    val bytes = call.argument<ByteArray>("bytes")
                    val mimeType = call.argument<String>("mimeType") ?: "text/html"

                    if (bytes == null) {
                        result.error("NULL_BYTES", "File is empty", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val resolver = applicationContext.contentResolver

                        val contentValues = ContentValues().apply {
                            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                            put(MediaStore.MediaColumns.RELATIVE_PATH, "Download/")
                        }

                        val uri: Uri? = resolver.insert(
                            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                            contentValues
                        )

                        if (uri == null) {
                            result.error("INSERT_FAILED", "MediaStore insert failed", null)
                            return@setMethodCallHandler
                        }

                        resolver.openOutputStream(uri).use { output ->
                            output?.write(bytes)
                        }

                        result.success(uri.toString())

                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.message, null)
                    }
                }
            }
    }
}