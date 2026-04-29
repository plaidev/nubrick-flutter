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
/// reference: https://docs.nubrick.app/reference/flutter/nubrick
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
  final bool trackCrashes;
  final List<EventHandler> _listeners = [];
  final List<void Function(String)> _onDispatchListeners = [];
  final List<void Function(String, String?)> _onTooltipListeners = [];
  final MethodChannel _channel = const MethodChannel("nubrick_flutter");

  Nubrick(this.projectId, {this.trackCrashes = true}) {
    Nubrick.instance = this;
    NubrickFlutterPlatform.instance.connectClient(projectId);
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
        // Call the previous handler if it exists, otherwise return false to indicate the error was not handled
        return previousPlatformErrorHandler?.call(error, stack) ?? false;
      };
    }
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

  void addOnTooltipListener(void Function(String, String?) listener) {
    _onTooltipListeners.add(listener);
  }

  void removeOnTooltipListener(void Function(String, String?) listener) {
    _onTooltipListeners.remove(listener);
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'on-event':
        final event = parseEvent(call.arguments);
        for (var listener in List.of(_listeners)) {
          listener(event);
        }
        return Future.value(true);
      case 'on-dispatch':
        final name = call.arguments["name"] as String?;
        if (name != null) {
          for (var listener in List.of(_onDispatchListeners)) {
            listener(name);
          }
        }
        return Future.value(true);
      case 'on-tooltip':
        String? data;
        String? experimentId;
        final args = call.arguments;
        if (args is String) {
          data = args;
        } else if (args is Map) {
          data = args["data"] as String?;
          experimentId = args["experimentId"] as String?;
        }
        if (data != null) {
          for (var listener in List.of(_onTooltipListeners)) {
            listener(data, experimentId);
          }
        }
        return Future.value(true);
      default:
        return Future.value(true);
    }
  }
}

