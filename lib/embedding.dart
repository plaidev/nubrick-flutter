import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nubrick_flutter/remote_config.dart';
import 'package:nubrick_flutter/utils/random.dart';
import 'package:nubrick_flutter/utils/parse_event.dart';
import './channel/nubrick_flutter_platform_interface.dart';

enum EventPayloadType { integer, string, timestamp, unknown }

class EventPayload {
  final String name;
  final String value;
  final EventPayloadType type;
  EventPayload(this.name, this.value, this.type);
}

class Event {
  final String? name;
  final String? deepLink;
  final List<EventPayload>? payload;
  Event(this.name, this.deepLink, this.payload);
}

typedef EventHandler = void Function(Event event);
typedef EmbeddingBuilder = Widget Function(
    BuildContext context, EmbeddingPhase phase, Widget child);

/// A widget that embeds an experiment.
///
/// - **Nubrick** must be initialized before using this widget.
///
/// reference: https://docs.nativebrik.com/reference/flutter/nativebrikembedding
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
      case 'embedding-size-update':
        if (!mounted) return Future.value(true);
        final args = Map<String, dynamic>.from(call.arguments);
        setState(() {
          _embeddingWidth = args["width"]?.toDouble();
          _embeddingHeight = args["height"]?.toDouble();
        });
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
        return _renderWithBuilder(
            context, const Center(child: Text("Failed to load embedding")));
      case EmbeddingPhase.notFound:
        return _renderWithBuilder(
            context, const Center(child: Text("Embedding not found")));
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
