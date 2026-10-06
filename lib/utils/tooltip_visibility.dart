import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

bool containsTooltipAnchor(Rect viewport, Rect anchor) =>
    !viewport.isEmpty &&
    anchor.left >= viewport.left - precisionErrorTolerance &&
    anchor.top >= viewport.top - precisionErrorTolerance &&
    anchor.right <= viewport.right + precisionErrorTolerance &&
    anchor.bottom <= viewport.bottom + precisionErrorTolerance;

/// Geometry is measured in global logical pixels.
class TooltipAnchorVisibility {
  final RenderBox anchor;
  final Rect bounds;
  final Rect viewportBounds;

  TooltipAnchorVisibility._(this.anchor, this.bounds, this.viewportBounds);

  static TooltipAnchorVisibility? measure(BuildContext context) {
    final object = context.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) {
      return null;
    }
    Rect viewport = Offset.zero & MediaQuery.sizeOf(context);
    RenderObject child = object;
    while (child.parent != null) {
      final parent = child.parent!;
      final clip = parent.describeApproximatePaintClip(child);
      if (clip != null) {
        viewport = viewport.intersect(
          MatrixUtils.transformRect(parent.getTransformTo(null), clip),
        );
      }
      child = parent;
    }
    return TooltipAnchorVisibility._(
      object,
      MatrixUtils.transformRect(
          object.getTransformTo(null), Offset.zero & object.size),
      viewport,
    );
  }

  bool get isVisible {
    if (viewportBounds.isEmpty || bounds.isEmpty) return false;
    final visibleBounds = viewportBounds.intersect(bounds);
    // Smaller anchors must fit; oversized anchors must fill the viewport on
    // each oversized axis. Allow only floating-point rounding at the edges.
    return visibleBounds.width + precisionErrorTolerance >=
            math.min(bounds.width, viewportBounds.width) &&
        visibleBounds.height + precisionErrorTolerance >=
            math.min(bounds.height, viewportBounds.height);
  }
}
