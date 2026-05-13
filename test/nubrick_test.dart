import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubrick_flutter/channel/nubrick_flutter_platform_interface.dart';
import 'package:nubrick_flutter/nubrick_flutter.dart';
import 'package:nubrick_flutter/src/runtime.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakeNubrickFlutterPlatform extends NubrickFlutterPlatform
    with MockPlatformInterfaceMixin {
  int recordedCrashCount = 0;
  final List<String> connectedProjectIds = [];
  String? connectClientResult = 'ok';
  Object? connectClientError;

  @override
  Future<String?> connectClient(String projectId) async {
    connectedProjectIds.add(projectId);
    if (connectClientError != null) {
      throw connectClientError!;
    }
    return connectClientResult;
  }

  @override
  Future<void> recordCrash(Map<String, dynamic> errorData) async {
    recordedCrashCount += 1;
  }
}

Future<void> _sendMethodChannelCall(String method, [dynamic arguments]) async {
  final completer = Completer<void>();
  final message = const StandardMethodCodec().encodeMethodCall(
    MethodCall(method, arguments),
  );

  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('nubrick_flutter', message, (_) {
    completer.complete();
  });

  await completer.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Nubrick', () {
    late NubrickFlutterPlatform originalPlatform;
    late FlutterExceptionHandler? originalFlutterErrorHandler;
    late bool Function(Object, StackTrace)? originalPlatformErrorHandler;
    late DebugPrintCallback originalDebugPrint;
    late _FakeNubrickFlutterPlatform fakePlatform;
    late List<String> debugLogs;

    setUp(() {
      Nubrick.resetForTest();
      originalPlatform = NubrickFlutterPlatform.instance;
      originalFlutterErrorHandler = FlutterError.onError;
      originalPlatformErrorHandler = PlatformDispatcher.instance.onError;
      originalDebugPrint = debugPrint;
      debugLogs = [];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          debugLogs.add(message);
        }
      };
      fakePlatform = _FakeNubrickFlutterPlatform();
      NubrickFlutterPlatform.instance = fakePlatform;
    });

    tearDown(() {
      Nubrick.resetForTest();
      NubrickFlutterPlatform.instance = originalPlatform;
      FlutterError.onError = originalFlutterErrorHandler;
      PlatformDispatcher.instance.onError = originalPlatformErrorHandler;
      debugPrint = originalDebugPrint;
    });

    test('repeated identical initialization is a no-op', () async {
      Nubrick.initialize('project-a');
      Nubrick.initialize('project-a');

      FlutterError.onError?.call(
        FlutterErrorDetails(
          exception: Exception('test'),
          stack: StackTrace.current,
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(Nubrick.projectId, 'project-a');
      expect(fakePlatform.connectedProjectIds, ['project-a']);
      expect(fakePlatform.recordedCrashCount, 1);
      expect(
        debugLogs,
        contains(
          'Nubrick.initialize(...) called more than once. '
          'Subsequent calls are ignored.',
        ),
      );
    });

    test('repeated initialization with a different config is ignored', () {
      Nubrick.initialize('project-a');
      Nubrick.initialize('project-b', trackCrashes: false);

      expect(Nubrick.projectId, 'project-a');
      expect(fakePlatform.connectedProjectIds, ['project-a']);
      expect(nubrickRuntime.isInitialized, isTrue);
      expect(
        debugLogs,
        contains(
          'Nubrick.initialize(...) called more than once. '
          'Subsequent calls are ignored.',
        ),
      );
    });

    test('ignores empty project id safely', () {
      Nubrick.initialize('   ');

      expect(nubrickRuntime.isInitialized, isFalse);
      expect(fakePlatform.connectedProjectIds, isEmpty);
      expect(
        debugLogs,
        contains(
          'Nubrick.initialize(...) ignored because projectId is empty.',
        ),
      );
    });

    test('rolls back initialization when native setup rejects the project', () async {
      fakePlatform.connectClientResult = 'no';

      Nubrick.initialize('project-a');
      await Future<void>.delayed(Duration.zero);

      expect(nubrickRuntime.isInitialized, isFalse);
      expect(() => Nubrick.projectId, throwsStateError);
      expect(
        debugLogs,
        contains(
          'Nubrick.initialize(...) failed during native setup. '
          'connectClient returned "no". Initialization has been rolled back.',
        ),
      );
    });

    test('rolls back initialization when native setup throws', () async {
      fakePlatform.connectClientError = Exception('native setup failed');

      Nubrick.initialize('project-a');
      await Future<void>.delayed(Duration.zero);

      expect(nubrickRuntime.isInitialized, isFalse);
      expect(() => Nubrick.projectId, throwsStateError);
      expect(
        debugLogs.single,
        contains('Nubrick.initialize(...) failed during native setup.'),
      );
      expect(debugLogs.single, contains('native setup failed'));
    });

    test('deprecated constructor initializes the singleton runtime', () {
      // ignore: deprecated_member_use_from_same_package
      final plugin = Nubrick('project-a');

      expect(Nubrick.projectId, 'project-a');
      expect(fakePlatform.connectedProjectIds, ['project-a']);
      expect(plugin, same(Nubrick.instance));
      expect(plugin.trackCrashes, isTrue);
    });

    test('deprecated instance trackCrashes reflects initialization config', () {
      // ignore: deprecated_member_use_from_same_package
      final plugin = Nubrick('project-a', trackCrashes: false);

      expect(plugin.trackCrashes, isFalse);
    });

    test('deprecated instance getter is null before initialize', () {
      // ignore: deprecated_member_use_from_same_package
      expect(Nubrick.instance, isNull);
    });

    test('ensureInitialized throws before initialize', () {
      expect(nubrickRuntime.isInitialized, isFalse);
      expect(nubrickRuntime.ensureInitialized, throwsStateError);
    });

    test('routes on-event from method channel to listeners', () async {
      Nubrick.initialize('project-a');

      Event? receivedEvent;
      Nubrick.addEventListener((event) {
        receivedEvent = event;
      });

      await _sendMethodChannelCall('on-event', {
        'name': 'signup_completed',
        'deepLink': 'app://checkout',
        'payload': [
          {'name': 'plan', 'value': 'pro', 'type': 'STRING'},
          {'name': 'seats', 'value': '3', 'type': 'INTEGER'},
        ],
      });

      expect(receivedEvent, isNotNull);
      expect(receivedEvent?.name, 'signup_completed');
      expect(receivedEvent?.deepLink, 'app://checkout');
      expect(receivedEvent?.payload, hasLength(2));
      expect(receivedEvent?.payload?[0].name, 'plan');
      expect(receivedEvent?.payload?[0].value, 'pro');
      expect(receivedEvent?.payload?[0].type, EventPayloadType.string);
      expect(receivedEvent?.payload?[1].name, 'seats');
      expect(receivedEvent?.payload?[1].value, '3');
      expect(receivedEvent?.payload?[1].type, EventPayloadType.integer);
    });

    test('ignores malformed on-event payloads safely', () async {
      Nubrick.initialize('project-a');

      var listenerCalled = false;
      Nubrick.addEventListener((_) {
        listenerCalled = true;
      });

      await expectLater(
        _sendMethodChannelCall('on-event', 'unexpected payload'),
        completes,
      );

      expect(listenerCalled, isFalse);
    });

    test('routes on-dispatch from method channel to listeners', () async {
      Nubrick.initialize('project-a');

      String? dispatchedName;
      Nubrick.addOnDispatchListener((name) {
        dispatchedName = name;
      });

      await _sendMethodChannelCall('on-dispatch', {
        'name': 'checkout_opened',
      });

      expect(dispatchedName, 'checkout_opened');
    });

    test('routes on-tooltip from method channel to listeners', () async {
      Nubrick.initialize('project-a');

      String? tooltipData;
      String? tooltipExperimentId;
      Nubrick.addOnTooltipListener((data, experimentId) {
        tooltipData = data;
        tooltipExperimentId = experimentId;
      });

      await _sendMethodChannelCall('on-tooltip', {
        'data': '{"step":1}',
        'experimentId': 'exp-123',
      });

      expect(tooltipData, '{"step":1}');
      expect(tooltipExperimentId, 'exp-123');
    });
  });
}
