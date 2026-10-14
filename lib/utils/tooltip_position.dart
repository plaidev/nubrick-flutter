import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:nubrick_flutter/schema/generated.dart';

Offset calculateTooltipPosition({
  required Offset anchorPosition,
  required Size anchorSize,
  required Size tooltipSize,
  required Size screenSize,
  required UITooltipPlacement placement,
  double offset = 16.0,
  double margin = 16.0,
}) {
  // Initial position variables
  double left = 0.0;
  double top = 0.0;

  // Calculate position based on requested placement
  switch (placement) {
    // TOP placements (tooltip above anchor)
    case UITooltipPlacement.TOP_CENTER:
      left = anchorPosition.dx + (anchorSize.width - tooltipSize.width) / 2;
      top = anchorPosition.dy - tooltipSize.height - offset;
      break;
    case UITooltipPlacement.TOP_START:
      left = anchorPosition.dx;
      top = anchorPosition.dy - tooltipSize.height - offset;
      break;
    case UITooltipPlacement.TOP_END:
      left = anchorPosition.dx + anchorSize.width - tooltipSize.width;
      top = anchorPosition.dy - tooltipSize.height - offset;
      break;

    // BOTTOM placements (tooltip below anchor)
    case UITooltipPlacement.BOTTOM_CENTER:
      left = anchorPosition.dx + (anchorSize.width - tooltipSize.width) / 2;
      top = anchorPosition.dy + anchorSize.height + offset;
      break;
    case UITooltipPlacement.BOTTOM_START:
      left = anchorPosition.dx;
      top = anchorPosition.dy + anchorSize.height + offset;
      break;
    case UITooltipPlacement.BOTTOM_END:
      left = anchorPosition.dx + anchorSize.width - tooltipSize.width;
      top = anchorPosition.dy + anchorSize.height + offset;
      break;

    // LEFT placements (tooltip to the left of anchor)
    case UITooltipPlacement.LEFT_CENTER:
      left = anchorPosition.dx - tooltipSize.width - offset;
      top = anchorPosition.dy + (anchorSize.height - tooltipSize.height) / 2;
      break;
    case UITooltipPlacement.LEFT_START:
      left = anchorPosition.dx - tooltipSize.width - offset;
      top = anchorPosition.dy;
      break;
    case UITooltipPlacement.LEFT_END:
      left = anchorPosition.dx - tooltipSize.width - offset;
      top = anchorPosition.dy + anchorSize.height - tooltipSize.height;
      break;

    // RIGHT placements (tooltip to the right of anchor)
    case UITooltipPlacement.RIGHT_CENTER:
      left = anchorPosition.dx + anchorSize.width + offset;
      top = anchorPosition.dy + (anchorSize.height - tooltipSize.height) / 2;
      break;
    case UITooltipPlacement.RIGHT_START:
      left = anchorPosition.dx + anchorSize.width + offset;
      top = anchorPosition.dy;
      break;
    case UITooltipPlacement.RIGHT_END:
      left = anchorPosition.dx + anchorSize.width + offset;
      top = anchorPosition.dy + anchorSize.height - tooltipSize.height;
      break;

    case UITooltipPlacement.UNKNOWN:
      // Default to BOTTOM_CENTER if unknown
      left = anchorPosition.dx + (anchorSize.width - tooltipSize.width) / 2;
      top = anchorPosition.dy + anchorSize.height + offset;
      break;
  }

  // Keep the requested side instead of flipping around the anchor.
  // Oversized tooltips stay at the leading margin without an invalid range.
  return Offset(
    left.clamp(margin,
        math.max(margin, screenSize.width - tooltipSize.width - margin)),
    top.clamp(margin,
        math.max(margin, screenSize.height - tooltipSize.height - margin)),
  );
}
