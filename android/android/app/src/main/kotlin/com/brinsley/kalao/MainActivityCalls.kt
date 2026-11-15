// Derived from Mornye (https://github.com/mornyeapp/Mornye), Copyright 2026 zarzet,
// LGPL-3.0-only. Modified for Kalao.
// Android-native handlers for MainActivity's backend channel, grouped as in
// Mornye's MainActivity*Calls.kt files.
package com.brinsley.kalao

import android.view.WindowManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// Lifecycle

internal fun MainActivity.handleSetScreenAwake(call: MethodCall, result: MethodChannel.Result) {
    if (call.argument<Boolean>("enabled") == true) {
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    } else {
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
    result.success(null)
}

// Services

internal fun MainActivity.handleStartBackgroundWork(call: MethodCall, result: MethodChannel.Result) {
    result.success(
        BackgroundWorkService.start(
            this,
            call.argument<String>("kind") ?: "",
            call.argument<String>("title") ?: "",
            call.argument<String>("text") ?: "",
        ),
    )
}

internal fun MainActivity.handleUpdateBackgroundWork(call: MethodCall, result: MethodChannel.Result) {
    BackgroundWorkService.update(
        call.argument<String>("kind") ?: "",
        call.argument<String>("title") ?: "",
        call.argument<String>("text") ?: "",
        call.argument<Int>("progress") ?: -1,
    )
    result.success(null)
}

internal fun MainActivity.handleStopBackgroundWork(call: MethodCall, result: MethodChannel.Result) {
    BackgroundWorkService.stop(call.argument<String>("kind") ?: "")
    result.success(null)
}

// Crash reports (kept on the device; nothing is uploaded)

internal suspend fun MainActivity.handleReadLastCrashReport(result: MethodChannel.Result) {
    result.success(withContext(Dispatchers.IO) { AppCrashReporter.read(this@handleReadLastCrashReport) })
}

internal suspend fun MainActivity.handleClearLastCrashReport(result: MethodChannel.Result) {
    withContext(Dispatchers.IO) { AppCrashReporter.clear(this@handleClearLastCrashReport) }
    result.success(null)
}

internal suspend fun MainActivity.handleRecordAppRuntimeError(call: MethodCall, result: MethodChannel.Result) {
    val error = call.argument<String>("error") ?: ""
    val stack = call.argument<String>("stack") ?: ""
    val logs = call.argument<String>("logs") ?: ""
    withContext(Dispatchers.IO) {
        AppCrashReporter.recordRuntimeError(this@handleRecordAppRuntimeError, error, stack, logs)
    }
    result.success(null)
}
