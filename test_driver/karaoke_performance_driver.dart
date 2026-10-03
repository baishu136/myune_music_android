import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';

// Preserve measurements even when a device misses the budget. A failed budget
// assertion is performance evidence, not a reason to discard the timeline.
Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  responseDataCallback: (data) => writeResponseData(
    data,
    destinationDirectory: Platform.environment['MYUNE_PERF_DIR'] ?? 'build',
    testOutputFilename:
        Platform.environment['MYUNE_PERF_RUN'] ?? 'karaoke_performance',
  ),
);
