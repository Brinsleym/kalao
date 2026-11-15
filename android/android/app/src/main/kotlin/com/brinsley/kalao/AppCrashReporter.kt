// Derived from Mornye (https://github.com/mornyeapp/Mornye), Copyright 2026 zarzet,
// LGPL-3.0-only. Modified for Kalao.
package com.brinsley.kalao

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
        val versionName = try {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: ""
        } catch (_: Exception) {
            ""
        }
        val runtimeContext = File(dir(context), CONTEXT_FILE)
            .takeIf { it.isFile }
            ?.let { runCatching { JSONObject(it.readText(Charsets.UTF_8)) }.getOrNull() }
        val report = JSONObject()
            .put("time", System.currentTimeMillis())
            .put("thread", thread)
            .put("error", error.toString().take(MAX_TEXT))
            .put("stack", error.stackTraceToString().take(MAX_TEXT))
            .put("appVersion", versionName)
            .put("sdk", Build.VERSION.SDK_INT)
            .put("device", "${Build.MANUFACTURER} ${Build.MODEL}")
            .put("abi", Build.SUPPORTED_ABIS.firstOrNull() ?: "")
            .put("dartContext", runtimeContext ?: JSONObject.NULL)
        atomicWrite(File(dir(context), CRASH_FILE), report.toString())
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
