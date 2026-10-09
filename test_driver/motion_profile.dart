import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 3),
  writeResponseOnFailure: true,
  responseDataCallback: (data) => writeResponseData(
    data,
    destinationDirectory: Platform.environment['MYUNE_PROFILE_OUTPUT'],
    testOutputFilename: 'frame_timings',
  ),
);
