import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nubrick_flutter/crash_report.dart';
import 'package:nubrick_flutter/embedding.dart';
import 'package:nubrick_flutter/utils/parse_event.dart';
import 'channel/nubrick_flutter_platform_interface.dart';

// Export public APIs
export 'package:nubrick_flutter/dispatcher.dart';
export 'package:nubrick_flutter/embedding.dart';
export 'package:nubrick_flutter/provider.dart';
export 'package:nubrick_flutter/remote_config.dart';
export 'package:nubrick_flutter/user.dart';
export 'package:nubrick_flutter/anchor/anchor.dart';

/// A bridge client to the nubrick SDK.
///
/// - Initialize the bridge with the project ID before using nubrick SDK.
///
/// reference: https://docs.nativebrik.com/reference/flutter/nativebrikbridge
///
/// Usage:
///
/// ```dart
/// // Setup Nubrick SDK
/// void main() {
///     WidgetsFlutterBinding.ensureInitialized();
///     // Initialize the bridge with the project ID
///     Nubrick("PROJECT ID");
///     runApp(const YourApp());
/// }
/// ```
class Nubrick {
  static Nubrick? instance;

  final String projectId;
  final NubrickCachePolicy cachePolicy;
  final bool trackCrashes;
  final List<EventHandler> _listeners = [];
  final List<void Function(String)> _onDispatchListeners = [];
  final MethodChannel _channel = const MethodChannel("nubrick_flutter");

  Nubrick(this.projectId,
      {this.cachePolicy = const NubrickCachePolicy(),
      this.trackCrashes = true}) {
    Nubrick.instance = this;
    NubrickFlutterPlatform.instance.connectClient(projectId, cachePolicy);
    _channel.setMethodCallHandler(_handleMethod);

    if (trackCrashes) {
      // Chain existing error handlers
      final previousFlutterErrorHandler = FlutterError.onError;
      FlutterError.onError = (errorDetails) {
        if (errorDetails.stack != null) {
          recordError(
            errorDetails.exception,
            errorDetails.stack!,
          );
        }
        // Call the previous handler if it exists
        previousFlutterErrorHandler?.call(errorDetails);
      };

      final previousPlatformErrorHandler = PlatformDispatcher.instance.onError;
      PlatformDispatcher.instance.onError = (error, stack) {
        recordError(error, stack);
        // Call the previous handler if it exists, otherwise return true
        return previousPlatformErrorHandler?.call(error, stack) ?? true;
      };
    }
  }

  Future<String?> getNubrickSDKVersion() {
    return NubrickFlutterPlatform.instance.getNubrickSDKVersion();
  }

  addEventListener(EventHandler listener) {
    _listeners.add(listener);
  }

  removeEventListener(EventHandler listener) {
    _listeners.remove(listener);
  }

  void addOnDispatchListener(void Function(String) listener) {
    _onDispatchListeners.add(listener);
  }

  void removeOnDispatchListener(void Function(String) listener) {
    _onDispatchListeners.remove(listener);
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'on-event':
        final event = parseEvent(call.arguments);
        for (var listener in _listeners) {
          listener(event);
        }
        return Future.value(true);
      case 'on-dispatch':
        final name = call.arguments["name"] as String?;
        if (name != null) {
          for (var listener in _onDispatchListeners) {
            listener(name);
          }
        }
        return Future.value(true);
      default:
        return Future.value(true);
    }
  }
}

/// A policy for caching data from the nubrick SDK.
///
/// - The cache time is the time to live for the cache. default is 1 day.
/// - The stale time is the time to live for the stale data. default is 0 seconds.
/// - The storage is the storage for the cache. default is inMemory.
///
/// ```dart
class NubrickCachePolicy {
  final Duration cacheTime;
  final Duration staleTime;
  final CacheStorage storage;

  const NubrickCachePolicy(
      {this.cacheTime = const Duration(days: 1),
      this.staleTime = const Duration(seconds: 0),
      this.storage = CacheStorage.inMemory});

  Map<String, dynamic> toObject() {
    return {
      'cacheTime': cacheTime.inSeconds,
      'staleTime': staleTime.inSeconds,
      'storage': storage.name,
    };
  }
}

enum CacheStorage {
  inMemory,
}
