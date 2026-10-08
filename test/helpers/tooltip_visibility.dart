import 'package:flutter/widgets.dart';

bool containsTooltipAnchor(Rect viewport, Rect anchor) =>
    !viewport.isEmpty &&
    anchor.left >= viewport.left &&
    anchor.top >= viewport.top &&
    anchor.right <= viewport.right &&
    anchor.bottom <= viewport.bottom;
