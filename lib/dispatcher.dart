import 'package:nubrick_flutter/channel/nubrick_flutter_platform_interface.dart';
import 'package:nubrick_flutter/src/event_property_codec.dart';
import 'package:nubrick_flutter/src/runtime.dart';

class NubrickEvent {
  final String name;

  /// Supported values are int, double, String, bool, and DateTime.
  /// Unsupported values and non-finite doubles are omitted.
  final Map<String, Object> properties;

  /// Creates an event with a snapshot of its properties.
  ///
  /// For example, `NubrickEvent('purchase', properties: {'price': 19.99})`.
  NubrickEvent(this.name, {Map<String, Object?> properties = const {}})
      : properties = Map.unmodifiable(normalizeEventProperties(properties));
}

/// NubrickDispatcher is the main dispatcher for the Nubrick SDK.
///
/// reference: https://docs.nubrick.app/reference/flutter/nubrickdispatcher
///
/// Usage:
/// ```dart
/// NubrickDispatcher.instance.dispatch(NubrickEvent('event_name'));
/// ```
class NubrickDispatcher {
  static final NubrickDispatcher _instance = NubrickDispatcher._();

  /// The singleton instance of [NubrickDispatcher].
  static NubrickDispatcher get instance => _instance;

  NubrickDispatcher._();

  /// Creates a new instance of [NubrickDispatcher].
  ///
  /// In most cases, you should use [NubrickDispatcher.instance] instead.
  factory NubrickDispatcher() => _instance;

  Future<void> dispatch(NubrickEvent event) async {
    if (!nubrickRuntime.isReady) {
      await nubrickRuntime.ready;
    }
    if (event.properties.isEmpty) {
      await NubrickFlutterPlatform.instance.dispatch(event.name);
    } else {
      await NubrickFlutterPlatform.instance
          .dispatchWithProperties(event.name, event.properties);
    }
  }
}
