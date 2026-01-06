import 'package:nativebrik_bridge/channel/nativebrik_bridge_platform_interface.dart';

/// The category of a breadcrumb.
///
/// This categorizes the type of event that occurred.
enum BreadcrumbCategory {
  /// Screen navigation events
  navigation,

  /// User interaction events (taps, clicks, etc.)
  ui,

  /// Network request events
  network,

  /// Console log events
  console,

  /// Custom events
  custom,
}

/// The severity level of a breadcrumb.
enum BreadcrumbLevel {
  /// Debug level
  debug,

  /// Info level
  info,

  /// Warning level
  warning,

  /// Error level
  error,
}

/// NativebrikBreadcrumb is the main class for recording breadcrumbs.
///
/// Breadcrumbs are used to record events that happened before a crash,
/// providing context for debugging.
///
/// reference: https://docs.nativebrik.com/reference/flutter/nativebrikbreadcrumb
///
/// Usage:
/// ```dart
/// NativebrikBreadcrumb.instance.record(
///   message: 'Button tapped',
///   category: BreadcrumbCategory.ui,
/// );
/// ```
class NativebrikBreadcrumb {
  static final NativebrikBreadcrumb _instance = NativebrikBreadcrumb._();

  /// The singleton instance of [NativebrikBreadcrumb].
  static NativebrikBreadcrumb get instance => _instance;

  NativebrikBreadcrumb._();

  /// Creates a new instance of [NativebrikBreadcrumb].
  ///
  /// In most cases, you should use [NativebrikBreadcrumb.instance] instead.
  factory NativebrikBreadcrumb() => _instance;

  /// Records a breadcrumb for crash reporting context.
  ///
  /// [message] is the main message describing the event.
  /// [category] categorizes the type of event (default: [BreadcrumbCategory.custom]).
  /// [level] is the severity level (default: [BreadcrumbLevel.info]).
  /// [data] is optional additional data to attach to the breadcrumb.
  Future<void> record({
    required String message,
    BreadcrumbCategory category = BreadcrumbCategory.custom,
    BreadcrumbLevel level = BreadcrumbLevel.info,
    Map<String, dynamic>? data,
  }) {
    return NativebrikBridgePlatform.instance.recordBreadcrumb({
      'message': message,
      'category': category.name,
      'level': level.name,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
