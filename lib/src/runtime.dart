import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nubrick_flutter/channel/nubrick_flutter_platform_interface.dart';
import 'package:nubrick_flutter/crash_report.dart';
import 'package:nubrick_flutter/event.dart';
import 'package:nubrick_flutter/utils/parse_event.dart';

final nubrickRuntime = NubrickRuntime._internal();

class NubrickRuntime {
  FlutterExceptionHandler? _previousFlutterErrorHandler;
  bool Function(Object, StackTrace)? _previousPlatformErrorHandler;
  bool _crashHandlersInstalled = false;
  bool _trackCrashesEnabled = false;

  String? _projectId;
  bool _isInitialized = false;
  bool _channelHandlerInstalled = false;
  final List<EventHandler> _listeners = [];
  final List<void Function(String)> _onDispatchListeners = [];
  final List<void Function(String, String?)> _onTooltipListeners = [];
  final MethodChannel _channel = const MethodChannel("nubrick_flutter");

  NubrickRuntime._internal();

  bool get isInitialized => _isInitialized;

  void ensureInitialized() {
    if (!_isInitialized) {
      throw StateError(
        'Nubrick must be initialized before use. '
        'Call Nubrick.initialize("PROJECT_ID") first.',
      );
    }
  }

  String get projectId {
    ensureInitialized();
    return _projectId!;
  }

  bool get trackCrashes {
    ensureInitialized();
    return _trackCrashesEnabled;
  }

  void initialize(String projectId, {required bool trackCrashes}) {
    if (_isInitialized) {
      debugPrint(
        'Nubrick.initialize(...) called more than once. '
        'Subsequent calls are ignored.',
      );
      return;
    }

    _projectId = projectId;
    _isInitialized = true;
    _ensureMethodHandlerInstalled();
    NubrickFlutterPlatform.instance.connectClient(projectId);
    _configureCrashTracking(trackCrashes);
  }

  void _ensureMethodHandlerInstalled() {
    if (_channelHandlerInstalled) {
      return;
    }
    _channel.setMethodCallHandler(_handleMethod);
    _channelHandlerInstalled = true;
  }

  void _configureCrashTracking(bool enabled) {
    _trackCrashesEnabled = enabled;
    if (_crashHandlersInstalled || !enabled) {
      return;
    }

    _crashHandlersInstalled = true;
    _previousFlutterErrorHandler = FlutterError.onError;
    FlutterError.onError = (errorDetails) {
      if (_trackCrashesEnabled && errorDetails.stack != null) {
        recordError(
          errorDetails.exception,
          errorDetails.stack!,
        );
      }
      _previousFlutterErrorHandler?.call(errorDetails);
    };

    _previousPlatformErrorHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      if (_trackCrashesEnabled) {
        recordError(error, stack);
      }
      return _previousPlatformErrorHandler?.call(error, stack) ?? false;
    };
  }

  void addEventListener(EventHandler listener) {
    _listeners.add(listener);
  }

  void removeEventListener(EventHandler listener) {
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

  void resetForTest() {
    if (_crashHandlersInstalled) {
      FlutterError.onError = _previousFlutterErrorHandler;
      PlatformDispatcher.instance.onError = _previousPlatformErrorHandler;
    }
    _previousFlutterErrorHandler = null;
    _previousPlatformErrorHandler = null;
    _crashHandlersInstalled = false;
    _trackCrashesEnabled = false;
    _projectId = null;
    _isInitialized = false;
    if (_channelHandlerInstalled) {
      _channel.setMethodCallHandler(null);
    }
    _channelHandlerInstalled = false;
    _listeners.clear();
    _onDispatchListeners.clear();
    _onTooltipListeners.clear();
  }
}
