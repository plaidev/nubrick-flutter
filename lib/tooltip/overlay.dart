import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nubrick_flutter/channel/nubrick_flutter_platform_interface.dart';
import 'package:nubrick_flutter/crash_report.dart';
import 'package:nubrick_flutter/schema/generated.dart' as schema;
import 'package:nubrick_flutter/src/runtime.dart';
import 'package:nubrick_flutter/utils/retry.dart';
import 'package:nubrick_flutter/utils/tooltip_animation.dart';
import 'package:nubrick_flutter/utils/tooltip_position.dart';
import 'package:nubrick_flutter/utils/tooltip_visibility.dart';
import 'package:nubrick_flutter/utils/transparent_pointer.dart';

/// @warning This is the internal overlay view for the tooltip.
///
/// DO NOT USE THIS CLASS DIRECTLY.
///
/// Use [NubrickProvider] instead.
class NubrickTooltipOverlay extends StatefulWidget {
  final Map<String, GlobalKey> keysReference;
  const NubrickTooltipOverlay({super.key, required this.keysReference});

  @override
  State<NubrickTooltipOverlay> createState() => NubrickTooltipOverlayState();
}

class NubrickTooltipOverlayState extends State<NubrickTooltipOverlay> {
  // Anchor lookup retry configuration.
  static const int _initialTooltipLookupRetries = 30;
  static const Duration _initialTooltipLookupDelay =
      Duration(milliseconds: 200);
  static const int _nextTooltipLookupRetries = 30;
  static const Duration _nextTooltipLookupDelay = Duration(milliseconds: 100);
  // Anchor visibility heuristics used during next-tooltip lookup.
  static const double _minAnchorSize = 2.0;
  // Hide displayed tooltip only after transient failures persist for N frames.
  static const int _hideAfterConsecutiveFailureFrames = 3;

  schema.UIRootBlock? _rootBlock;
  String _channelId = '';
  MethodChannel? _channel;
  schema.UIPageBlock? _currentPage;
  // Incremented whenever a new tooltip flow starts (or current one is reset).
  // Async callbacks keep the id they started with and ignore stale work.
  int _currentTooltipFlowId = 0;
  // Incremented for each tooltip-step transition within a flow.
  int _currentTooltipTransitionId = 0;
  int _consecutiveFullyOffscreenFrames = 0;
  int _consecutiveUnresolvableDataFrames = 0;
  bool _isAnimateHole = false;
  Offset? _anchorPosition;
  Size? _anchorSize;
  Offset? _tooltipPosition;
  Size? _tooltipSize;
  // True while the per-frame position update loop is running.
  bool _isFrameLoopActive = false;
  // True while showing the temporary dim barrier between tooltip steps.
  bool _isTransitioningToNextTooltip = false;
  // Local rendering state. Native decides whether an experiment may start.
  bool get _isTooltipFlowActive => _channelId.isNotEmpty;
  // Tracks current in-flight next-tooltip target to dedupe duplicate requests.
  String? _pendingNextTooltipPageId;
  String? _currentTooltipExperimentId;
  String? _currentTooltipVariantId;
  bool _didAppendCurrentTooltipHistory = false;

  bool _isAnchorOnCurrentRoute(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route == null) {
      return true;
    }
    return route.isCurrent;
  }

  schema.UIPageBlock? _findPageInListById(
      List<schema.UIPageBlock>? pages, String pageId) {
    if (pages == null) {
      return null;
    }
    for (final page in pages) {
      if (page.id == pageId) {
        return page;
      }
    }
    return null;
  }

  bool _isAnchorTooSmall(Size anchorSize) {
    return anchorSize.width < _minAnchorSize ||
        anchorSize.height < _minAnchorSize;
  }

  void _startNextTooltipTransition() {
    _isFrameLoopActive = false;
    _consecutiveFullyOffscreenFrames = 0;
    _consecutiveUnresolvableDataFrames = 0;
    final wasTooltipVisible = _anchorPosition != null &&
        _anchorSize != null &&
        _tooltipPosition != null &&
        _tooltipSize != null &&
        _currentPage != null;
    _isTransitioningToNextTooltip = wasTooltipVisible;
    if (!wasTooltipVisible) {
      return;
    }
    setState(() {
      _anchorPosition = null;
      _anchorSize = null;
      _tooltipPosition = null;
      _tooltipSize = null;
      _currentPage = null;
      _isAnimateHole = false;
    });
  }

  int _nextTooltipTransitionId() {
    _currentTooltipTransitionId += 1;
    return _currentTooltipTransitionId;
  }

  void _onTooltip(String data, String? experimentId, String? variantId,
      String sessionId) async {
    // Native has already reserved this session.
    if (_isTooltipFlowActive) _stopTooltipFlow(stoppedByFlutter: false);

    final decodedData = jsonDecode(data);
    _channelId = sessionId;
    if (experimentId == null || experimentId.isEmpty) {
      _stopTooltipFlow();
      return;
    }
    var uiroot = schema.UIRootBlock.decode(decodedData);
    if (uiroot == null) {
      _stopTooltipFlow();
      return;
    }
    _rootBlock = uiroot;
    var currentPageId = uiroot.data?.currentPageId;
    if (currentPageId == null) {
      _stopTooltipFlow();
      return;
    }
    final pages = uiroot.data?.pages;
    if (pages == null) {
      _stopTooltipFlow();
      return;
    }
    final page = _findPageInListById(pages, currentPageId);
    if (page == null) {
      _stopTooltipFlow();
      return;
    }
    var destinationId = page.data?.triggerSetting?.onTrigger?.destinationPageId;
    if (destinationId == null) {
      _stopTooltipFlow();
      return;
    }
    final destinationPage = _findPageInListById(pages, destinationId);
    if (destinationPage == null) {
      _stopTooltipFlow();
      return;
    }

    _consecutiveFullyOffscreenFrames = 0;
    _consecutiveUnresolvableDataFrames = 0;
    _currentTooltipExperimentId = experimentId;
    _currentTooltipVariantId = variantId;
    _didAppendCurrentTooltipHistory = false;
    _currentTooltipFlowId += 1;
    final flowId = _currentTooltipFlowId;
    final transitionId = _nextTooltipTransitionId();
    _channel = MethodChannel("Nubrick/Embedding/$sessionId");
    _channel!.setMethodCallHandler((call) async {
      if (!mounted || flowId != _currentTooltipFlowId) return false;
      return _handleMethod(call);
    });

    try {
      if (!nubrickRuntime.isReady) {
        await nubrickRuntime.ready;
      }
      if (!mounted || flowId != _currentTooltipFlowId) {
        return;
      }
      final result = await NubrickFlutterPlatform.instance.connectTooltipEmbedding(
          sessionId,
          experimentId,
          variantId,
          schema.UIRootBlock(
            id: uiroot.id,
            data: schema.UIRootBlockData(
              currentPageId: destinationId,
              pages: uiroot.data?.pages,
            ),
          ));
      if (result != 'ok') {
        if (mounted && flowId == _currentTooltipFlowId) _stopTooltipFlow();
        return;
      }
    } catch (e, stackTrace) {
      if (mounted && flowId == _currentTooltipFlowId) _stopTooltipFlow();
      recordError(e, stackTrace, severity: ErrorSeverity.warning);
      return;
    }

    if (!mounted || flowId != _currentTooltipFlowId) {
      await NubrickFlutterPlatform.instance.disconnectTooltipEmbedding(
          sessionId, stoppedByFlutter: false);
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      retryUntilTrue(
        fn: () => _onNextTooltip(
          destinationId,
          flowId: flowId,
          transitionId: transitionId,
        ),
        retries: _initialTooltipLookupRetries, // 30 * 200 = 6 seconds timeout
        delay: _initialTooltipLookupDelay,
      ).then((resolved) {
        if (!resolved &&
            mounted &&
            flowId == _currentTooltipFlowId &&
            transitionId == _currentTooltipTransitionId) {
          _stopTooltipFlow();
        }
      });
    });
    // Post-frame callbacks alone do not request a frame on an idle screen.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// calculate the anchor position, size, tooltip position, size
  /// return the result if successful, return null if failed
  _TooltipPositionData? _calculateTooltipPositionData(
      schema.UIPageBlock? page) {
    if (page == null) {
      return null;
    }
    final anchorId = page.data?.tooltipAnchor;
    if (anchorId == null) {
      return null;
    }
    final key = widget.keysReference[anchorId];
    if (key == null) {
      return null;
    }
    final context = key.currentContext;
    if (context == null || !context.mounted) {
      return null;
    }

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) {
      return null;
    }

    late final Offset anchorPosition;
    late final Size anchorSize;
    try {
      anchorPosition = box.localToGlobal(Offset.zero);
      anchorSize = box.size;
    } on StateError {
      return null;
    } on FlutterError {
      return null;
    }

    final tooltipSize = page.data?.tooltipSize;
    if (tooltipSize == null) {
      return null;
    }
    final tooltipSizeValue = (tooltipSize.width != null &&
            tooltipSize.height != null)
        ? Size(tooltipSize.width!.toDouble(), tooltipSize.height!.toDouble())
        : null;
    if (tooltipSizeValue == null) {
      return null;
    }

    final screenSize = MediaQuery.of(context).size;
    final tooltipPosition = calculateTooltipPosition(
      anchorPosition: anchorPosition,
      anchorSize: anchorSize,
      tooltipSize: tooltipSizeValue,
      screenSize: screenSize,
      placement: page.data?.tooltipPlacement ??
          schema.UITooltipPlacement.BOTTOM_CENTER,
    );

    return _TooltipPositionData(
      anchorPosition: anchorPosition,
      anchorSize: anchorSize,
      tooltipPosition: tooltipPosition,
      tooltipSize: tooltipSizeValue,
      context: context,
    );
  }

  Future<bool> _onNextTooltip(
    String pageId, {
    required int flowId,
    required int transitionId,
  }) async {
    if (!_isTooltipFlowActive) {
      return true;
    }
    if (!mounted ||
        flowId != _currentTooltipFlowId ||
        transitionId != _currentTooltipTransitionId) {
      return true;
    }

    // find the page
    final page = _findPageInListById(_rootBlock?.data?.pages, pageId);
    if (page == null) {
      return false;
    }

    final data = _calculateTooltipPositionData(page);
    if (data == null) {
      return false;
    }

    if (_isAnchorTooSmall(data.anchorSize)) {
      return false;
    }

    if (!_isAnchorOnCurrentRoute(data.context)) {
      return false;
    }
    final isVisible = isTooltipAnchorVisible(data.context);
    if (isVisible == null) return false;
    if (!isVisible) {
      await Scrollable.ensureVisible(
        data.context,
        // Center the anchor in its scroll viewport to leave space around the
        // highlight when scroll limits allow.
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      // Remeasure after scrolling before displaying the highlight.
      return false;
    }

    if (!mounted ||
        flowId != _currentTooltipFlowId ||
        transitionId != _currentTooltipTransitionId) {
      return true;
    }

    final willAnimateHole =
        getTransitionTarget(page) == schema.UITooltipTransitionTarget.ANCHOR &&
            page.data?.triggerSetting?.onTrigger != null;

    setState(() {
      _currentPage = page;
      _anchorPosition = data.anchorPosition;
      _anchorSize = data.anchorSize;
      _tooltipPosition = data.tooltipPosition;
      _tooltipSize = data.tooltipSize;
      _isAnimateHole = willAnimateHole;
      _isTransitioningToNextTooltip = false;
    });
    _consecutiveFullyOffscreenFrames = 0;
    _consecutiveUnresolvableDataFrames = 0;
    _pendingNextTooltipPageId = null;
    if (!_didAppendCurrentTooltipHistory) {
      final experimentId = _currentTooltipExperimentId;
      final variantId = _currentTooltipVariantId;
      if (experimentId != null && variantId != null && variantId.isNotEmpty) {
        _didAppendCurrentTooltipHistory = true;
        NubrickFlutterPlatform.instance
            .appendTooltipExperimentHistory(experimentId, variantId,
                channelId: _channelId)
            .catchError((e, stackTrace) {
          recordError(e, stackTrace, severity: ErrorSeverity.warning);
        });
      }
    }

    // register the frame callback when the tooltip is shown
    _registerFrameCallback();

    return true;
  }

  void _startNextTooltipLookup(String pageId) {
    if (!_isTooltipFlowActive) {
      return;
    }
    if (_isTransitioningToNextTooltip && _pendingNextTooltipPageId == pageId) {
      return;
    }
    _pendingNextTooltipPageId = pageId;
    _startNextTooltipTransition();
    final flowId = _currentTooltipFlowId;
    final transitionId = _nextTooltipTransitionId();
    retryUntilTrue(
      fn: () => _onNextTooltip(
        pageId,
        flowId: flowId,
        transitionId: transitionId,
      ),
      retries: _nextTooltipLookupRetries,
      delay: _nextTooltipLookupDelay,
    ).then((resolved) {
      if (!resolved &&
          mounted &&
          flowId == _currentTooltipFlowId &&
          transitionId == _currentTooltipTransitionId) {
        _stopTooltipFlow();
      }
    });
  }

  void _updateTooltipPosition() {
    if (_currentPage == null || _anchorPosition == null) {
      return;
    }
    final page = _currentPage;
    final data = _calculateTooltipPositionData(page);
    if (data == null) {
      _consecutiveUnresolvableDataFrames += 1;
      if (_consecutiveUnresolvableDataFrames >=
          _hideAfterConsecutiveFailureFrames) {
        _stopTooltipFlow();
      }
      return;
    }
    _consecutiveUnresolvableDataFrames = 0;
    if (!_isAnchorOnCurrentRoute(data.context)) {
      _stopTooltipFlow();
      return;
    }
    if (isTooltipAnchorVisible(data.context) != true) {
      _consecutiveFullyOffscreenFrames += 1;
      if (_consecutiveFullyOffscreenFrames >=
          _hideAfterConsecutiveFailureFrames) {
        _stopTooltipFlow();
      }
      return;
    }
    _consecutiveFullyOffscreenFrames = 0;

    // do nothing if the position or size is not changed
    if (_anchorPosition == data.anchorPosition &&
        _anchorSize == data.anchorSize &&
        _tooltipPosition != null &&
        _tooltipSize != null) {
      return;
    }

    setState(() {
      _anchorPosition = data.anchorPosition;
      _anchorSize = data.anchorSize;
      _tooltipPosition = data.tooltipPosition;
      _tooltipSize = data.tooltipSize;
    });
  }

  void _registerFrameCallback() {
    if (_isFrameLoopActive) {
      return;
    }
    _isFrameLoopActive = true;
    WidgetsBinding.instance.addPostFrameCallback(_onFrame);
  }

  void _onFrame(Duration timestamp) {
    if (!mounted) {
      _isFrameLoopActive = false;
      return;
    }

    // do nothing if the tooltip is not shown
    if (!_isFrameLoopActive ||
        _anchorPosition == null ||
        _currentPage == null) {
      return;
    }

    _updateTooltipPosition();

    if (_isFrameLoopActive && mounted) {
      WidgetsBinding.instance.addPostFrameCallback(_onFrame);
    }
  }

  void _disconnectTooltip({required bool stoppedByFlutter}) {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    final channelId = _channelId;
    _channelId = '';
    if (channelId.isEmpty) return;
    NubrickFlutterPlatform.instance
        .disconnectTooltipEmbedding(channelId,
            stoppedByFlutter: stoppedByFlutter)
        .catchError((e, stackTrace) {
      recordError(e, stackTrace, severity: ErrorSeverity.warning);
      return null;
    });
  }

  void _stopTooltipFlow({bool stoppedByFlutter = true}) {
    _currentTooltipFlowId += 1;
    _currentTooltipTransitionId += 1;
    _consecutiveFullyOffscreenFrames = 0;
    _consecutiveUnresolvableDataFrames = 0;
    _isFrameLoopActive = false;
    _isTransitioningToNextTooltip = false;
    _pendingNextTooltipPageId = null;
    _currentTooltipExperimentId = null;
    _currentTooltipVariantId = null;
    _didAppendCurrentTooltipHistory = false;
    setState(() {
      _anchorPosition = null;
      _anchorSize = null;
      _tooltipPosition = null;
      _tooltipSize = null;
      _rootBlock = null;
      _currentPage = null;
    });
    _disconnectTooltip(stoppedByFlutter: stoppedByFlutter);
  }

  void _onTransitionTargetTap(bool isInAnchor) {
    if (_currentPage == null) {
      return;
    }
    if (_currentPage?.data?.kind != schema.PageKind.TOOLTIP) {
      return;
    }
    final target = getTransitionTarget(_currentPage);
    if (target == schema.UITooltipTransitionTarget.ANCHOR && !isInAnchor) {
      // if the transiation target is anchor, but the isInAnchor is not true, then do nothing.
      return;
    }
    var onTrigger = _currentPage?.data?.triggerSetting?.onTrigger;
    if (onTrigger == null) {
      return;
    }
    if (_channelId.isEmpty) {
      return;
    }
    // Pause per-frame visibility checks while native handles transition.
    // This avoids hiding the current flow during legitimate page/route changes.
    _isFrameLoopActive = false;
    _consecutiveFullyOffscreenFrames = 0;
    _consecutiveUnresolvableDataFrames = 0;
    final flowId = _currentTooltipFlowId;
    final transitionId = _currentTooltipTransitionId;
    final channelId = _channelId;
    (() async {
      if (!nubrickRuntime.isReady) {
        await nubrickRuntime.ready;
      }
      await NubrickFlutterPlatform.instance
          .callTooltipEmbeddingDispatch(channelId, onTrigger);
    })()
        .catchError((e, stackTrace) {
      if (mounted &&
          flowId == _currentTooltipFlowId &&
          transitionId == _currentTooltipTransitionId) {
        _stopTooltipFlow();
      }
      recordError(e, stackTrace, severity: ErrorSeverity.warning);
    });
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'on-next-tooltip':
        if (!_isTooltipFlowActive) {
          return Future.value(true);
        }
        final pageId = call.arguments["pageId"] as String;
        _startNextTooltipLookup(pageId);
        return Future.value(true);
      case 'on-dismiss-tooltip':
        if (!_isTooltipFlowActive) {
          return Future.value(true);
        }
        _stopTooltipFlow(stoppedByFlutter: false);
        return Future.value(true);
      default:
        return Future.value(false);
    }
  }

  @override
  void initState() {
    super.initState();
    nubrickRuntime.addInternalTooltipListener(_onTooltip);
  }

  @override
  void dispose() {
    _currentTooltipFlowId += 1;
    nubrickRuntime.removeInternalTooltipListener(_onTooltip);
    _disconnectTooltip(stoppedByFlutter: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return _renderTooltip(context);
      case TargetPlatform.android:
        return _renderTooltip(context);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _renderTooltip(BuildContext context) {
    final visible = _anchorPosition != null &&
        _anchorSize != null &&
        _tooltipPosition != null &&
        _tooltipSize != null;
    if (!visible && _isTransitioningToNextTooltip) {
      return const ColoredBox(
        color: Color.fromARGB(150, 0, 0, 0),
        child: SizedBox.expand(),
      );
    }
    if (visible) {
      if (_isAnchorTooSmall(_anchorSize!)) {
        return const SizedBox.shrink();
      }
      final screenSize = MediaQuery.of(context).size;
      Widget tooltipWidget = AnimationFrame(
        position: _tooltipPosition!,
        size: _tooltipSize!,
        builder: (context, position, size, fade, scale, _) {
          return Transform.translate(
            offset: position,
            child: FadeTransition(
              opacity: fade,
              child: ScaleTransition(
                scale: scale,
                child: Material(
                  color: Colors.transparent,
                  elevation: 99999,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: size.width,
                    height: size.height,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(20),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                          spreadRadius: 16,
                        ),
                      ],
                    ),
                    child: _renderEmbedding(context),
                  ),
                ),
              ),
            ),
          );
        },
      );
      // Custom barrier with transparent hole over anchor
      return Stack(
        children: [
          AnimationFrame(
            position: _anchorPosition!,
            size: _anchorSize!,
            animateHole: _isAnimateHole,
            builder: (context, position, size, fade, scale, hole) {
              return TransparentPointer(
                transparent: _isAnimateHole,
                transparentRect: Rect.fromLTWH(
                  position.dx,
                  position.dy,
                  size.width,
                  size.height,
                ),
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerUp: (details) {
                    final tapPos = details.position;
                    final anchorRect = Rect.fromLTWH(
                      position.dx,
                      position.dy,
                      size.width,
                      size.height,
                    );
                    if (anchorRect.contains(tapPos)) {
                      _onTransitionTargetTap(true);
                    } else {
                      _onTransitionTargetTap(false);
                    }
                  },
                  child: CustomPaint(
                    size: screenSize,
                    painter: _BarrierWithHolePainter(
                      anchorRect: Rect.fromLTWH(
                        position.dx,
                        position.dy,
                        size.width,
                        size.height,
                      ).inflate(8.0 * hole),
                      borderRadius: 8.0,
                      color: const Color.fromARGB(150, 0, 0, 0),
                    ),
                  ),
                ),
              );
            },
          ),
          tooltipWidget,
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _renderEmbedding(BuildContext context) {
    if (_channelId.isEmpty) {
      return const SizedBox.shrink();
    }
    const String viewType = "nubrick-embedding-view";
    final Map<String, dynamic> creationParams = <String, dynamic>{
      "channelId": _channelId,
      "arguments": {},
    };
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return UiKitView(
          key: ValueKey(_channelId),
          viewType: viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          gestureRecognizers: {
            // Maybe we need to pass other gesture recognizers.
            // This suppport only horizontal drag like horizontal swipe.
            Factory<OneSequenceGestureRecognizer>(
                () => HorizontalDragGestureRecognizer()),
          },
        );
      case TargetPlatform.android:
        return AndroidView(
          key: ValueKey(_channelId),
          viewType: viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          gestureRecognizers: {
            // Maybe we need to pass other gesture recognizers.
            // This suppport only horizontal drag like horizontal swipe.
            Factory<OneSequenceGestureRecognizer>(
                () => HorizontalDragGestureRecognizer()),
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// Custom painter for the barrier with a transparent hole
class _BarrierWithHolePainter extends CustomPainter {
  final Rect anchorRect;
  final double borderRadius;
  final Color color;
  _BarrierWithHolePainter(
      {required this.anchorRect,
      required this.borderRadius,
      required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(
          RRect.fromRectAndRadius(anchorRect, Radius.circular(borderRadius)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

schema.UITooltipTransitionTarget getTransitionTarget(schema.UIPageBlock? page) {
  return page?.data?.tooltipTransitionTarget ??
      schema.UITooltipTransitionTarget.ANCHOR;
}

class _TooltipPositionData {
  final Offset anchorPosition;
  final Size anchorSize;
  final Offset tooltipPosition;
  final Size tooltipSize;
  final BuildContext context;

  _TooltipPositionData({
    required this.anchorPosition,
    required this.anchorSize,
    required this.tooltipPosition,
    required this.tooltipSize,
    required this.context,
  });
}
