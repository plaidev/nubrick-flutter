import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubrick_flutter/utils/tooltip_visibility.dart';

import 'helpers/tooltip_visibility.dart';

class _ThrowingClip extends SingleChildRenderObjectWidget {
  const _ThrowingClip({super.key, required super.child});

  @override
  _ThrowingClipRenderBox createRenderObject(BuildContext context) =>
      _ThrowingClipRenderBox();
}

class _ThrowingClipRenderBox extends RenderProxyBox {
  Object? measurementError;

  @override
  Rect? describeApproximatePaintClip(RenderObject child) {
    final error = measurementError;
    if (error != null) throw error;
    return super.describeApproximatePaintClip(child);
  }
}

void main() {
  testWidgets('returns null for a disposed context', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(key: key, width: 40, height: 40),
    ));
    final context = key.currentContext!;
    await tester.pumpWidget(const SizedBox());

    expect(context.mounted, isFalse);
    expect(isTooltipAnchorVisible(context), isNull);
  });

  testWidgets('returns null when an ancestor clip measurement throws',
      (tester) async {
    final anchorKey = GlobalKey();
    final clipKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: _ThrowingClip(
        key: clipKey,
        child: SizedBox(key: anchorKey, width: 40, height: 40),
      ),
    ));
    expect(isTooltipAnchorVisible(anchorKey.currentContext!), isTrue);
    final clip =
        clipKey.currentContext!.findRenderObject()! as _ThrowingClipRenderBox;
    try {
      for (final error in [
        FlutterError('Clip measurement failed'),
        StateError('Clip measurement failed'),
      ]) {
        clip.measurementError = error;
        expect(isTooltipAnchorVisible(anchorKey.currentContext!), isNull);
      }
    } finally {
      clip.measurementError = null;
    }
  });

  testWidgets('returns null when there is no MediaQuery', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      RawView(
        view: tester.view,
        child: SizedBox(key: key, width: 40, height: 40),
      ),
      wrapWithView: false,
    );

    final context = key.currentContext!;
    final box = context.findRenderObject()! as RenderBox;
    expect(box.attached, isTrue);
    expect(box.hasSize, isTrue);
    expect(MediaQuery.maybeSizeOf(context), isNull);
    expect(isTooltipAnchorVisible(context), isNull);
  });

  testWidgets('propagates unexpected errors during clip measurement',
      (tester) async {
    final anchorKey = GlobalKey();
    final clipKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: _ThrowingClip(
        key: clipKey,
        child: SizedBox(key: anchorKey, width: 40, height: 40),
      ),
    ));
    final clip =
        clipKey.currentContext!.findRenderObject()! as _ThrowingClipRenderBox;
    try {
      for (final error in [TypeError(), AssertionError('Clip implementation')]) {
        clip.measurementError = error;
        expect(() => isTooltipAnchorVisible(anchorKey.currentContext!),
            throwsA(same(error)));
      }
    } finally {
      clip.measurementError = null;
    }
  });

  test('containment accepts exact edges but rejects clipping', () {
    const viewport = Rect.fromLTWH(0, 0, 100, 100);
    expect(containsTooltipAnchor(viewport, viewport), isTrue);
    for (final anchor in [
      const Rect.fromLTRB(-0.01, 0, 100, 100),
      const Rect.fromLTRB(0, -0.01, 100, 100),
      const Rect.fromLTRB(0, 0, 100.01, 100),
      const Rect.fromLTRB(0, 0, 100, 100.01),
    ]) {
      expect(containsTooltipAnchor(viewport, anchor), isFalse);
    }
    expect(containsTooltipAnchor(Rect.zero, Rect.zero), isFalse);
  });

  testWidgets('oversized anchors must be maximally exposed on both axes',
      (tester) async {
    final key = GlobalKey();
    final cases = <(Rect, bool)>[
      (const Rect.fromLTWH(0, 0, 40, 150), true),
      (const Rect.fromLTWH(0, 0, 150, 40), true),
      (const Rect.fromLTWH(-25, -25, 150, 150), true),
      (const Rect.fromLTWH(0, 20, 40, 150), false),
      (const Rect.fromLTWH(20, 0, 150, 40), false),
      (const Rect.fromLTWH(-20, 0, 40, 150), false),
      (const Rect.fromLTWH(0, -20, 150, 40), false),
    ];
    for (final (bounds, expected) in cases) {
      await tester.pumpWidget(MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fromRect(rect: bounds, child: SizedBox(key: key)),
              ],
            ),
          ),
        ),
      ));
      expect(isTooltipAnchorVisible(key.currentContext!), expected,
          reason: 'Anchor bounds: $bounds');
    }
  });

  testWidgets(
      'does not detect a sibling covering an anchor inside the viewport',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          SingleChildScrollView(
            child: Column(children: [
              const SizedBox(height: 30),
              SizedBox(key: key, height: 40, width: 100),
              const SizedBox(height: 1000),
            ]),
          ),
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ColoredBox(
              color: Colors.white,
              child: SizedBox(height: 80),
            ),
          ),
        ]),
      ),
    ));
    // Visibility currently checks ancestor clipping, not sibling occlusion.
    expect(isTooltipAnchorVisible(key.currentContext!), isTrue);
  });

  testWidgets('rejects an anchor clipped by its scroll viewport',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: 100,
          child: SingleChildScrollView(
            child: Column(children: [
              const SizedBox(height: 150),
              SizedBox(key: key, height: 40, width: 100),
            ]),
          ),
        ),
      ),
    ));
    expect(isTooltipAnchorVisible(key.currentContext!), isFalse);
  });
}
