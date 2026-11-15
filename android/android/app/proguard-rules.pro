# Derived from Mornye (https://github.com/mornyeapp/Mornye), Copyright 2026 zarzet,
# LGPL-3.0-only. Modified for Kalao.

# Ignore missing Play Core classes (not used, but referenced by Flutter).
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# UniFFI/JNA resolves FFI methods and structure fields by their generated names.
-keep class com.sun.jna.** { *; }
-keep class com.brinsley.kalao.backend.** { *; }
# The JNA desktop AWT helpers are unavailable and unused on Android.
-dontwarn java.awt.Component
-dontwarn java.awt.GraphicsEnvironment
-dontwarn java.awt.HeadlessException
-dontwarn java.awt.Window

-keepclasseswithmembernames class * {
    native <methods>;
}

-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-dontwarn kotlinx.coroutines.**

-keep,allowoptimization class com.brinsley.kalao.MainActivity { public <init>(); }
-keep,allowoptimization class com.brinsley.kalao.KalaoApplication { public <init>(); }
-keep,allowoptimization class com.brinsley.kalao.BackgroundWorkService { public <init>(); }

-keepattributes *Annotation*,SourceFile,LineNumberTable,Signature,Exceptions,InnerClasses,EnclosingMethod
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
