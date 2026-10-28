import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubrick_flutter/channel/nubrick_flutter_platform_interface.dart';
import 'package:nubrick_flutter/channel/nubrick_flutter_method_channel.dart';
import 'package:nubrick_flutter/nubrick_flutter.dart';
import 'package:nubrick_flutter/src/runtime.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakeNubrickFlutterPlatform extends NubrickFlutterPlatform
    with MockPlatformInterfaceMixin {
  int recordedCrashCount = 0;
  final List<String> connectedProjectIds = [];
  final List<String> dispatchedEvents = [];
  final List<Map<String, Object>> dispatchedProperties = [];
  String? connectClientResult = 'ok';
  Object? connectClientError;
  Completer<String?>? connectClientCompleter;

  @override
  Future<String?> connectClient(String projectId) async {
    connectedProjectIds.add(projectId);
    if (connectClientCompleter != null) {
      return connectClientCompleter!.future;
    }
    if (connectClientError != null) {
      throw connectClientError!;
    }
    return connectClientResult;
  }

  @override
  Future<String?> dispatch(String name) async {
    dispatchedEvents.add(name);
    return 'ok';
  }

  @override
  Future<String?> dispatchWithProperties(
      String name, Map<String, Object> properties) async {
    dispatchedEvents.add(name);
    dispatchedProperties.add(properties);
    return 'ok';
  }

  @override
  Future<void> recordCrash(Map<String, dynamic> errorData) async {
    recordedCrashCount += 1;
  }
}

Future<dynamic> _sendMethodChannelCall(String method,
    [dynamic arguments]) async {
  final completer = Completer<dynamic>();
  final message = const StandardMethodCodec().encodeMethodCall(
    MethodCall(method, arguments),
  );

  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('nubrick_flutter', message, (reply) {
    completer.complete(reply == null
        ? null
        : const StandardMethodCodec().decodeEnvelope(reply));
  });

  return completer.future;
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

    test('async platform calls fail immediately before initialization',
        () async {
      final dispatchFuture = NubrickDispatcher.instance.dispatch(
        NubrickEvent('checkout_opened'),
      );

      await expectLater(dispatchFuture, throwsStateError);
      expect(fakePlatform.connectedProjectIds, isEmpty);
      expect(fakePlatform.dispatchedEvents, isEmpty);
    });

    test('async platform calls wait for native initialization readiness',
        () async {
      fakePlatform.connectClientCompleter = Completer<String?>();

      Nubrick.initialize('project-a');
      final dispatchFuture = NubrickDispatcher.instance.dispatch(
        NubrickEvent('checkout_opened'),
      );

      await Future<void>.delayed(Duration.zero);

      expect(fakePlatform.connectedProjectIds, ['project-a']);
      expect(fakePlatform.dispatchedEvents, isEmpty);

      fakePlatform.connectClientCompleter!.complete('ok');
      await dispatchFuture;

      expect(fakePlatform.dispatchedEvents, ['checkout_opened']);
    });

    test('ready platform calls do not wait for another async turn', () async {
      Nubrick.initialize('project-a');
      await Nubrick.ready;

      final dispatchFuture = NubrickDispatcher.instance.dispatch(
        NubrickEvent('checkout_opened'),
      );

      expect(fakePlatform.dispatchedEvents, ['checkout_opened']);
      await dispatchFuture;
    });

    test('async platform calls fail if native initialization rolls back',
        () async {
      fakePlatform.connectClientCompleter = Completer<String?>();

      Nubrick.initialize('project-a');
      final dispatchFuture = NubrickDispatcher.instance.dispatch(
        NubrickEvent('checkout_opened'),
      );

      await Future<void>.delayed(Duration.zero);
      fakePlatform.connectClientCompleter!.complete('no');

      await expectLater(dispatchFuture, throwsStateError);
      expect(fakePlatform.dispatchedEvents, isEmpty);
      expect(nubrickRuntime.isInitialized, isFalse);
    });

    testWidgets('async platform calls fail if native initialization times out',
        (tester) async {
      fakePlatform.connectClientCompleter = Completer<String?>();

      Nubrick.initialize('project-a');
      final dispatchFuture = NubrickDispatcher.instance.dispatch(
        NubrickEvent('checkout_opened'),
      );
      final dispatchExpectation = expectLater(dispatchFuture, throwsStateError);

      await tester.pump(NubrickRuntime.initializationTimeout);
      await tester.pump();

      await dispatchExpectation;
      expect(fakePlatform.dispatchedEvents, isEmpty);
      expect(nubrickRuntime.isInitialized, isFalse);
      expect(debugLogs.single, contains('TimeoutException'));
      debugPrint = originalDebugPrint;
    });

    test('stale native initialization completion does not reset newer runtime',
        () async {
      fakePlatform.connectClientCompleter = Completer<String?>();
      final staleConnectClientCompleter = fakePlatform.connectClientCompleter!;

      Nubrick.initialize('project-a');
      await Future<void>.delayed(Duration.zero);

      Nubrick.resetForTest();
      fakePlatform.connectClientCompleter = Completer<String?>();
      final currentConnectClientCompleter =
          fakePlatform.connectClientCompleter!;

      Nubrick.initialize('project-b');
      await Future<void>.delayed(Duration.zero);

      currentConnectClientCompleter.complete('ok');
      await Nubrick.ready;

      staleConnectClientCompleter.complete('ok');
      await Future<void>.delayed(Duration.zero);

      expect(fakePlatform.connectedProjectIds, ['project-a', 'project-b']);
      expect(nubrickRuntime.isInitialized, isTrue);
      expect(Nubrick.projectId, 'project-b');
    });

    test('rolls back initialization when native setup rejects the project',
        () async {
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

    test('ready throws before initialize', () async {
      expect(nubrickRuntime.isInitialized, isFalse);
      await expectLater(nubrickRuntime.ready, throwsStateError);
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

    test('dispatches a snapshot of typed event properties', () async {
      Nubrick.initialize('project-a');
      await Nubrick.ready;

      final input = <String, Object>{
        'count': 3,
        'price': 12.5,
        'active': true,
        'label': 'checkout',
        'at': DateTime.utc(2026, 10, 27, 1, 2, 3, 456, 789),
        'invalid': double.nan,
      };
      final event = NubrickEvent('purchase', properties: input);
      input['count'] = 9;

      await NubrickDispatcher.instance.dispatch(event);

      expect(fakePlatform.dispatchedEvents, ['purchase']);
      expect(fakePlatform.dispatchedProperties.single, {
        'count': 3,
        'price': 12.5,
        'active': true,
        'label': 'checkout',
        'at': DateTime.utc(2026, 10, 27, 1, 2, 3, 456, 789),
      });
      expect(() => event.properties['count'] = 4, throwsUnsupportedError);
    });

    test('encodes typed properties on the method channel', () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('nubrick_flutter');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return 'ok';
      });
      try {
        final platform = MethodChannelNubrickFlutter();
        await platform.dispatch('plain');
        final event = NubrickEvent('purchase', properties: {
          'count': 3,
          'minInt64': -9223372036854775807 - 1,
          'maxInt64': 9223372036854775807,
          'price': 12.5,
          'minFloat64': double.minPositive,
          'maxFloat64': double.maxFinite,
          'active': true,
          'label': 'checkout',
          'at': DateTime.utc(2026, 10, 27, 1, 2, 3, 456, 789),
        });
        await platform.dispatchWithProperties(event.name, event.properties);

        expect(calls[0].arguments, 'plain');
        expect(calls[1].arguments, {
          'name': 'purchase',
          'properties': {
            'count': {'type': 'integer', 'value': 3},
            'minInt64': {'type': 'integer', 'value': -9223372036854775807 - 1},
            'maxInt64': {'type': 'integer', 'value': 9223372036854775807},
            'price': {'type': 'float', 'value': 12.5},
            'minFloat64': {'type': 'float', 'value': double.minPositive},
            'maxFloat64': {'type': 'float', 'value': double.maxFinite},
            'active': {'type': 'boolean', 'value': true},
            'label': {'type': 'string', 'value': 'checkout'},
            'at': {
              'type': 'timestamp',
              'value': '2026-10-27T01:02:03.456789Z',
            },
          },
        });
      } finally {
        messenger.setMockMethodCallHandler(channel, null);
      }
    });

    test('rejects native tooltip delivery when no overlay is listening',
        () async {
      Nubrick.initialize('project-a');
      Nubrick.addOnTooltipListener((data, experimentId) {});
      final accepted = await _sendMethodChannelCall('on-tooltip', {
        'data': '{"id":"native-session"}',
        'experimentId': 'exp',
        'variantId': 'variant',
      });
      expect(accepted, false);
    });

    test('routes on-tooltip from method channel to listeners', () async {
      Nubrick.initialize('project-a');

      String? tooltipData;
      String? tooltipExperimentId;
      String? tooltipVariantId;
      Nubrick.addOnTooltipListener((data, experimentId) {
        tooltipData = data;
        tooltipExperimentId = experimentId;
      });
      nubrickRuntime
          .addInternalTooltipListener((data, experimentId, variantId, sessionId) {
        tooltipVariantId = variantId;
        expect(sessionId, 'session-789');
      });

      await _sendMethodChannelCall('on-tooltip', {
        'data': '{"step":1}',
        'experimentId': 'exp-123',
        'variantId': 'var-456',
        'sessionId': 'session-789',
      });

      expect(tooltipData, '{"step":1}');
      expect(tooltipExperimentId, 'exp-123');
      expect(tooltipVariantId, 'var-456');
    });
  });
}
