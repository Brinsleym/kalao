// Derived from Mornye (https://github.com/mornyeapp/Mornye), Copyright 2026 zarzet,
// LGPL-3.0-only. Modified for Kalao.
package com.brinsley.kalao

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val PLAYER_POSITION_STREAM_CHANNEL = "com.brinsley.kalao/player_position_stream"

/** 30 Hz while playing (Dart interpolates between events for 60 fps lyrics). */
private const val PLAYING_INTERVAL_MS = 33L
private const val IDLE_INTERVAL_MS = 250L

/**
 * Polls the engine's `playerState` (as Mornye polls its progress snapshots)
 * and forwards each changed JSON payload to Dart.
 */
internal fun MainActivity.registerProgressStreams(messenger: BinaryMessenger) {
    var job: Job? = null
    EventChannel(messenger, PLAYER_POSITION_STREAM_CHANNEL).setStreamHandler(
        object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                job?.cancel()
                val sink = events ?: return
                job = scope.launch {
                    var previous: String? = null
                    while (isActive) {
                        val payload = try {
                            withContext(Dispatchers.IO) {
                                coreBackend.invokeApplication("playerState", null)
                            }
                        } catch (error: Exception) {
                            sink.error("player_state", error.message, null)
                            null
                        }
                        if (payload != null && payload != previous) {
                            previous = payload
                            sink.success(payload)
                        }
                        val playing = payload?.contains("\"playing\":true") == true
                        delay(if (playing) PLAYING_INTERVAL_MS else IDLE_INTERVAL_MS)
                    }
                }
            }

            override fun onCancel(arguments: Any?) {
                job?.cancel()
                job = null
            }
        },
    )
}
