import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Geometry is measured in global logical pixels.
///
/// Returns null when the anchor cannot be measured.
bool? isTooltipAnchorVisible(BuildContext context) {
  if (!context.mounted) return null;

  late final Rect viewportBounds;
  late final Rect bounds;
  try {
    final screenSize = MediaQuery.maybeSizeOf(context);
    if (screenSize == null) return null;

    final object = context.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) {
      return null;
    }
    Rect viewport = Offset.zero & screenSize;
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
    bounds = MatrixUtils.transformRect(
        object.getTransformTo(null), Offset.zero & object.size);
    viewportBounds = viewport;
  } on FlutterError {
    // The element or render tree may no longer support geometry lookup.
    return null;
  } on StateError {
    // Treat unavailable render geometry as an unresolved anchor.
    return null;
  }

  if (viewportBounds.isEmpty || bounds.isEmpty) return false;
  final visibleBounds = viewportBounds.intersect(bounds);
  // Smaller anchors must fit; oversized anchors must fill the viewport on
  // each oversized axis.
  return visibleBounds.width >=
          math.min(bounds.width, viewportBounds.width) &&
      visibleBounds.height >= math.min(bounds.height, viewportBounds.height);
}
