import 'package:flutter/foundation.dart';
import 'package:nubrick_flutter/event.dart';
import 'package:nubrick_flutter/src/runtime.dart';

// Export public APIs
export 'package:nubrick_flutter/dispatcher.dart';
export 'package:nubrick_flutter/embedding.dart';
export 'package:nubrick_flutter/event.dart';
export 'package:nubrick_flutter/provider.dart';
export 'package:nubrick_flutter/remote_config.dart';
export 'package:nubrick_flutter/user.dart';
export 'package:nubrick_flutter/anchor/anchor.dart';

/// A bridge client to the nubrick SDK.
///
/// - Initialize the bridge with the project ID before using nubrick SDK.
///
/// reference: https://docs.nubrick.app/reference/flutter/nubrick
///
/// Usage:
///
/// ```dart
/// // Setup Nubrick SDK
/// void main() {
///     WidgetsFlutterBinding.ensureInitialized();
///     // Initialize the bridge with the project ID
///     Nubrick.initialize("PROJECT ID");
///     runApp(const YourApp());
/// }
/// ```
class Nubrick {
  // Legacy object kept only so the deprecated instance-based API can keep
  // returning a stable value while callers migrate to the static/runtime API.
  // Remove this once the compatibility surface is dropped in a future release.
  static final Nubrick _singleton = Nubrick._();

  Nubrick._();

  @Deprecated('Use Nubrick.initialize(projectId, trackCrashes: ...) instead.')
  factory Nubrick(String projectId, {bool trackCrashes = true}) {
    initialize(projectId, trackCrashes: trackCrashes);
    return _singleton;
  }

  /// Initializes Nubrick once for the current process.
  ///
  /// Subsequent calls are ignored and a warning is logged.
  /// The first initialization wins.
  static void initialize(String projectId, {bool trackCrashes = true}) {
    nubrickRuntime.initialize(projectId, trackCrashes: trackCrashes);
  }

  @Deprecated('Use the static Nubrick API directly instead of Nubrick.instance.')
  static Nubrick? get instance =>
      nubrickRuntime.isInitialized ? _singleton : null;

  static String get projectId => nubrickRuntime.projectId;

  static void addEventListener(EventHandler listener) {
    nubrickRuntime.addEventListener(listener);
  }

  static void removeEventListener(EventHandler listener) {
    nubrickRuntime.removeEventListener(listener);
  }

  static void addOnDispatchListener(void Function(String) listener) {
    nubrickRuntime.addOnDispatchListener(listener);
  }

  static void removeOnDispatchListener(void Function(String) listener) {
    nubrickRuntime.removeOnDispatchListener(listener);
  }

  static void addOnTooltipListener(void Function(String, String?) listener) {
    nubrickRuntime.addOnTooltipListener(listener);
  }

  static void removeOnTooltipListener(void Function(String, String?) listener) {
    nubrickRuntime.removeOnTooltipListener(listener);
  }

  @visibleForTesting
  static void resetForTest() {
    nubrickRuntime.resetForTest();
  }
}

// Temporary compatibility layer for older `Nubrick.instance` call sites.
// These forwards should be removed with the deprecated instance API.
extension NubrickInstanceCompatibility on Nubrick {
  @Deprecated('Use Nubrick.projectId instead.')
  String get projectId => Nubrick.projectId;

  @Deprecated(
    'Use the trackCrashes argument passed to '
    'Nubrick.initialize(projectId, trackCrashes: ...) instead.',
  )
  bool get trackCrashes => nubrickRuntime.trackCrashes;

  @Deprecated('Use Nubrick.addEventListener(listener) instead.')
  void addEventListener(EventHandler listener) {
    Nubrick.addEventListener(listener);
  }

  @Deprecated('Use Nubrick.removeEventListener(listener) instead.')
  void removeEventListener(EventHandler listener) {
    Nubrick.removeEventListener(listener);
  }

  @Deprecated('Use Nubrick.addOnDispatchListener(listener) instead.')
  void addOnDispatchListener(void Function(String) listener) {
    Nubrick.addOnDispatchListener(listener);
  }

  @Deprecated('Use Nubrick.removeOnDispatchListener(listener) instead.')
  void removeOnDispatchListener(void Function(String) listener) {
    Nubrick.removeOnDispatchListener(listener);
  }

  @Deprecated('Use Nubrick.addOnTooltipListener(listener) instead.')
  void addOnTooltipListener(void Function(String, String?) listener) {
    Nubrick.addOnTooltipListener(listener);
  }

  @Deprecated('Use Nubrick.removeOnTooltipListener(listener) instead.')
  void removeOnTooltipListener(void Function(String, String?) listener) {
    Nubrick.removeOnTooltipListener(listener);
  }
}
