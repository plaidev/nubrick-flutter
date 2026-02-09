import 'package:flutter/foundation.dart';
import 'package:nubrick_flutter/channel/nubrick_flutter_platform_interface.dart';
import 'package:nubrick_flutter/version.dart';
import 'package:stack_trace/stack_trace.dart';

/// Represents a single stack frame in a crash report.
///
/// This structure matches the Android SDK format for consistency.
class _StackFrame {
  final String? fileName;
  final String? className;
  final String? methodName;
  final int? lineNumber;

  _StackFrame({
    this.fileName,
    this.className,
    this.methodName,
    this.lineNumber,
  });

  Map<String, dynamic> toMap() {
    return {
      'fileName': fileName,
      'className': className,
      'methodName': methodName,
      'lineNumber': lineNumber,
    };
  }
}

/// Represents an exception record in a crash report.
///
/// This structure matches the Android SDK format for consistency.
class _ExceptionRecord {
  final String? type;
  final String? message;
  final List<_StackFrame>? callStacks;

  _ExceptionRecord({
    this.type,
    this.message,
    this.callStacks,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'message': message,
      'callStacks': callStacks?.map((frame) => frame.toMap()).toList(),
    };
  }
}

/// Parses a stack trace and converts it to a list of _StackFrame objects.
List<_StackFrame> _parseStackTrace(StackTrace? stackTrace) {
    if (stackTrace == null) return [];

    try {
      final trace = Trace.from(stackTrace);
      final frames = trace.frames.map((frame) {
        // Flutter/Dart stack traces have URIs like "package:nubrick_flutter/nubrick_flutter.dart"
        // Split on first '/' to get module name (package:nubrick_flutter) and file name (nubrick_flutter.dart)
        String uriString = frame.uri.toString();
        String? className;
        String? fileName;

        if (uriString.contains('/')) {
          final slashIndex = uriString.indexOf('/');
          className = uriString.substring(0, slashIndex);
          fileName = uriString.substring(slashIndex + 1);
        } else {
          // No slash, use whole URI as fileName
          fileName = uriString;
        }

        String? methodName = frame.member;

        // Extract just the method name if member contains a dot
        if (frame.member != null && frame.member!.contains('.')) {
          final parts = frame.member!.split('.');
          if (parts.isNotEmpty) {
            methodName = parts.last;
          }
        }

        return _StackFrame(
          fileName: fileName,
          className: className,
          methodName: methodName,
          lineNumber: frame.line,
        );
      }).toList();

      return frames;
    } catch (e) {
      debugPrint('Error parsing stack trace: $e');
      return [];
    }
  }

/// Severity level for error reporting.
enum ErrorSeverity { crash, warning }

/// Records an error with stack trace at the specified severity level.
///
/// - [error]: The error object to record
/// - [stackTrace]: The stack trace associated with the error
/// - [severity]: The severity level (defaults to [ErrorSeverity.crash])
Future<void> recordError(
  Object error,
  StackTrace stackTrace, {
  ErrorSeverity severity = ErrorSeverity.crash,
}) async {
  try {
    final exceptionRecord = _ExceptionRecord(
      type: error.runtimeType.toString(),
      message: error.toString(),
      callStacks: _parseStackTrace(stackTrace),
    );

    final Map<String, dynamic> errorData = {
      'exceptions': [exceptionRecord.toMap()],
      'flutterSdkVersion': nubrickFlutterSdkVersion,
      'severity': severity.name,
    };

    await NubrickFlutterPlatform.instance.recordCrash(errorData);
  } catch (e) {
    // Silently handle any errors in the crash reporting itself
  }
}

/// A class to handle crash reporting in Flutter applications.
///
/// **DEPRECATED**: Crash reporting is now handled automatically by the SDK.
/// Simply initialize NubrickFlutter and crash reporting will be enabled by default.
///
/// If you need to disable crash reporting, use:
/// ```dart
/// NubrickFlutter("PROJECT_ID", trackCrashes: false);
/// ```
@Deprecated(
  'Crash reporting is now automatic. '
  'Remove manual crash reporting setup and the SDK will handle it automatically. '
  'This class will be removed in a future version.'
)
class NubrickCrashReport {
  static final NubrickCrashReport _instance = NubrickCrashReport._();

  static NubrickCrashReport get instance => _instance;

  NubrickCrashReport._();

  factory NubrickCrashReport() => _instance;

  @Deprecated(
    'Crash reporting is now automatic. '
    'Remove this call and the SDK will handle crash reporting automatically.'
  )
  Future<void> recordFlutterError(FlutterErrorDetails errorDetails) async {}

  @Deprecated(
    'Crash reporting is now automatic. '
    'Remove this call and the SDK will handle crash reporting automatically.'
  )
  Future<void> recordPlatformError(Object error, StackTrace stackTrace) async {}
}
