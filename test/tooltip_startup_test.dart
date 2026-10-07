import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubrick_flutter/channel/nubrick_flutter_platform_interface.dart';
import 'package:nubrick_flutter/nubrick_flutter.dart';
import 'package:nubrick_flutter/schema/generated.dart';
import 'package:nubrick_flutter/src/runtime.dart';
import 'package:nubrick_flutter/tooltip/overlay.dart';
import 'package:nubrick_flutter/utils/tooltip_visibility.dart';
import 'package:nubrick_flutter/utils/transparent_pointer.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _TooltipPlatform extends NubrickFlutterPlatform
    with MockPlatformInterfaceMixin {
  int connections = 0;
  final shownExperiments = <String>[];

  @override
  Future<String?> connectClient(String projectId) async => 'ok';

  @override
  Future<String?> connectTooltipEmbedding(String channelId, String experimentId,
      String? variantId, UIRootBlock rootBlock) async {
    connections++;
    return 'ok';
  }

  @override
  Future<String?> disconnectTooltipEmbedding(String channelId,
          {required bool stoppedByFlutter}) async =>
      'ok';

  @override
  Future<void> appendTooltipExperimentHistory(
      String experimentId, String variantId,
      {required String channelId}) async {
    shownExperiments.add(experimentId);
  }
}

class _TooltipHarness {
  final platform = _TooltipPlatform();
  final controller = ScrollController();
  final anchorKey = GlobalKey();
  final viewportKey = GlobalKey();
  final navigationKey = GlobalKey();

  Future<void> sendTooltip(WidgetTester tester) async {
    final payload = {
      'data': jsonEncode({
        'id': 'root',
        'data': {
          'currentPageId': 'trigger',
          'pages': [
            {
              'id': 'trigger',
              'data': {
                'triggerSetting': {
                  'onTrigger': {'destinationPageId': 'tooltip'}
                }
              }
            },
            {
              'id': 'tooltip',
              'data': {
                'tooltipAnchor': 'target',
                'tooltipSize': {'width': 100, 'height': 60},
              }
            }
          ]
        }
      }),
      'experimentId': 'experiment',
      'variantId': 'variant',
      'sessionId': 'native-session',
    };
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'nubrick_flutter',
      const StandardMethodCodec()
          .encodeMethodCall(MethodCall('on-tooltip', payload)),
      (_) {},
    );
    // Flush the connection without forcing the frame needed by the lookup.
    await tester.idle();
    expect(platform.connections, 1);
  }

  Future<void> finishLookup(WidgetTester tester) async {
    await tester.pumpAndSettle();
    // The lookup retries after the scroll animation has completed.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
  }

  void expectHighlightOnAnchor(WidgetTester tester) {
    final highlight = find.descendant(
      of: find.byType(NubrickTooltipOverlay),
      matching: find.byType(TransparentPointer),
    );
    expect(highlight, findsOneWidget);
    final hole = tester.widget<TransparentPointer>(highlight).transparentRect!;
    final anchor = tester.getRect(find.byKey(anchorKey));
    expect(hole.left, closeTo(anchor.left, 0.01));
    expect(hole.top, closeTo(anchor.top, 0.01));
    expect(hole.width, closeTo(anchor.width, 0.01));
    expect(hole.height, closeTo(anchor.height, 0.01));
    expect(find.descendant(of: highlight, matching: find.byType(CustomPaint)),
        findsOneWidget);
    expect(find.byType(UiKitView), findsOneWidget);
    expect(platform.shownExperiments, ['experiment']);
  }
}

Future<void> _withTooltipHarness(
  WidgetTester tester, {
  required double beforeAnchor,
  required double afterAnchor,
  double anchorHeight = 40,
  double? viewportHeight,
  bool showAppBar = false,
  bool showBottomNavigationBar = false,
  required Future<void> Function(_TooltipHarness) check,
}) async {
  final original = NubrickFlutterPlatform.instance;
  final originalTarget = debugDefaultTargetPlatformOverride;
  final harness = _TooltipHarness();
  Nubrick.resetForTest();
  NubrickFlutterPlatform.instance = harness.platform;
  // Render the actual Flutter barrier while mocking the native tooltip view.
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views, (_) async => null);
  try {
    Nubrick.initialize('test-project', trackCrashes: false);
    await nubrickRuntime.ready;
    await tester.pumpWidget(MaterialApp(
      // The provider's overlay covers the whole route, including its chrome.
      home: Stack(children: [
        Scaffold(
          appBar: showAppBar ? AppBar(title: const Text('Page A')) : null,
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              key: harness.viewportKey,
              height: viewportHeight,
              width: double.infinity,
              child: SingleChildScrollView(
                controller: harness.controller,
                child: Column(children: [
                  SizedBox(height: beforeAnchor),
                  SizedBox(
                      key: harness.anchorKey, height: anchorHeight, width: 100),
                  SizedBox(height: afterAnchor),
                ]),
              ),
            ),
          ),
          bottomNavigationBar: showBottomNavigationBar
              ? BottomNavigationBar(
                  key: harness.navigationKey,
                  items: const [
                    BottomNavigationBarItem(
                        icon: Icon(Icons.home), label: 'Page A'),
                    BottomNavigationBarItem(
                        icon: Icon(Icons.business), label: 'Page B'),
                  ],
                )
              : null,
        ),
        NubrickTooltipOverlay(keysReference: {'target': harness.anchorKey}),
      ]),
    ));
    await tester.pumpAndSettle();
    await check(harness);
  } finally {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    Nubrick.resetForTest();
    NubrickFlutterPlatform.instance = original;
    debugDefaultTargetPlatformOverride = originalTarget;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
    harness.controller.dispose();
  }
}

void main() {
  testWidgets('tooltip shows an oversized anchor already filling its viewport',
      (tester) async {
    await _withTooltipHarness(tester,
        beforeAnchor: 0,
        afterAnchor: 0,
        anchorHeight: 150,
        viewportHeight: 100, check: (harness) async {
      await harness.sendTooltip(tester);
      await harness.finishLookup(tester);
      expect(harness.controller.offset, 0);
      harness.expectHighlightOnAnchor(tester);
    });
  });

  testWidgets(
      'tooltip scrolls to and keeps a maximally exposed oversized anchor',
      (tester) async {
    await _withTooltipHarness(tester,
        beforeAnchor: 200,
        afterAnchor: 200,
        anchorHeight: 150,
        viewportHeight: 100, check: (harness) async {
      await harness.sendTooltip(tester);
      await harness.finishLookup(tester);
      final anchor = tester.getRect(find.byKey(harness.anchorKey));
      final viewport = tester.getRect(find.byKey(harness.viewportKey));
      expect(harness.controller.offset, greaterThan(0));
      expect(anchor.top, lessThanOrEqualTo(viewport.top));
      expect(anchor.bottom, greaterThanOrEqualTo(viewport.bottom));
      // Keep the tooltip visible through consecutive position-update frames.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      harness.expectHighlightOnAnchor(tester);
    });
  });

  testWidgets('tooltip scrolls an on-screen anchor clear of the bottom bar',
      (tester) async {
    await _withTooltipHarness(tester,
        beforeAnchor: 1000,
        afterAnchor: 400,
        showAppBar: true,
        showBottomNavigationBar: true, check: (harness) async {
      final navigation = tester.getRect(find.byKey(harness.navigationKey));
      final initialAnchor = tester.getRect(find.byKey(harness.anchorKey));
      // Place the anchor inside screen bounds, but below the body viewport.
      harness.controller.jumpTo(initialAnchor.top - navigation.top - 8);
      await tester.pumpAndSettle();
      final coveredAnchor = tester.getRect(find.byKey(harness.anchorKey));
      final screen =
          Offset.zero & MediaQuery.sizeOf(harness.anchorKey.currentContext!);
      expect(containsTooltipAnchor(screen, coveredAnchor), isTrue);
      expect(navigation.overlaps(coveredAnchor), isTrue);
      expect(
          TooltipAnchorVisibility.measure(harness.anchorKey.currentContext!)!
              .isVisible,
          isFalse);
      final beforeOffset = harness.controller.offset;

      await harness.sendTooltip(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byType(TransparentPointer), findsNothing);
      await harness.finishLookup(tester);

      final revealedAnchor = tester.getRect(find.byKey(harness.anchorKey));
      final body = tester.getRect(find.byKey(harness.viewportKey));
      expect(harness.controller.offset, greaterThan(beforeOffset));
      expect(containsTooltipAnchor(body, revealedAnchor), isTrue);
      expect(navigation.overlaps(revealedAnchor), isFalse);
      harness.expectHighlightOnAnchor(tester);
      final highlight =
          tester.widget<TransparentPointer>(find.byType(TransparentPointer));
      expect(navigation.overlaps(highlight.transparentRect!), isFalse);
    });
  });

  testWidgets(
      'startup tooltip schedules a frame, centers and highlights anchor',
      (tester) async {
    await _withTooltipHarness(tester, beforeAnchor: 1000, afterAnchor: 1000,
        check: (harness) async {
      expect(tester.binding.hasScheduledFrame, isFalse);
      await harness.sendTooltip(tester);
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      // Keep the highlight hidden until scrolling and remeasurement finish.
      expect(find.byType(TransparentPointer), findsNothing);
      expect(harness.platform.shownExperiments, isEmpty);
      await harness.finishLookup(tester);
      final anchor = tester.getRect(find.byKey(harness.anchorKey));
      final viewport = tester.getRect(find.byKey(harness.viewportKey));
      expect(anchor.center.dy, closeTo(viewport.center.dy, 0.01));
      expect(harness.controller.offset, greaterThan(0));
      harness.expectHighlightOnAnchor(tester);
    });
  });

  testWidgets('tooltip highlights a visible anchor without scrolling',
      (tester) async {
    await _withTooltipHarness(tester, beforeAnchor: 160, afterAnchor: 1000,
        check: (harness) async {
      harness.controller.jumpTo(80);
      await tester.pumpAndSettle();
      final before = tester.getRect(find.byKey(harness.anchorKey));
      final offsets = <double>[];
      void recordOffset() => offsets.add(harness.controller.offset);
      harness.controller.addListener(recordOffset);
      try {
        await harness.sendTooltip(tester);
        await harness.finishLookup(tester);
        expect(harness.controller.offset, 80);
        expect(offsets, isEmpty);
        expect(tester.getRect(find.byKey(harness.anchorKey)), before);
        harness.expectHighlightOnAnchor(tester);
      } finally {
        harness.controller.removeListener(recordOffset);
      }
    });
  });

  testWidgets('tooltip highlights at scroll end when centering is impossible',
      (tester) async {
    await _withTooltipHarness(tester, beforeAnchor: 1000, afterAnchor: 0,
        check: (harness) async {
      await harness.sendTooltip(tester);
      await harness.finishLookup(tester);
      final anchor = tester.getRect(find.byKey(harness.anchorKey));
      final viewport = tester.getRect(find.byKey(harness.viewportKey));
      expect(harness.controller.offset,
          closeTo(harness.controller.position.maxScrollExtent, 0.01));
      expect(anchor.bottom, closeTo(viewport.bottom, 0.01));
      expect(anchor.top, greaterThanOrEqualTo(viewport.top));
      expect(anchor.center.dy, greaterThan(viewport.center.dy));
      harness.expectHighlightOnAnchor(tester);
    });
  });
}
