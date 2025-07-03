import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

const String logLevelString =
    String.fromEnvironment('LOG_LEVEL', defaultValue: 'debug');

Level getLogLevelFromString(String level) {
  switch (level.toLowerCase()) {
    case 'debug':
      return Level.debug;
    case 'info':
      return Level.info;
    case 'warning':
      return Level.warning;
    case 'error':
      return Level.error;
    default:
      return Level.debug;
  }
}

final Level configuredLogLevel = getLogLevelFromString(logLevelString);

class LevelFilter extends LogFilter {
  final Level minLevel;

  LevelFilter({this.minLevel = Level.debug});

  @override
  bool shouldLog(LogEvent event) {
    return event.level.index >= minLevel.index;
  }
}

final appLoggerProvider = Provider<Logger>((ref) {
  debugPrint('[DEBUG] Configured log level: $configuredLogLevel');
  return Logger(
    filter: LevelFilter(minLevel: configuredLogLevel),
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );
});

