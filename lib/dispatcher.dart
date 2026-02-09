import 'package:nubrick_flutter/channel/nubrick_flutter_platform_interface.dart';

class NubrickEvent {
  final String name;
  NubrickEvent(this.name);
}

/// NubrickDispatcher is the main dispatcher for the Nativebrik SDK.
///
/// reference: https://docs.nativebrik.com/reference/flutter/nativebrikdispatcher
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

  Future<void> dispatch(NubrickEvent event) {
    return NubrickFlutterPlatform.instance.dispatch(event.name);
  }
}
