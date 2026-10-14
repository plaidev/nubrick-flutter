import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubrick_flutter/schema/generated.dart' show UITooltipPlacement;
import 'package:nubrick_flutter/utils/tooltip_position.dart';

const _screen = Size(400, 800);
const _tooltip = Size(120, 80);

// Regression expectations for issue #3092 with the default 16px screen margin.
const _expected = <String, Map<UITooltipPlacement, Offset>>{
  'normal': {
    UITooltipPlacement.TOP_CENTER: Offset(140, 272),
    UITooltipPlacement.TOP_START: Offset(160, 272),
    UITooltipPlacement.TOP_END: Offset(120, 272),
    UITooltipPlacement.BOTTOM_CENTER: Offset(140, 448),
    UITooltipPlacement.BOTTOM_START: Offset(160, 448),
    UITooltipPlacement.BOTTOM_END: Offset(120, 448),
    UITooltipPlacement.LEFT_CENTER: Offset(24, 360),
    UITooltipPlacement.LEFT_START: Offset(24, 368),
    UITooltipPlacement.LEFT_END: Offset(24, 352),
    UITooltipPlacement.RIGHT_CENTER: Offset(256, 360),
    UITooltipPlacement.RIGHT_START: Offset(256, 368),
    UITooltipPlacement.RIGHT_END: Offset(256, 352),
    UITooltipPlacement.UNKNOWN: Offset(140, 448),
  },
  'full_width': {
    UITooltipPlacement.TOP_CENTER: Offset(140, 272),
    UITooltipPlacement.TOP_START: Offset(16, 272),
    UITooltipPlacement.TOP_END: Offset(264, 272),
    UITooltipPlacement.BOTTOM_CENTER: Offset(140, 448),
    UITooltipPlacement.BOTTOM_START: Offset(16, 448),
    UITooltipPlacement.BOTTOM_END: Offset(264, 448),
    UITooltipPlacement.LEFT_CENTER: Offset(16, 360),
    UITooltipPlacement.LEFT_START: Offset(16, 368),
    UITooltipPlacement.LEFT_END: Offset(16, 352),
    UITooltipPlacement.RIGHT_CENTER: Offset(264, 360),
    UITooltipPlacement.RIGHT_START: Offset(264, 368),
    UITooltipPlacement.RIGHT_END: Offset(264, 352),
    UITooltipPlacement.UNKNOWN: Offset(140, 448),
  },
  'full_height': {
    UITooltipPlacement.TOP_CENTER: Offset(140, 16),
    UITooltipPlacement.TOP_START: Offset(160, 16),
    UITooltipPlacement.TOP_END: Offset(120, 16),
    UITooltipPlacement.BOTTOM_CENTER: Offset(140, 704),
    UITooltipPlacement.BOTTOM_START: Offset(160, 704),
    UITooltipPlacement.BOTTOM_END: Offset(120, 704),
    UITooltipPlacement.LEFT_CENTER: Offset(24, 360),
    UITooltipPlacement.LEFT_START: Offset(24, 16),
    UITooltipPlacement.LEFT_END: Offset(24, 704),
    UITooltipPlacement.RIGHT_CENTER: Offset(256, 360),
    UITooltipPlacement.RIGHT_START: Offset(256, 16),
    UITooltipPlacement.RIGHT_END: Offset(256, 704),
    UITooltipPlacement.UNKNOWN: Offset(140, 704),
  },
  'anchor_overlap': {
    UITooltipPlacement.TOP_CENTER: Offset(140, 16),
    UITooltipPlacement.TOP_START: Offset(160, 16),
    UITooltipPlacement.TOP_END: Offset(120, 16),
    UITooltipPlacement.BOTTOM_CENTER: Offset(140, 704),
    UITooltipPlacement.BOTTOM_START: Offset(160, 704),
    UITooltipPlacement.BOTTOM_END: Offset(120, 704),
    UITooltipPlacement.LEFT_CENTER: Offset(16, 360),
    UITooltipPlacement.LEFT_START: Offset(16, 368),
    UITooltipPlacement.LEFT_END: Offset(16, 352),
    UITooltipPlacement.RIGHT_CENTER: Offset(264, 360),
    UITooltipPlacement.RIGHT_START: Offset(264, 368),
    UITooltipPlacement.RIGHT_END: Offset(264, 352),
    UITooltipPlacement.UNKNOWN: Offset(140, 704),
  },
};

Rect _anchorRect(String scenario, UITooltipPlacement placement) {
  switch (scenario) {
    case 'normal':
      return const Rect.fromLTWH(160, 368, 80, 64);
    case 'full_width':
      return const Rect.fromLTWH(0, 368, 400, 64);
    case 'full_height':
      return const Rect.fromLTWH(160, 0, 80, 800);
    case 'anchor_overlap':
      // Clamping to the 16px screen margin moves the tooltip by 40px:
      // the 16px gap plus 24px of anchor overlap.
      switch (placement) {
        case UITooltipPlacement.TOP_CENTER:
        case UITooltipPlacement.TOP_START:
        case UITooltipPlacement.TOP_END:
          return const Rect.fromLTWH(160, 72, 80, 64);
        case UITooltipPlacement.BOTTOM_CENTER:
        case UITooltipPlacement.BOTTOM_START:
        case UITooltipPlacement.BOTTOM_END:
        case UITooltipPlacement.UNKNOWN:
          return const Rect.fromLTWH(160, 664, 80, 64);
        case UITooltipPlacement.LEFT_CENTER:
        case UITooltipPlacement.LEFT_START:
        case UITooltipPlacement.LEFT_END:
          return const Rect.fromLTWH(112, 368, 80, 64);
        case UITooltipPlacement.RIGHT_CENTER:
        case UITooltipPlacement.RIGHT_START:
        case UITooltipPlacement.RIGHT_END:
          return const Rect.fromLTWH(208, 368, 80, 64);
      }
    default:
      throw ArgumentError.value(scenario, 'scenario');
  }
}

Offset _position(Rect anchor, UITooltipPlacement placement) {
  return calculateTooltipPosition(
    anchorPosition: anchor.topLeft,
    anchorSize: anchor.size,
    tooltipSize: _tooltip,
    screenSize: _screen,
    placement: placement,
  );
}

void main() {
  test('each scenario covers every placement, including UNKNOWN', () {
    for (final positions in _expected.values) {
      expect(positions.keys, unorderedEquals(UITooltipPlacement.values));
    }
  });

  group('placement and overlap regressions with default margin 16', () {
    for (final scenario in _expected.entries) {
      for (final entry in scenario.value.entries) {
        test('${scenario.key}/${entry.key.name}', () {
          final anchor = _anchorRect(scenario.key, entry.key);
          final position = _position(anchor, entry.key);
          expect(position, entry.value);
          if (scenario.key == 'anchor_overlap') {
            final overlap = anchor.intersect(position & _tooltip);
            expect(overlap.width == 24 || overlap.height == 24, isTrue);
          }
        });
      }
    }
  });

  group('positions just inside, on, and outside each boundary', () {
    const cases = <(double, UITooltipPlacement, Offset, Offset)>[
      (16, UITooltipPlacement.LEFT_CENTER, Offset(151, 368), Offset(16, 360)),
      (16, UITooltipPlacement.LEFT_CENTER, Offset(152, 368), Offset(16, 360)),
      (16, UITooltipPlacement.LEFT_CENTER, Offset(153, 368), Offset(17, 360)),
      (16, UITooltipPlacement.RIGHT_CENTER, Offset(167, 368), Offset(263, 360)),
      (16, UITooltipPlacement.RIGHT_CENTER, Offset(168, 368), Offset(264, 360)),
      (16, UITooltipPlacement.RIGHT_CENTER, Offset(169, 368), Offset(264, 360)),
      (16, UITooltipPlacement.TOP_CENTER, Offset(160, 111), Offset(140, 16)),
      (16, UITooltipPlacement.TOP_CENTER, Offset(160, 112), Offset(140, 16)),
      (16, UITooltipPlacement.TOP_CENTER, Offset(160, 113), Offset(140, 17)),
      (
        16,
        UITooltipPlacement.BOTTOM_CENTER,
        Offset(160, 623),
        Offset(140, 703)
      ),
      (
        16,
        UITooltipPlacement.BOTTOM_CENTER,
        Offset(160, 624),
        Offset(140, 704)
      ),
      (
        16,
        UITooltipPlacement.BOTTOM_CENTER,
        Offset(160, 625),
        Offset(140, 704)
      ),
    ];
    for (final (margin, placement, anchor, expected) in cases) {
      test('margin $margin/${placement.name}/$anchor', () {
        expect(
          calculateTooltipPosition(
            anchorPosition: anchor,
            anchorSize: const Size(80, 64),
            tooltipSize: _tooltip,
            screenSize: _screen,
            placement: placement,
            margin: margin,
          ),
          expected,
        );
      });
    }
  });

  group('anchor offset is independent of screen margin', () {
    const cases = <(UITooltipPlacement, List<Offset>)>[
      (
        UITooltipPlacement.TOP_CENTER,
        [Offset(140, 288), Offset(140, 280), Offset(140, 272)]
      ),
      (
        UITooltipPlacement.BOTTOM_CENTER,
        [Offset(140, 432), Offset(140, 440), Offset(140, 448)]
      ),
      (
        UITooltipPlacement.LEFT_CENTER,
        [Offset(40, 360), Offset(32, 360), Offset(24, 360)]
      ),
      (
        UITooltipPlacement.RIGHT_CENTER,
        [Offset(240, 360), Offset(248, 360), Offset(256, 360)]
      ),
    ];
    for (final (placement, expected) in cases) {
      for (var i = 0; i < 3; i++) {
        final offset = [0.0, 8.0, 16.0][i];
        test('${placement.name}/offset $offset', () {
          expect(
            calculateTooltipPosition(
              anchorPosition: const Offset(160, 368),
              anchorSize: const Size(80, 64),
              tooltipSize: _tooltip,
              screenSize: _screen,
              placement: placement,
              offset: offset,
            ),
            expected[i],
          );
        });
      }
    }
  });

  group('custom screen, tooltip, offset, and margin', () {
    const cases = <UITooltipPlacement, Offset>{
      UITooltipPlacement.TOP_CENTER: Offset(90, 148),
      UITooltipPlacement.BOTTOM_CENTER: Offset(90, 242),
      UITooltipPlacement.LEFT_CENTER: Offset(24, 195),
      UITooltipPlacement.RIGHT_CENTER: Offset(172, 195),
    };
    for (final entry in cases.entries) {
      test(entry.key.name, () {
        expect(
          calculateTooltipPosition(
            anchorPosition: const Offset(100, 200),
            anchorSize: const Size(60, 30),
            tooltipSize: const Size(80, 40),
            screenSize: const Size(320, 640),
            placement: entry.key,
            offset: 12,
            margin: 24,
          ),
          entry.value,
        );
      });
    }
  });

  group('tooltips that cannot fit the available screen area', () {
    const cases = <(String, Size, Size, Offset)>[
      ('too wide', Size(100, 800), Size(120, 80), Offset(16, 448)),
      ('too tall', Size(400, 50), Size(120, 80), Offset(140, 16)),
      ('larger than screen', Size(100, 50), Size(120, 80), Offset(16, 16)),
      (
        'fills area inside margins',
        Size(400, 800),
        Size(368, 768),
        Offset(16, 16)
      ),
    ];
    for (final (name, screen, tooltip, expected) in cases) {
      test(name, () {
        expect(
          calculateTooltipPosition(
            anchorPosition: const Offset(160, 368),
            anchorSize: const Size(80, 64),
            tooltipSize: tooltip,
            screenSize: screen,
            placement: UITooltipPlacement.BOTTOM_CENTER,
          ),
          expected,
        );
      });
    }
  });
}
