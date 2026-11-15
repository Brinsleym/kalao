// Derived from Mornye (https://github.com/mornyeapp/Mornye), Copyright 2026 zarzet,
// LGPL-3.0-only. Modified for Kalao.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kalao/services/backend/method_channel_backend.dart';

/// Handles a host to Dart call, like [MethodChannel.setMethodCallHandler].
typedef BackendCallHandler = Future<Object?> Function(MethodCall call);

/// Transport between Dart and the Rust backend.
///
/// Android uses the platform channel ([MethodChannelBackend]). Desktop builds
/// will call the Rust library directly through `dart:ffi` (`RustFfiBackend`,
/// added with `desktop/`), with the same method names and replies.
abstract class BackendChannel {
  const BackendChannel();

  /// Same contract as [MethodChannel.invokeMethod]. Methods the backend does
  /// not implement throw [MissingPluginException] or a [PlatformException].
  @optionalTypeArgs
  Future<T?> invokeMethod<T>(String method, [Object? arguments]);

  /// Receives host to Dart calls. Replaces any previous handler; null removes it.
  void setMethodCallHandler(BackendCallHandler? handler);
}

/// The backend of the running platform. Tests replace it with [debugOverride].
BackendChannel get backendChannel => debugOverride ?? MethodChannelBackend.shared;

@visibleForTesting
BackendChannel? debugOverride;
