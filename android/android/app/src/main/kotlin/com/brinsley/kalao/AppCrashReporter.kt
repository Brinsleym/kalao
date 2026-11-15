// Derived from Mornye (https://github.com/mornyeapp/Mornye), Copyright 2026 zarzet,
// LGPL-3.0-only. Modified for Kalao.
package com.brinsley.kalao

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import org.json.JSONObject
import java.io.File

/**
 * Keeps the most recent process crash on the device so the app can show it on
 * the next start (copy it, or open a GitHub issue). Nothing is sent anywhere.
 *
 * Dart errors are only saved as context: a handled Flutter error must not
 * produce an "app crashed" message on the next launch. If the process then
 * dies, the crash report includes that context.
 */
object AppCrashReporter {
    private const val CRASH_FILE = "last_crash.json"
    private const val CONTEXT_FILE = "last_runtime_error.json"
    private const val MAX_TEXT = 64 * 1024
    private const val MAX_TRACE_BYTES = 2 * 1024 * 1024
    private const val PREFS = "app_crash_reports"
    private const val NATIVE_SEEN_AT = "native_exit_seen_at"

    private fun dir(context: Context) = File(context.filesDir, "crash")

    /** Chains in front of the existing handler; call once from Application.onCreate. */
    fun install(context: Context) {
        val app = context.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                writeCrash(app, thread.name, error)
            } catch (_: Throwable) {
                // Never mask the original crash.
            }
            previous?.uncaughtException(thread, error)
        }
    }

    /**
     * Native crashes (a Rust abort or a signal in the audio engine) never reach
     * the JVM handler. On Android 11+ the system keeps the tombstone; read the
     * newest unseen one at startup and store it like a JVM crash.
     */
    fun captureNativeExit(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val seenAt = prefs.getLong(NATIVE_SEEN_AT, 0L)
            val manager = context.getSystemService(ActivityManager::class.java) ?: return
            val exit = manager.getHistoricalProcessExitReasons(context.packageName, 0, 1)
                .firstOrNull() ?: return
            if (exit.timestamp <= seenAt) return
            prefs.edit().putLong(NATIVE_SEEN_AT, exit.timestamp).apply()
            if (exit.reason != ApplicationExitInfo.REASON_CRASH_NATIVE) return
            val trace = try {
                exit.traceInputStream?.use { NativeCrashTrace.decode(it.takeBounded(MAX_TRACE_BYTES)) }
            } catch (error: Exception) {
                "Android crash trace unavailable: ${error.javaClass.simpleName}"
            }
            val report = baseReport(context, exit.timestamp, "native")
                .put("error", "Native crash: ${exit.description.orEmpty()}".take(MAX_TEXT))
                .put("stack", (trace ?: "").take(MAX_TEXT))
            atomicWrite(File(dir(context), CRASH_FILE), report.toString())
        } catch (_: Exception) {
            // Diagnostics must never block startup.
        }
    }

    /** Context from the last Dart runtime error, attached to a later crash. */
    fun recordRuntimeError(context: Context, error: String, stack: String, logs: String) {
        val report = JSONObject()
            .put("time", System.currentTimeMillis())
            .put("error", error.take(MAX_TEXT))
            .put("stack", stack.take(MAX_TEXT))
            .put("logs", logs.takeLast(MAX_TEXT))
        atomicWrite(File(dir(context), CONTEXT_FILE), report.toString())
    }

    fun read(context: Context): String? =
        File(dir(context), CRASH_FILE).takeIf { it.isFile }?.readText(Charsets.UTF_8)

    fun clear(context: Context) {
        File(dir(context), CRASH_FILE).delete()
        File(dir(context), CONTEXT_FILE).delete()
    }

    private fun writeCrash(context: Context, thread: String, error: Throwable) {
        val report = baseReport(context, System.currentTimeMillis(), thread)
            .put("error", error.toString().take(MAX_TEXT))
            .put("stack", error.stackTraceToString().take(MAX_TEXT))
        atomicWrite(File(dir(context), CRASH_FILE), report.toString())
    }

    private fun baseReport(context: Context, time: Long, thread: String): JSONObject {
        val versionName = try {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: ""
        } catch (_: Exception) {
            ""
        }
        val runtimeContext = File(dir(context), CONTEXT_FILE)
            .takeIf { it.isFile }
            ?.let { runCatching { JSONObject(it.readText(Charsets.UTF_8)) }.getOrNull() }
        return JSONObject()
            .put("time", time)
            .put("thread", thread)
            .put("appVersion", versionName)
            .put("sdk", Build.VERSION.SDK_INT)
            .put("device", "${Build.MANUFACTURER} ${Build.MODEL}")
            .put("abi", Build.SUPPORTED_ABIS.firstOrNull() ?: "")
            .put("dartContext", runtimeContext ?: JSONObject.NULL)
    }

    private fun java.io.InputStream.takeBounded(limit: Int): ByteArray {
        val output = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (output.size() < limit) {
            val count = read(buffer, 0, minOf(buffer.size, limit - output.size()))
            if (count < 0) break
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    private fun atomicWrite(target: File, text: String) {
        target.parentFile?.mkdirs()
        val temp = File(target.parentFile, "${target.name}.tmp")
        temp.writeText(text, Charsets.UTF_8)
        if (!temp.renameTo(target)) {
            target.delete()
            temp.renameTo(target)
        }
    }
}
