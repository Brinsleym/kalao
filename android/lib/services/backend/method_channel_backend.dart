// Derived from Mornye (https://github.com/mornyeapp/Mornye), Copyright 2026 zarzet,
// LGPL-3.0-only. Modified for Kalao.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kalao/services/backend/backend_channel.dart';

/// The Android backend: the host platform channel, unchanged.
class MethodChannelBackend extends BackendChannel {
  const MethodChannelBackend(this.channel);

  static const channelName = 'com.brinsley.kalao/backend';
  static const shared = MethodChannelBackend(MethodChannel(channelName));

  final MethodChannel channel;

  @override
  @optionalTypeArgs
  Future<T?> invokeMethod<T>(String method, [Object? arguments]) =>
      channel.invokeMethod<T>(method, arguments);

  @override
  void setMethodCallHandler(BackendCallHandler? handler) =>
      channel.setMethodCallHandler(handler);
}
