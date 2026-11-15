// Derived from Mornye (https://github.com/mornyeapp/Mornye), Copyright 2026 zarzet,
// LGPL-3.0-only. Modified for Kalao.
package com.brinsley.kalao

import android.app.Application

class KalaoApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        AppCrashReporter.install(this)
    }
}
