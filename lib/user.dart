import 'package:nubrick_bridge/channel/nubrick_bridge_platform_interface.dart';

/// A class to handle NubrickUser.
///
/// reference: https://docs.nativebrik.com/reference/flutter/nativebrikuser
///
/// Usage:
/// ```dart
/// // Set Custom User Properties
/// // Values support [String], [int], [double], [DateTime], [bool].
/// NubrickUser.instance.setProperties({
///   'prefecture': 'Tokyo',
///   'test_user': true,
///   'environment': const bool.fromEnvironment('dart.vm.product')
///       ? 'production'
///       : 'development',
/// });
/// ```
class NubrickUser {
  static final NubrickUser _instance = NubrickUser._();

  /// The singleton instance of [NubrickUser].
  static NubrickUser get instance => _instance;

  /// Private constructor for singleton pattern.
  NubrickUser._();

  /// Creates a new instance of [NubrickUser].
  ///
  /// In most cases, you should use [NubrickUser.instance] instead.
  factory NubrickUser() => _instance;

  /// Retrieves the current user ID.
  ///
  /// Returns a [Future] that completes with the user ID as a [String],
  /// or `null` if no user ID is set.
  Future<String?> getId() async {
    return await NubrickBridgePlatform.instance.getUserId();
  }

  /// Sets user properties for the current user.
  ///
  /// The [properties] parameter is a map of key-value pairs.
  /// Values support [String], [int], [double], [DateTime], [bool].
  ///
  /// Returns a [Future] that completes when the properties have been set.
  Future<void> setProperties(Map<String, dynamic> properties) async {
    await NubrickBridgePlatform.instance.setUserProperties(properties);
  }

  /// Retrieves the current user's properties.
  ///
  /// Returns a [Future] that completes with a [Map] of user properties,
  /// where both keys and values are [String]s. Returns `null` if no
  /// properties are set or if the user is not identified.
  Future<Map<String, String>?> getProperties() async {
    return await NubrickBridgePlatform.instance.getUserProperties();
  }
}
