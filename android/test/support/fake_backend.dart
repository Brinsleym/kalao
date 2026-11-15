import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalao/services/backend/method_channel_backend.dart';

/// Answers the backend channel the way the Android host does: Rust methods
/// reply with JSON text, Android-native methods with typed values.
class FakeBackend {
  final calls = <MethodCall>[];
  String? crashReport;

  static const _channel = MethodChannel(MethodChannelBackend.channelName);

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, _handle);
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'getBackendInfo':
        return jsonEncode({
          'name': 'kalao-mobile',
          'version': '0.1.0',
          'os': 'android',
          'arch': 'aarch64',
          'initialized': true,
          'methods': ['getBackendInfo'],
        });
      case 'getLogs':
        return jsonEncode({
          'logs': [
            {
              'timestamp': '12:00:00.000',
              'level': 'INFO',
              'tag': 'Backend',
              'message': 'initialized',
            },
          ],
          'next_index': 1,
        });
      case 'setLoggingEnabled':
      case 'clearLogs':
        return 'null';
      case 'readLastCrashReport':
        return crashReport;
      case 'clearLastCrashReport':
      case 'recordAppRuntimeError':
        return null;
      default:
        throw PlatformException(
          code: 'ERROR',
          message: 'Rust application method is not connected yet: ${call.method}',
        );
    }
  }
}
