import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/fault_log_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('fault reports use date folders and time-based file names', () {
    final temporary = Directory.systemTemp.createTempSync('myune_fault_test_');
    addTearDown(() => temporary.deleteSync(recursive: true));
    final store = FaultLogStore(temporary);
    final timestamp = DateTime(2026, 8, 22, 19, 16, 7, 23);

    final report = store.write(
      timestamp: timestamp,
      source: 'test exception',
      error: StateError('expected failure'),
      stackTrace: StackTrace.fromString('frame one\nframe two'),
    );

    expect(p.basename(report.parent.path), '26.8.22');
    expect(p.basename(report.path), '19.16.07.023.log');
    final contents = report.readAsStringSync();
    expect(contents, contains('Myune Music fault report'));
    expect(contents, contains('Source: test exception'));
    expect(contents, contains('Bad state: expected failure'));
    expect(contents, contains('frame one'));
  });

  test('same-millisecond reports never overwrite one another', () {
    final temporary = Directory.systemTemp.createTempSync('myune_fault_test_');
    addTearDown(() => temporary.deleteSync(recursive: true));
    final store = FaultLogStore(temporary);
    final timestamp = DateTime(2026, 8, 22, 19, 16, 7, 23);

    File write() => store.write(
      timestamp: timestamp,
      source: 'collision test',
      error: Exception('failure'),
      stackTrace: StackTrace.empty,
    );

    final first = write();
    final second = write();
    expect(first.path, isNot(second.path));
    expect(first.existsSync(), isTrue);
    expect(second.existsSync(), isTrue);
  });
}
