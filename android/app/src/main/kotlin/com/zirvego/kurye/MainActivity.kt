package com.zirvego.kurye

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.zirvego.kurye/download"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "downloadApk") {
                val url = call.argument<String>("url")
                if (url != null) {
                    val outcome = downloadApkOrOpenBrowser(url)
                    when (outcome) {
                        is DownloadOutcome.Success -> result.success(outcome.method)
                        is DownloadOutcome.Failure -> result.error(
                            "DOWNLOAD_FAILED",
                            outcome.message,
                            null,
                        )
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "URL is null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private sealed class DownloadOutcome {
        data class Success(val method: String) : DownloadOutcome()
        data class Failure(val message: String) : DownloadOutcome()
    }

    private fun downloadApkOrOpenBrowser(url: String): DownloadOutcome {
        val parsed = try {
            Uri.parse(url.trim())
        } catch (e: Exception) {
            return DownloadOutcome.Failure("Geçersiz URL: ${e.message}")
        }
        if (parsed.scheme.isNullOrEmpty() || (!parsed.scheme.equals("https", true) && !parsed.scheme.equals("http", true))) {
            return DownloadOutcome.Failure("APK adresi http veya https olmalı")
        }

        try {
            val fileName = apkFileNameFromUrl(url)
            val downloadManager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val request = DownloadManager.Request(parsed)
                .setMimeType("application/vnd.android.package-archive")
                .setTitle("ZirveGo Kurye")
                .setDescription("APK dosyası indiriliyor…")
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, fileName)
                .setAllowedOverMetered(true)
                .setAllowedOverRoaming(true)

            val id = downloadManager.enqueue(request)
            return if (id >= 0L) {
                DownloadOutcome.Success("download_manager")
            } else {
                tryOpenBrowser(url)
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "DownloadManager enqueue failed", e)
            return tryOpenBrowser(url)
        }
    }

    private fun tryOpenBrowser(url: String): DownloadOutcome {
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url.trim())).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            DownloadOutcome.Success("browser")
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Browser open failed", e)
            DownloadOutcome.Failure(
                e.message ?: "İndirme başlatılamadı. Linki tarayıcıda deneyin.",
            )
        }
    }

    /** URL yolundan (.apk) dosya adı; Firebase Storage gibi %2F içeren yollar için decode + basename. */
    private fun apkFileNameFromUrl(url: String): String {
        val fallback = "zirvego.apk"
        val trimmed = url.trim()
        if (trimmed.isEmpty()) return fallback

        val uri = Uri.parse(trimmed)
        val fromSegment = uri.lastPathSegment?.let { Uri.decode(it).substringAfterLast('/') }?.trim().orEmpty()
        val pathNoQuery = trimmed.substringBefore('?')
        val fromPath = Uri.decode(pathNoQuery.substringAfterLast('/')).substringAfterLast('/').trim()

        val candidate = when {
            fromSegment.endsWith(".apk", ignoreCase = true) -> fromSegment
            fromPath.endsWith(".apk", ignoreCase = true) -> fromPath
            else -> return fallback
        }

        val safe = candidate.replace(Regex("""[\\/:*?"<>|]"""), "_").trim()
        return if (safe.isNotEmpty() && safe.endsWith(".apk", ignoreCase = true)) safe else fallback
    }
}
