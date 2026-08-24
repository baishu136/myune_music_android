import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

String faultLogDateFolder(DateTime timestamp) =>
    '${timestamp.year % 100}.${timestamp.month}.${timestamp.day}';

String faultLogFileName(DateTime timestamp) =>
    '${timestamp.hour.toString().padLeft(2, '0')}.'
    '${timestamp.minute.toString().padLeft(2, '0')}.'
    '${timestamp.second.toString().padLeft(2, '0')}.'
    '${timestamp.millisecond.toString().padLeft(3, '0')}.log';

class FaultLogStore {
  FaultLogStore(this.rootDirectory);

  final Directory rootDirectory;

  File write({
    required DateTime timestamp,
    required String source,
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> details = const {},
  }) {
    final dateDirectory = Directory(
      p.join(rootDirectory.path, faultLogDateFolder(timestamp)),
    )..createSync(recursive: true);
    var target = File(p.join(dateDirectory.path, faultLogFileName(timestamp)));
    var collision = 1;
    while (target.existsSync()) {
      final name = p.basenameWithoutExtension(faultLogFileName(timestamp));
      target = File(p.join(dateDirectory.path, '${name}_$collision.log'));
      collision++;
    }
    final report = StringBuffer()
      ..writeln('Myune Music fault report')
      ..writeln('Timestamp: ${timestamp.toIso8601String()}')
      ..writeln('Source: $source')
      ..writeln('Platform: ${Platform.operatingSystem}')
      ..writeln('OS version: ${Platform.operatingSystemVersion}')
      ..writeln('Process ID: $pid');
    for (final entry in details.entries) {
      final value = entry.value;
      if (value != null && value.toString().trim().isNotEmpty) {
        report.writeln('${entry.key}: $value');
      }
    }
    report
      ..writeln()
      ..writeln('Exception type: ${error.runtimeType}')
      ..writeln('Exception: $error')
      ..writeln()
      ..writeln('Stack trace:')
      ..writeln(stackTrace);
    target.writeAsStringSync(report.toString(), flush: true);
    return target;
  }
}

class FaultLogService {
  FaultLogService._();

  static final FaultLogService instance = FaultLogService._();
  static const MethodChannel _androidChannel = MethodChannel(
    'com.myune.music/fault_log',
  );

  FaultLogStore? _store;
  bool _handlersInstalled = false;
  String? _directoryPath;

  String? get directoryPath => _directoryPath;

  Future<void> refreshDirectory() async {
    _store = null;
    _directoryPath = null;
    await initialize();
  }

  Future<void> initialize() async {
    if (_store != null) return;
    try {
      Directory? directory;
      if (Platform.isAndroid) {
        try {
          final path = await _androidChannel.invokeMethod<String>('initialize');
          if (path != null && path.isNotEmpty) directory = Directory(path);
        } catch (_) {
          // Fall through to the permission-free app-private directory.
        }
      }
      directory ??= await _fallbackDirectory();
      try {
        directory.createSync(recursive: true);
        _directoryPath = directory.path;
        _store = FaultLogStore(directory);
      } catch (_) {
        final emergency = Directory.systemTemp.createTempSync(
          'myune_fault_log_',
        );
        _directoryPath = emergency.path;
        _store = FaultLogStore(emergency);
      }
    } catch (_) {
      // Initialization itself must never prevent the first Flutter frame.
      try {
        final documents = await getApplicationDocumentsDirectory();
        final directory = Directory(p.join(documents.path, 'myune fault log'))
          ..createSync(recursive: true);
        _directoryPath = directory.path;
        _store = FaultLogStore(directory);
      } catch (_) {
        final emergency = Directory.systemTemp.createTempSync(
          'myune_fault_log_',
        );
        _directoryPath = emergency.path;
        _store = FaultLogStore(emergency);
      }
    }
  }

  Future<Directory> _fallbackDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory(p.join(documents.path, 'myune fault log'));
  }

  Future<void> markStartup(String marker) async {
    if (!Platform.isAndroid) return;
    try {
      await _androidChannel.invokeMethod<void>('breadcrumb', <String, Object?>{
        'marker': marker,
      });
    } catch (_) {
      // Breadcrumbs are diagnostic only and must never affect startup.
    }
  }

  void installFlutterHandlers() {
    if (_handlersInstalled) return;
    _handlersInstalled = true;
    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      recordFlutterError(details);
    };
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      recordSync(
        source: 'Dart asynchronous uncaught exception',
        error: error,
        stackTrace: stackTrace,
      );
      return previousPlatformHandler?.call(error, stackTrace) ?? false;
    };
  }

  void recordFlutterError(FlutterErrorDetails details) {
    String? diagnostics;
    try {
      diagnostics = details.informationCollector
          ?.call()
          .map((node) => node.toString())
          .join('\n');
    } catch (_) {
      diagnostics = null;
    }
    recordSync(
      source: 'Flutter framework exception',
      error: details.exception,
      stackTrace: details.stack ?? StackTrace.current,
      details: {
        'Library': details.library,
        'Context': details.context,
        'Diagnostics': diagnostics,
      },
    );
  }

  void recordSync({
    required String source,
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> details = const {},
  }) {
    try {
      _store?.write(
        timestamp: DateTime.now(),
        source: source,
        error: error,
        stackTrace: stackTrace,
        details: details,
      );
    } catch (writeError, writeStack) {
      debugPrint('Unable to write Myune fault report: $writeError');
      debugPrintStack(stackTrace: writeStack);
    }
  }
}
