import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nativebrik_bridge/crash_report.dart';
import 'package:nativebrik_bridge/embedding.dart';
import 'package:nativebrik_bridge/utils/parse_event.dart';
import 'channel/nativebrik_bridge_platform_interface.dart';

// Export public APIs
// Note: Using 'show' to only export deprecated NativebrikCrashReport class.
// Internal crash reporting functions are not exported. The 'show' triggers a
// deprecation warning which is temporary until the class is removed in a future version.
export 'package:nativebrik_bridge/breadcrumb.dart';
export 'package:nativebrik_bridge/crash_report.dart' show NativebrikCrashReport;
export 'package:nativebrik_bridge/dispatcher.dart';
export 'package:nativebrik_bridge/embedding.dart';
export 'package:nativebrik_bridge/provider.dart';
export 'package:nativebrik_bridge/remote_config.dart';
export 'package:nativebrik_bridge/user.dart';
export 'package:nativebrik_bridge/anchor/anchor.dart';

/// A bridge client to the nativebrik SDK.
///
/// - Initialize the bridge with the project ID before using nativebrik SDK.
///
/// reference: https://docs.nativebrik.com/reference/flutter/nativebrikbridge
///
/// Usage:
///
/// ```dart
/// // Setup Nativebrik SDK
/// void main() {
///     WidgetsFlutterBinding.ensureInitialized();
///     // Initialize the bridge with the project ID
///     NativebrikBridge("PROJECT ID");
///     runApp(const YourApp());
/// }
/// ```
class NativebrikBridge {
  static NativebrikBridge? instance;

  final String projectId;
  final NativebrikCachePolicy cachePolicy;
  final bool trackCrashes;
  final List<EventHandler> _listeners = [];
  final List<void Function(String)> _onDispatchListeners = [];
  final MethodChannel _channel = const MethodChannel("nativebrik_bridge");

  NativebrikBridge(this.projectId,
      {this.cachePolicy = const NativebrikCachePolicy(),
      this.trackCrashes = true}) {
    NativebrikBridge.instance = this;
    NativebrikBridgePlatform.instance.connectClient(projectId, cachePolicy);
    _channel.setMethodCallHandler(_handleMethod);

    if (trackCrashes) {
      // Chain existing error handlers
      final previousFlutterErrorHandler = FlutterError.onError;
      FlutterError.onError = (errorDetails) {
        if (errorDetails.stack != null) {
          recordCrash(
            errorDetails.exception,
            errorDetails.stack!,
          );
        }
        // Call the previous handler if it exists
        previousFlutterErrorHandler?.call(errorDetails);
      };

      final previousPlatformErrorHandler = PlatformDispatcher.instance.onError;
      PlatformDispatcher.instance.onError = (error, stack) {
        recordCrash(error, stack);
        // Call the previous handler if it exists, otherwise return true
        return previousPlatformErrorHandler?.call(error, stack) ?? true;
      };
    }
  }

  Future<String?> getNativebrikSDKVersion() {
    return NativebrikBridgePlatform.instance.getNativebrikSDKVersion();
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

/// A policy for caching data from the nativebrik SDK.
///
/// - The cache time is the time to live for the cache. default is 1 day.
/// - The stale time is the time to live for the stale data. default is 0 seconds.
/// - The storage is the storage for the cache. default is inMemory.
///
/// ```dart
class NativebrikCachePolicy {
  final Duration cacheTime;
  final Duration staleTime;
  final CacheStorage storage;

  const NativebrikCachePolicy(
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
