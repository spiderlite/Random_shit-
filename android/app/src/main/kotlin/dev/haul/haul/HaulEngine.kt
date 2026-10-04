package dev.haul.haul

import android.content.Context
import android.os.Environment
import android.os.Handler
import android.os.Looper
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLException
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Bridges Flutter to yt-dlp running on the embedded Python from
 * youtubedl-android. Dart builds the exact argument list (shared with the
 * desktop app); this class just runs it and streams stdout lines back.
 */
class HaulEngine(private val context: Context) : EventChannel.StreamHandler {
    private val executor = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    @Volatile
    private var initialized = false

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private fun post(block: () -> Unit) = main.post(block)

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> executor.execute {
                try {
                    ensureInit()
                    maybeAutoUpdate()
                    // youtubedl-android ships QuickJS; yt-dlp uses it to solve
                    // YouTube's JS challenges (full format list).
                    val qjs = File(context.applicationInfo.nativeLibraryDir, "libqjs.so")
                    val info = mapOf(
                        "version" to version(),
                        "downloadDir" to downloadDir().absolutePath,
                        "cacheDir" to context.cacheDir.absolutePath,
                        "jsRuntime" to (if (qjs.exists()) "quickjs:${qjs.absolutePath}" else null),
                    )
                    post { result.success(info) }
                } catch (e: Throwable) {
                    post { result.error("init", "Couldn't start the download engine.", describe(e)) }
                }
            }

            "run" -> {
                val id = call.argument<String>("id")!!
                val args = call.argument<List<String>>("args") ?: emptyList()
                executor.execute { run(id, args, result) }
            }

            "cancel" -> {
                val id = call.argument<String>("id")!!
                executor.execute {
                    YoutubeDL.getInstance().destroyProcessById(id)
                    post { result.success(null) }
                }
            }

            "update" -> executor.execute {
                try {
                    ensureInit()
                    val status = YoutubeDL.getInstance().updateYoutubeDL(context, YoutubeDL.UpdateChannel.STABLE)
                    markUpdated()
                    val map = mapOf("status" to (status?.name ?: "DONE"), "version" to version())
                    post { result.success(map) }
                } catch (e: Throwable) {
                    post { result.error("update", "Couldn't update. Check your connection.", null) }
                }
            }

            else -> result.notImplemented()
        }
    }

    /** Exception type, message and root cause, for the error screen's "Copy details". */
    private fun describe(e: Throwable): String = buildString {
        var t: Throwable? = e
        var depth = 0
        while (t != null && depth < 4) {
            if (depth > 0) append("\ncaused by ")
            append(t.javaClass.name)
            t.message?.let { append(": ").append(it) }
            t = t.cause
            depth++
        }
        e.stackTrace.take(6).forEach { append("\n  at ").append(it) }
    }

    @Synchronized
    private fun ensureInit() {
        if (initialized) return
        YoutubeDL.getInstance().init(context)
        FFmpeg.getInstance().init(context)
        initialized = true
    }

    /**
     * Sites change constantly and yt-dlp keeps up, so a stale copy is the #1
     * cause of failed downloads. Refresh at most once a day, before any
     * download starts (init gates the queue). Offline is fine — we just
     * keep the bundled version.
     */
    private fun maybeAutoUpdate() {
        val prefs = context.getSharedPreferences("haul", Context.MODE_PRIVATE)
        val last = prefs.getLong("ytdlpUpdatedAt", 0L)
        if (System.currentTimeMillis() - last < 24L * 60 * 60 * 1000) return
        try {
            YoutubeDL.getInstance().updateYoutubeDL(context, YoutubeDL.UpdateChannel.STABLE)
            markUpdated()
        } catch (_: Throwable) {
        }
    }

    private fun markUpdated() {
        context.getSharedPreferences("haul", Context.MODE_PRIVATE)
            .edit().putLong("ytdlpUpdatedAt", System.currentTimeMillis()).apply()
    }

    private fun version(): String? {
        YoutubeDL.getInstance().version(context)?.let { return it }
        return try {
            val r = YoutubeDL.getInstance().execute(YoutubeDLRequest(emptyList<String>()).addOption("--version"))
            r.out.trim().lines().firstOrNull()
        } catch (_: Throwable) {
            null
        }
    }

    private fun downloadDir(): File {
        @Suppress("DEPRECATION")
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "Haul")
        dir.mkdirs()
        return dir
    }

    private fun run(id: String, args: List<String>, result: MethodChannel.Result) {
        try {
            ensureInit()
            val cache = File(context.cacheDir, "yt-dlp-cache").apply { mkdirs() }
            val request = YoutubeDLRequest(emptyList<String>())
                // Keeps YouTube's player code cached between runs: much faster starts.
                .addOption("--cache-dir", cache.absolutePath)
                .addCommands(args)
            val response = YoutubeDL.getInstance().execute(request, id) { _, _, line ->
                post { sink?.success(mapOf("id" to id, "line" to line)) }
            }
            val map = mapOf("exitCode" to response.exitCode, "out" to response.out, "err" to response.err)
            post { result.success(map) }
        } catch (e: YoutubeDL.CanceledException) {
            post { result.success(mapOf("exitCode" to 1, "out" to "", "err" to "", "cancelled" to true)) }
        } catch (e: YoutubeDLException) {
            val err = e.message ?: "ERROR: download failed"
            post { result.success(mapOf("exitCode" to 1, "out" to "", "err" to err)) }
        } catch (e: Throwable) {
            post { result.success(mapOf("exitCode" to 1, "out" to "", "err" to "ERROR: ${e.message}")) }
        }
    }
}
