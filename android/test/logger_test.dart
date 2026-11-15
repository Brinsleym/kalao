import 'package:flutter_test/flutter_test.dart';
import 'package:kalao/utils/logger.dart';

void main() {
  setUp(
    () => LogBuffer()
      ..clear()
      ..verbose = false,
  );

  test('redacts tokens, keys and the MyMemory email parameter', () {
    final text = redactDiagnosticText(
      'Authorization: Bearer abc.def api_key=secret123 '
      'https://api.mymemory.translated.net/get?q=hi&de=me@example.com',
    );
    expect(text, isNot(contains('abc.def')));
    expect(text, isNot(contains('secret123')));
    expect(text, isNot(contains('me@example.com')));
    expect(text, contains('q=hi'));
  });

  test('keeps only warnings and errors unless verbose', () {
    const log = AppLogger('Test');
    log.i('dropped');
    log.w('kept');
    expect(LogBuffer().entries.map((e) => e.message), ['kept']);
    LogBuffer().verbose = true;
    log.d('kept too');
    expect(LogBuffer().entries, hasLength(2));
  });

  test('buffer is bounded', () {
    LogBuffer().verbose = true;
    const log = AppLogger('Test');
    for (var i = 0; i < 600; i++) {
      log.i('$i');
    }
    expect(LogBuffer().entries, hasLength(500));
    expect(LogBuffer().entries.first.message, '100');
  });
}
