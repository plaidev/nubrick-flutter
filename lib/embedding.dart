import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nubrick_flutter/event.dart';
import 'package:nubrick_flutter/remote_config.dart';
import 'package:nubrick_flutter/src/runtime.dart';
import 'package:nubrick_flutter/utils/random.dart';
import 'package:nubrick_flutter/utils/parse_event.dart';
import './channel/nubrick_flutter_platform_interface.dart';

export 'package:nubrick_flutter/event.dart';

typedef EmbeddingBuilder = Widget Function(
    BuildContext context, EmbeddingPhase phase, Widget child);
typedef EmbeddingSizeHandler = void Function(
    NubrickSize width, NubrickSize height);

NubrickSize _nubrickSizeFromMessage(dynamic value) {
  if (value == null) {
    return const NubrickFillSize();
  }
  final map = Map<Object?, Object?>.from(value as Map);
  switch (map['kind']) {
    case 'fixed':
      final fixedValue = map['value'];
      if (fixedValue is num) {
        return NubrickFixedSize(fixedValue.toDouble());
      }
      return const NubrickFillSize();
    case 'fill':
    default:
      return const NubrickFillSize();
  }
}

sealed class NubrickSize {
  const NubrickSize();
}

final class NubrickFixedSize extends NubrickSize {
  final double value;

  const NubrickFixedSize(this.value);

  @override
  bool operator ==(Object other) =>
      other is NubrickFixedSize && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'NubrickSize.fixed($value)';
}

final class NubrickFillSize extends NubrickSize {
  const NubrickFillSize();

  @override
  bool operator ==(Object other) => other is NubrickFillSize;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'NubrickSize.fill';
}

/// A widget that embeds an experiment.
///
/// - **Nubrick** must be initialized before using this widget.
///
/// reference: https://docs.nubrick.app/reference/flutter/nubrickembedding
///
/// Usage:
/// ```dart
/// // Embedding with default height
/// Embedding("ID OR CUSTOM ID", height: 300);
///
/// // Embedding with custom builder
/// Embedding("ID OR CUSTOM ID", builder: (context, phase, child) {
///  return phase == EmbeddingPhase.loading
///     ? const Center(child: CircularProgressIndicator())
///    : child;
/// });
///
/// // Embedding with remoteconfig.variant
/// var config = RemoteConfig("ID OR CUSTOM ID");
/// var variant = await config.fetch();
/// Embedding("Config Key", variant: variant);
/// ```
class NubrickEmbedding extends StatefulWidget {
  final String id;
  final double? width;
  final double? height;
  final dynamic arguments;
  final EventHandler? onEvent;
  final EmbeddingSizeHandler? onSizeChange;
  final EmbeddingBuilder? builder;

  // this is used from remoteconfig.embed
  final NubrickRemoteConfigVariant? variant;

  const NubrickEmbedding(
    this.id, {
    super.key,
    this.width,
    this.height,
    this.arguments,
    this.onEvent,
    this.onSizeChange,
    this.variant,
    this.builder,
  });

  @override
  // ignore: library_private_types_in_public_api
  _EmbeddingState createState() => _EmbeddingState();
}

enum EmbeddingPhase {
  loading,
  failed,
  notFound,
  completed,
}

class _EmbeddingState extends State<NubrickEmbedding> {
  var _phase = EmbeddingPhase.loading;
  final _channelId = generateRandomString(32);
  late final MethodChannel _embeddingChannel;
  double? _embeddingWidth;
  double? _embeddingHeight;

  @override
  void initState() {
    super.initState();
    nubrickRuntime.ensureInitialized();
    _embeddingChannel = MethodChannel("Nubrick/Embedding/$_channelId");
    _embeddingChannel.setMethodCallHandler(_handleMethod);

    final variant = widget.variant;
    if (variant != null) {
      NubrickFlutterPlatform.instance.connectEmbeddingInRemoteConfigValue(
          widget.id, variant.channelId, _channelId, widget.arguments);
    } else {
      NubrickFlutterPlatform.instance
          .connectEmbedding(widget.id, _channelId, widget.arguments);
    }
  }

  @override
  void dispose() {
    _embeddingChannel.setMethodCallHandler(null);
    NubrickFlutterPlatform.instance.disconnectEmbedding(_channelId);
    super.dispose();
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'embedding-phase-update':
        if (!mounted) return Future.value(true);
        String phase = call.arguments as String;
        setState(() {
          _phase = switch (phase) {
            "loading" => EmbeddingPhase.loading,
            "not-found" => EmbeddingPhase.notFound,
            "failed" => EmbeddingPhase.failed,
            "completed" => EmbeddingPhase.completed,
            _ => EmbeddingPhase.loading,
          };
        });
        return Future.value(true);
      // embedding-initial-size: Android only — Flutter's AndroidView gives zero
      // space to embedded Compose content, so no size-update would ever fire.
      // This provides an initial size so Compose has space to render. Not needed
      // on iOS. Does not trigger onSizeChange.
      case 'embedding-initial-size':
      case 'embedding-size-update':
        if (!mounted) return Future.value(true);
        final args = Map<String, dynamic>.from(call.arguments);
        final width = _nubrickSizeFromMessage(args["width"]);
        final height = _nubrickSizeFromMessage(args["height"]);
        setState(() {
          _embeddingWidth = width is NubrickFixedSize ? width.value : null;
          _embeddingHeight = height is NubrickFixedSize ? height.value : null;
        });
        if (call.method == 'embedding-size-update') {
          widget.onSizeChange?.call(width, height);
        }
        return Future.value(true);
      case 'on-event':
        if (widget.onEvent == null) return Future.value(false);
        widget.onEvent?.call(parseEvent(call.arguments));
        return Future.value(true);
      default:
        return Future.value(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height ?? _embeddingHeight,
      width: widget.width ?? _embeddingWidth,
      child: _renderByPhase(context),
    );
  }

  Widget _renderByPhase(BuildContext context) {
    switch (_phase) {
      case EmbeddingPhase.loading:
        return _renderWithBuilder(
            context, const Center(child: CircularProgressIndicator()));
      case EmbeddingPhase.failed:
        return _renderWithBuilder(context, const SizedBox.shrink());
      case EmbeddingPhase.notFound:
        return _renderWithBuilder(context, const SizedBox.shrink());
      case EmbeddingPhase.completed:
        return _renderWithBuilder(context,
            Center(child: _BridgeView(_channelId, widget.arguments)));
    }
  }

  Widget _renderWithBuilder(BuildContext context, Widget child) {
    if (widget.builder != null) {
      return widget.builder!(context, _phase, child);
    }
    return child;
  }
}

class _BridgeView extends StatelessWidget {
  final String channelId;
  final dynamic arguments;

  const _BridgeView(this.channelId, this.arguments);

  @override
  Widget build(BuildContext context) {
    const String viewType = "nubrick-embedding-view";
    final Map<String, dynamic> creationParams = <String, dynamic>{
      "channelId": channelId,
      "arguments": arguments,
    };
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return UiKitView(
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
