package com.quakestring.ludo_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Updating the app from inside the app.
 *
 * The build is side-loaded rather than installed from a store, so nothing
 * else will ever offer it a newer version. The Dart side notices that one
 * exists; this side fetches it and hands it to Android's own installer, which
 * asks the player to confirm — an app can offer an update, never force one.
 */
class MainActivity : FlutterActivity() {
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ludo/update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "install" -> install(call.argument<String>("url")!!, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun install(url: String, result: MethodChannel.Result) {
        // Android 8 and later ask once whether this app may install others.
        // Without that, the installer would refuse; send the player to the
        // switch instead, and let them tap Update again afterwards.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                ),
            )
            result.success("permission")
            return
        }
        Thread {
            try {
                val apk = File(cacheDir, "updates/ludo.apk")
                apk.parentFile?.mkdirs()
                download(url, apk)
                main.post {
                    val uri = FileProvider.getUriForFile(
                        this, "$packageName.updates", apk,
                    )
                    startActivity(
                        Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_ACTIVITY_NEW_TASK,
                            ),
                    )
                    result.success("started")
                }
            } catch (e: Exception) {
                main.post { result.error("download", e.message, null) }
            }
        }.start()
    }

    /** Follows GitHub's redirect to wherever the file is actually stored. */
    private fun download(from: String, to: File) {
        var url = URL(from)
        repeat(5) {
            val conn = url.openConnection() as HttpURLConnection
            conn.instanceFollowRedirects = false
            conn.connectTimeout = 15000
            conn.readTimeout = 30000
            val code = conn.responseCode
            if (code in 300..399) {
                url = URL(url, conn.getHeaderField("Location"))
                conn.disconnect()
                return@repeat
            }
            if (code != 200) throw IllegalStateException("HTTP $code")
            conn.inputStream.use { input ->
                to.outputStream().use { output -> input.copyTo(output) }
            }
            return
        }
        throw IllegalStateException("too many redirects")
    }
}
