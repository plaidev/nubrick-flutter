import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubrick_flutter/crash_report.dart';
import 'package:stack_trace/stack_trace.dart';

void main() {
  group('Stack Trace Parsing', () {
    test('parses simple package URI stack trace', () {
      // Create a real stack trace by throwing an exception
      StackTrace? capturedStack;
      try {
        throw Exception('Test exception');
      } catch (e, stack) {
        capturedStack = stack;
      }

      expect(capturedStack, isNotNull);

      // Parse the stack trace using the Trace library
      final trace = Trace.from(capturedStack);
      expect(trace.frames, isNotEmpty);

      // Verify we can access frame properties
      final firstFrame = trace.frames.first;
      expect(firstFrame.uri, isNotNull);
      expect(firstFrame.member, isNotNull);
    });

    test('parses stack trace with package path containing slash', () {
      // Simulate a stack trace string with package path
      const stackTraceString = '''
#0      main.<anonymous closure> (package:nubrick_flutter/crash_report_test.dart:120:9)
#1      _rootRun (dart:async/zone.dart:1428:47)
#2      _CustomZone.run (dart:async/zone.dart:1328:19)
''';

      final trace = Trace.parse(stackTraceString);
      expect(trace.frames.length, greaterThanOrEqualTo(3));

      final firstFrame = trace.frames.first;
      final uriString = firstFrame.uri.toString();

      // Verify URI parsing
      expect(uriString, contains('package:nubrick_flutter'));
      expect(uriString, contains('/'));

      // Test URI splitting logic (simulating what crash_report.dart does)
      String? className;
      String? fileName;

      if (uriString.contains('/')) {
        final slashIndex = uriString.indexOf('/');
        className = uriString.substring(0, slashIndex);
        fileName = uriString.substring(slashIndex + 1);
      }

      expect(className, 'package:nubrick_flutter');
      expect(fileName, 'crash_report_test.dart');
    });

    test('parses stack trace with multi-level package path', () {
      const stackTraceString = '''
#0      foo (package:my_package/sub/folder/file.dart:10:5)
''';

      final trace = Trace.parse(stackTraceString);
      final frame = trace.frames.first;
      final uriString = frame.uri.toString();

      // Test that only the first slash is used for splitting
      String? className;
      String? fileName;

      if (uriString.contains('/')) {
        final slashIndex = uriString.indexOf('/');
        className = uriString.substring(0, slashIndex);
        fileName = uriString.substring(slashIndex + 1);
      }

      expect(className, 'package:my_package');
      expect(fileName, 'sub/folder/file.dart');
    });

    test('parses stack trace without slash in URI', () {
      const stackTraceString = '''
#0      main (dart:core:10:5)
''';

      final trace = Trace.parse(stackTraceString);
      final frame = trace.frames.first;
      final uriString = frame.uri.toString();

      // Verify the fallback case when there's no '/'
      String? fileName;

      if (uriString.contains('/')) {
        final slashIndex = uriString.indexOf('/');
        fileName = uriString.substring(slashIndex + 1);
      } else {
        fileName = uriString;
      }

      expect(fileName, isNotNull);
    });

    test('extracts method name from member with dot notation', () {
      const stackTraceString = '''
#0      MyClass.myMethod (package:test/file.dart:10:5)
''';

      final trace = Trace.parse(stackTraceString);
      final frame = trace.frames.first;

      expect(frame.member, 'MyClass.myMethod');

      // Test method name extraction logic
      String? methodName = frame.member;
      if (frame.member != null && frame.member!.contains('.')) {
        final parts = frame.member!.split('.');
        if (parts.isNotEmpty) {
          methodName = parts.last;
        }
      }

      expect(methodName, 'myMethod');
    });

    test('handles member without dot notation', () {
      const stackTraceString = '''
#0      main (package:test/file.dart:10:5)
''';

      final trace = Trace.parse(stackTraceString);
      final frame = trace.frames.first;

      expect(frame.member, 'main');

      // Test method name extraction logic
      String? methodName = frame.member;
      if (frame.member != null && frame.member!.contains('.')) {
        final parts = frame.member!.split('.');
        if (parts.isNotEmpty) {
          methodName = parts.last;
        }
      }

      expect(methodName, 'main');
    });

    test('handles anonymous closures', () {
      const stackTraceString = '''
#0      main.<anonymous closure> (package:test/file.dart:10:5)
''';

      final trace = Trace.parse(stackTraceString);
      final frame = trace.frames.first;

      // Stack trace library may represent closures as <fn> or <anonymous closure>
      expect(frame.member, anyOf(contains('<fn>'), contains('<anonymous closure>')));

      // Test method name extraction for closures
      String? methodName = frame.member;
      if (frame.member != null && frame.member!.contains('.')) {
        final parts = frame.member!.split('.');
        if (parts.isNotEmpty) {
          methodName = parts.last;
        }
      }

      expect(methodName, anyOf(equals('<fn>'), equals('<anonymous closure>')));
    });

    test('parses line numbers from stack trace', () {
      const stackTraceString = '''
#0      foo (package:test/file.dart:42:10)
#1      bar (package:test/file.dart:100:5)
''';

      final trace = Trace.parse(stackTraceString);

      expect(trace.frames[0].line, 42);
      expect(trace.frames[1].line, 100);
    });
  });

  group('Deprecated NubrickCrashReport', () {
    test('singleton instance returns same object', () {
      final instance1 = NubrickCrashReport.instance;
      final instance2 = NubrickCrashReport.instance;
      final instance3 = NubrickCrashReport();

      expect(instance1, same(instance2));
      expect(instance1, same(instance3));
    });

    test('recordFlutterError does not throw', () async {
      final crashReport = NubrickCrashReport.instance;

      await expectLater(
        crashReport.recordFlutterError(
          FlutterErrorDetails(exception: Exception('test')),
        ),
        completes,
      );
    });

    test('recordPlatformError does not throw', () async {
      final crashReport = NubrickCrashReport.instance;

      await expectLater(
        crashReport.recordPlatformError(
          Exception('test'),
          StackTrace.current,
        ),
        completes,
      );
    });
  });
}
