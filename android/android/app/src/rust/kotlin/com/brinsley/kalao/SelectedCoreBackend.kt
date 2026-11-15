// Derived from Mornye (https://github.com/mornyeapp/Mornye), Copyright 2026 zarzet,
// LGPL-3.0-only. Modified for Kalao.
package com.brinsley.kalao

import android.content.Context
import com.brinsley.kalao.backend.invokeApplication as rustInvokeApplication
import com.brinsley.kalao.backend.runNativeDataJob
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/** The backend that answers every channel method Kotlin does not handle itself. */
internal interface CoreBackend {
    val implementation: String

    /** [arguments] is the channel's argument value; the reply is JSON text. */
    fun invokeApplication(method: String, arguments: Any?): String
}

internal fun createCoreBackend(context: Context): CoreBackend = RustCoreBackend.initialize(context)

/**
 * Runs a Rust method on Dispatchers.IO and replies with its JSON text (or a
 * `__json_file` spill map for large replies). Data jobs get a cancellation
 * lease acquired before the call is queued, so a following
 * `cancelNativeDataJob` also reaches work that has not started.
 */
internal suspend fun MainActivity.dispatchBackendApplication(call: MethodCall, result: MethodChannel.Result): Boolean {
    if (call.method == "cancelNativeDataJob") {
        NativeDataJobs.cancel(call.argument<String>("request_id") ?: "")
        result.success(null)
        return true
    }
    val jobId = if (call.method == "runNativeDataJob") {
        call.argument<String>("request_id") ?: error("Missing data job ID")
    } else {
        null
    }
    val jobLease = jobId?.let { NativeDataJobs.acquire(it) }
    val response = try {
        withContext(Dispatchers.IO) {
            if (jobLease != null) {
                val request = call.argument<String>("request_json") ?: error("Missing data job request")
                runNativeDataJob(request, jobLease)
            } else {
                coreBackend.invokeApplication(call.method, call.arguments)
            }
        }
    } finally {
        if (jobLease != null) NativeDataJobs.release(checkNotNull(jobId), jobLease)
    }
    result.success(bridgeJsonResult(response))
    return true
}

internal object RustCoreBackend : CoreBackend {
    override val implementation = "rust"
    @Volatile private var initialized = false

    @Synchronized
    fun initialize(context: Context): RustCoreBackend {
        if (!initialized) {
            // Load the library now so a missing or broken .so fails at startup,
            // not on the first user action.
            val app = context.applicationContext
            rustInvokeApplication(
                "initBackend",
                JSONObject()
                    .put("filesDir", app.filesDir.resolve("backend").absolutePath)
                    .put("cacheDir", app.cacheDir.resolve("backend").absolutePath)
                    .toString(),
            )
            initialized = true
        }
        return this
    }

    override fun invokeApplication(method: String, arguments: Any?): String =
        rustInvokeApplication(method, toJson(arguments))

    private fun toJson(value: Any?): String = when (value) {
        null -> "{}"
        is String -> value
        else -> jsonValue(value).toString()
    }

    private fun jsonValue(value: Any?): Any = when (value) {
        null -> JSONObject.NULL
        is Map<*, *> -> JSONObject().also { json ->
            value.forEach { (key, item) -> json.put(key.toString(), jsonValue(item)) }
        }
        is List<*> -> JSONArray().also { json -> value.forEach { json.put(jsonValue(it)) } }
        is ByteArray -> JSONArray().also { json -> value.forEach { json.put(it.toInt() and 0xff) } }
        is Number, is Boolean, is String -> value
        else -> value.toString()
    }
}
