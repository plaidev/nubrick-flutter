import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubrick_flutter/channel/nubrick_flutter_method_channel.dart';
import 'package:nubrick_flutter/channel/nubrick_flutter_platform_interface.dart';
import 'package:nubrick_flutter/nubrick_flutter.dart';
import 'package:nubrick_flutter/schema/generated.dart';
import 'package:nubrick_flutter/tooltip/overlay.dart';

class _TooltipPlatform extends NubrickFlutterPlatform {
  final displays = <(String, String)>[];
  final connections = <String>[];
  final rootIds = <String?>[];
  final disconnections = <String>[];
  final stops = <String>[];
  String? connectResult = 'ok';
  Completer<String?>? pendingConnection;
  Completer<void>? pendingRecording;
  bool failConnection = false;
  bool failDispatch = false;
  final dispatches = <String>[];

  @override
  Future<String?> connectClient(String projectId) async => 'ok';

  @override
  Future<String?> connectTooltipEmbedding(String channelId, String experimentId,
      String? variantId, UIRootBlock rootBlock) async {
    connections.add(channelId);
    rootIds.add(rootBlock.id);
    if (failConnection) throw PlatformException(code: 'connect-failed');
    if (pendingConnection != null) return pendingConnection!.future;
    return connectResult;
  }

  @override
  Future<void> appendTooltipExperimentHistory(
      String experimentId, String variantId,
      {required String channelId}) async {
    displays.add((experimentId, variantId));
    if (pendingRecording != null) await pendingRecording!.future;
  }

  @override
  Future<void> callTooltipEmbeddingDispatch(
      String channelId, UIBlockAction event) async {
    dispatches.add(channelId);
    if (failDispatch) throw PlatformException(code: 'dispatch-failed');
  }

  @override
  Future<String?> disconnectTooltipEmbedding(String channelId,
      {required bool stoppedByFlutter}) async {
    if (stoppedByFlutter) stops.add(channelId);
    disconnections.add(channelId);
    return 'ok';
  }
}

int _sessionId = 0;
String _tooltipPayload() => jsonEncode(UIRootBlock(
      id: 'tooltip-root',
      data: UIRootBlockData(currentPageId: 'trigger', pages: [
        UIPageBlock(
          id: 'trigger',
          data: UIPageBlockData(
            triggerSetting: TriggerSetting(
              onTrigger: UIBlockAction(destinationPageId: 'tooltip'),
            ),
          ),
        ),
        for (final id in ['tooltip', 'next'])
          UIPageBlock(
            id: id,
            data: UIPageBlockData(
              kind: PageKind.TOOLTIP,
              tooltipAnchor: 'anchor',
              tooltipSize: UITooltipSize(width: 100, height: 50),
              tooltipTransitionTarget: UITooltipTransitionTarget.SCREEN,
              triggerSetting: TriggerSetting(
                onTrigger: UIBlockAction(destinationPageId: 'next'),
              ),
            ),
          ),
      ]),
    ).encode());

Future<void> _send(String channel, String method, [dynamic arguments]) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    channel,
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
    (_) {},
  );
}

Future<void> _trigger({String? variantId = 'variant'}) =>
    _send('nubrick_flutter', 'on-tooltip', {
      'data': _tooltipPayload(),
      'experimentId': 'experiment',
      'variantId': variantId,
      'sessionId': 'native-session-${++_sessionId}',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NubrickFlutterPlatform original;
  late _TooltipPlatform platform;

  setUp(() {
    Nubrick.resetForTest();
    original = NubrickFlutterPlatform.instance;
    platform = _TooltipPlatform();
    NubrickFlutterPlatform.instance = platform;
    Nubrick.initialize('test-project', trackCrashes: false);
  });

  tearDown(() {
    Nubrick.resetForTest();
    NubrickFlutterPlatform.instance = original;
  });

  Future<void> mount(WidgetTester tester, {bool anchorVisible = true}) async {
    final anchorKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Stack(children: [
        if (anchorVisible)
          Center(child: SizedBox(key: anchorKey, width: 100, height: 50)),
        NubrickTooltipOverlay(keysReference: {'anchor': anchorKey}),
      ]),
    ));
  }

  test('display registration sends both experiment and variant IDs', () async {
    final bridge = MethodChannelNubrickFlutter();
    MethodCall? recorded;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(bridge.methodChannel, (call) async {
      recorded = call;
      return null;
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(bridge.methodChannel, null));

    await bridge.appendTooltipExperimentHistory('experiment', 'variant',
        channelId: 'session');

    expect(recorded!.method, 'appendTooltipExperimentHistory');
    expect(recorded!.arguments, {
      'experimentId': 'experiment',
      'variantId': 'variant',
      'channelId': 'session'
    });
  });

  testWidgets('records a displayed flow once, including across tooltip steps',
      (tester) async {
    await mount(tester);
    await _trigger();
    await tester.pump();
    await tester.pump();
    expect(platform.displays, [('experiment', 'variant')]);
    expect(platform.rootIds, ['tooltip-root']);
    expect(platform.connections.single, startsWith('native-session-'));

    await _send('Nubrick/Embedding/${platform.connections.single}',
        'on-next-tooltip', {'pageId': 'next'});
    await tester.pump();
    expect(platform.connections, hasLength(1));
    expect(platform.displays, hasLength(1));

    await _send('Nubrick/Embedding/${platform.connections.single}',
        'on-dismiss-tooltip');
    await _trigger();
    await tester.pump();
    await tester.pump();
    expect(platform.displays, hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a missing variant skips recording and still renders the tooltip',
      (tester) async {
    await mount(tester);
    await _trigger(variantId: null);
    await tester.pump();
    await tester.pump();
    await _trigger(variantId: '');
    await tester.pump();
    await tester.pump();
    expect(platform.connections, hasLength(2));
    expect(platform.displays, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'failed embedding setup stops the native session and permits later retry',
      (tester) async {
    await mount(tester);
    platform.connectResult = 'unavailable';
    await _trigger();
    await tester.pump();
    expect(platform.displays, isEmpty);
    expect(platform.disconnections, contains(platform.connections.single));
    platform.connectResult = 'ok';
    await _trigger();
    await tester.pump();
    await tester.pump();
    expect(platform.displays, hasLength(1));
    expect(platform.connections.toSet(), hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed setup releases its claim and allows another flow',
      (tester) async {
    await mount(tester);
    platform.failConnection = true;
    await _trigger();
    await tester.pump();
    expect(platform.displays, isEmpty);
    expect(platform.disconnections, contains(platform.connections.single));
    platform.failConnection = false;
    await _trigger();
    await tester.pump();
    await tester.pump();
    expect(platform.displays, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disposal during native setup releases the late connection',
      (tester) async {
    await mount(tester);
    platform.pendingConnection = Completer<String?>();
    await _trigger();
    await tester.pump();
    final oldChannel = platform.connections.single;
    await tester.pumpWidget(const SizedBox());
    platform.pendingConnection!.complete('ok');
    await tester.pump();
    expect(platform.displays, isEmpty);
    expect(platform.disconnections, everyElement(oldChannel));
    expect(platform.disconnections, hasLength(2));
  });

  testWidgets('tooltip waits for embedding setup before displaying',
      (tester) async {
    await mount(tester);
    platform.pendingConnection = Completer<String?>();
    await _trigger();
    await tester.pump();
    await tester.pump();
    expect(platform.displays, isEmpty);
    platform.pendingConnection!.complete('ok');
    await tester.pump();
    await tester.pump();
    expect(platform.displays, [('experiment', 'variant')]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('native dismissal cleans up rendering without sending a stop',
      (tester) async {
    await mount(tester);
    await _trigger();
    await tester.pump();
    await tester.pump();
    final channelId = platform.connections.single;
    await _send('Nubrick/Embedding/$channelId', 'on-dismiss-tooltip');
    await tester.idle();
    expect(platform.disconnections, [channelId]);
    expect(platform.stops, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dismissal during a frame cleans up rendering',
      (tester) async {
    await mount(tester);
    await _trigger();
    await tester.pump();
    await tester.pump();
    final channelId = platform.connections.single;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _send('Nubrick/Embedding/$channelId', 'on-dismiss-tooltip');
    });
    await tester.pump();
    expect(platform.disconnections, [channelId]);
    expect(platform.stops, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('display recording does not delay native dismissal cleanup',
      (tester) async {
    await mount(tester);
    platform.pendingRecording = Completer<void>();
    await _trigger();
    await tester.pump();
    await tester.pump();
    await _send('Nubrick/Embedding/${platform.connections.single}',
        'on-dismiss-tooltip');
    await tester.pump();
    expect(platform.disconnections, [platform.connections.single]);
    expect(platform.stops, isEmpty);
    platform.pendingRecording!.complete();
    await tester.pump();
    expect(platform.disconnections, [platform.connections.single]);
    await tester.pumpWidget(const SizedBox());
  });

  Future<void> mountWithPlatformView(WidgetTester tester,
      {List<MethodCall>? viewCalls}) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      viewCalls?.add(call);
      return null;
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    });
    await mount(tester);
    await _trigger();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('waiting on a native page keeps the flow until native returns',
      (tester) async {
    await mountWithPlatformView(tester);
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(platform.dispatches, [platform.connections.single]);
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(platform.disconnections, isEmpty);
    await _send('Nubrick/Embedding/${platform.connections.single}',
        'on-next-tooltip', {'pageId': 'next'});
    await tester.pump();
    expect(platform.displays, hasLength(1));
    expect(platform.connections, hasLength(1));
    expect(platform.stops, isEmpty);
    await _send('Nubrick/Embedding/${platform.connections.single}',
        'on-dismiss-tooltip');
    await tester.pump();
    expect(platform.disconnections, [platform.connections.single]);
    expect(platform.stops, isEmpty);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('dispatch failure hides the tooltip and releases its claim',
      (tester) async {
    await mountWithPlatformView(tester);
    platform.failDispatch = true;
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(platform.dispatches, [platform.connections.single]);
    expect(platform.disconnections, [platform.connections.single]);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a new session recreates the native view before the next frame',
      (tester) async {
    final viewCalls = <MethodCall>[];
    await mountWithPlatformView(tester, viewCalls: viewCalls);
    final firstCreate = viewCalls.singleWhere((call) => call.method == 'create');
    final oldChannel = platform.connections.single;

    // Moving between pages in one session keeps the same native view.
    await _send('Nubrick/Embedding/$oldChannel',
        'on-next-tooltip', {'pageId': 'next'});
    await tester.pump();
    expect(viewCalls.where((call) => call.method == 'create'), hasLength(1));

    platform.pendingConnection = Completer<String?>();
    await _trigger();
    final newChannel = platform.connections.last;
    // iOS RootView can request its first tooltip during embedding setup,
    // before Flutter has rendered the cleared state of the previous flow.
    await _send('Nubrick/Embedding/$newChannel',
        'on-next-tooltip', {'pageId': 'tooltip'});
    platform.pendingConnection!.complete('ok');
    await tester.pump();
    await tester.pump();

    final creates = viewCalls.where((call) => call.method == 'create').toList();
    expect(creates, hasLength(2));
    expect(creates.last.arguments['id'], isNot(firstCreate.arguments['id']));
    final params = const StandardMessageCodec().decodeMessage(
        ByteData.sublistView(creates.last.arguments['params'] as Uint8List));
    expect(params, containsPair('channelId', newChannel));
    expect(
        viewCalls
            .where((call) => call.method == 'dispose')
            .map((call) => call.arguments),
        contains(firstCreate.arguments['id']));
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });



  testWidgets('missing anchor times out without recording display',
      (tester) async {
    await mount(tester, anchorVisible: false);
    await _trigger();
    await tester.pump();
    for (var i = 0; i < 32; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(platform.displays, isEmpty);
    expect(platform.disconnections, contains(platform.connections.single));
    expect(platform.stops, [platform.connections.single]);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('a newly reserved native flow replaces stale Flutter rendering',
      (tester) async {
    await mount(tester);
    await _trigger();
    await tester.pump();
    await tester.pump();
    final oldChannel = platform.connections.single;
    await _trigger();
    await tester.pump();
    await tester.pump();
    expect(platform.connections.toSet(), hasLength(2));
    expect(platform.disconnections, [oldChannel]);
    expect(platform.stops, isEmpty);
    await _send('Nubrick/Embedding/$oldChannel', 'on-dismiss-tooltip');
    await tester.pump();
    expect(platform.disconnections, [oldChannel]);
    await tester.pumpWidget(const SizedBox());
    expect(platform.stops, [platform.connections.last]);
  });
}
