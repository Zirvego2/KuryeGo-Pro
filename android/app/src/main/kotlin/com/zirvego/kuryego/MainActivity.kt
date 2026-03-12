package com.zirvego.kuryego

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.zirvego.kuryego/download"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "downloadApk") {
                val url = call.argument<String>("url")
                if (url != null) {
                    downloadApk(url)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGUMENT", "URL is null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun downloadApk(url: String) {
        try {
            val downloadManager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val request = DownloadManager.Request(Uri.parse(url))
                .setTitle("ZirveGo Kurye Güncelleme")
                .setDescription("Uygulama güncelleniyor...")
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, "zirvego_update.apk")
                .setAllowedOverMetered(true)
                .setAllowedOverRoaming(true)
            
            downloadManager.enqueue(request)
        } catch (e: Exception) {
            // Hata durumunda tarayıcıda aç
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            startActivity(intent)
        }
    }
}
