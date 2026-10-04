package dev.haul.haul

import android.Manifest
import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.webkit.MimeTypeMap
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private lateinit var engine: HaulEngine
    private var platform: MethodChannel? = null
    private var pendingShare: String? = null
    private var permissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Cold start from the share sheet: hold the text until Dart asks.
        if (savedInstanceState == null) pendingShare = sharedText(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val text = sharedText(intent) ?: return
        val channel = platform
        if (channel != null) channel.invokeMethod("sharedText", text) else pendingShare = text
    }

    override fun onResume() {
        super.onResume()
        visible = true
    }

    override fun onPause() {
        super.onPause()
        visible = false
    }

    private fun sharedText(intent: Intent?): String? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_SEND -> listOfNotNull(
                intent.getStringExtra(Intent.EXTRA_TEXT),
                intent.getStringExtra(Intent.EXTRA_SUBJECT)?.takeIf { it.startsWith("http") },
            ).joinToString("\n").ifBlank { null }
            Intent.ACTION_VIEW -> intent.dataString
            else -> null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        engine = HaulEngine(applicationContext)
        MethodChannel(messenger, "haul/engine").setMethodCallHandler(engine::handle)
        EventChannel(messenger, "haul/engine/lines").setStreamHandler(engine)

        platform = MethodChannel(messenger, "haul/platform").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeInitialShare" -> {
                        result.success(pendingShare)
                        pendingShare = null
                    }
                    "scanFile" -> {
                        val path = call.argument<String>("path")!!
                        MediaScannerConnection.scanFile(applicationContext, arrayOf(path), null) { _, uri ->
                            runOnUiThread { result.success(uri?.toString()) }
                        }
                    }
                    "openFile" -> result.success(openFile(call.argument<String>("path")!!))
                    "shareFile" -> {
                        shareFile(call.argument<String>("path")!!, call.argument<String>("title"))
                        result.success(null)
                    }
                    "openDownloads" -> result.success(
                        tryStart(Intent(DownloadManager.ACTION_VIEW_DOWNLOADS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)),
                    )
                    "openUrl" -> result.success(
                        tryStart(Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url")))),
                    )
                    "background" -> {
                        DownloadService.update(
                            applicationContext,
                            call.argument<Int>("active") ?: 0,
                            call.argument<Int>("queued") ?: 0,
                            call.argument<Double>("progress"),
                            call.argument<String>("title"),
                            visible,
                        )
                        result.success(null)
                    }
                    "ensurePermissions" -> ensurePermissions(result)
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun uriFor(file: File): Uri = FileProvider.getUriForFile(this, "$packageName.files", file)

    private fun mimeOf(file: File): String =
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension.lowercase()) ?: "*/*"

    private fun openFile(path: String): Boolean {
        val file = File(path)
        if (!file.exists()) return false
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uriFor(file), mimeOf(file))
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return tryStart(intent)
    }

    private fun shareFile(path: String, title: String?) {
        val file = File(path)
        if (!file.exists()) return
        val send = Intent(Intent.ACTION_SEND)
            .setType(mimeOf(file))
            .putExtra(Intent.EXTRA_STREAM, uriFor(file))
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        tryStart(Intent.createChooser(send, title ?: file.name))
    }

    private fun tryStart(intent: Intent): Boolean = try {
        startActivity(intent)
        true
    } catch (_: ActivityNotFoundException) {
        false
    }

    private fun ensurePermissions(result: MethodChannel.Result) {
        val wanted = mutableListOf<String>()
        val prefs = getSharedPreferences("haul", MODE_PRIVATE)
        // Notifications are a nicety: ask once, never nag.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            !granted(Manifest.permission.POST_NOTIFICATIONS) &&
            !prefs.getBoolean("askedNotifications", false)
        ) {
            wanted += Manifest.permission.POST_NOTIFICATIONS
            prefs.edit().putBoolean("askedNotifications", true).apply()
        }
        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.Q &&
            !granted(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        ) {
            wanted += Manifest.permission.WRITE_EXTERNAL_STORAGE
        }
        if (wanted.isEmpty()) {
            result.success(true)
            return
        }
        permissionResult?.success(granted(Manifest.permission.WRITE_EXTERNAL_STORAGE))
        permissionResult = result
        ActivityCompat.requestPermissions(this, wanted.toTypedArray(), PERMISSIONS_REQUEST)
    }

    private fun granted(p: String) = ContextCompat.checkSelfPermission(this, p) == PackageManager.PERMISSION_GRANTED

    @Deprecated("Deprecated in Java")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSIONS_REQUEST) return
        val storageOk = Build.VERSION.SDK_INT > Build.VERSION_CODES.Q ||
            granted(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        permissionResult?.success(storageOk)
        permissionResult = null
    }

    companion object {
        private const val PERMISSIONS_REQUEST = 7
        @Volatile var visible = false
    }
}
