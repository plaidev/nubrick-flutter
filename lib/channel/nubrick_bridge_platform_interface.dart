import 'package:nubrick_bridge/schema/generated.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:nubrick_bridge/nubrick_bridge.dart';

import './nubrick_bridge_method_channel.dart';

abstract class NubrickBridgePlatform extends PlatformInterface {
  /// Constructs a NubrickBridgePlatform.
  NubrickBridgePlatform() : super(token: _token);

  static final Object _token = Object();

  static NubrickBridgePlatform _instance = MethodChannelNubrickBridge();

  /// The default instance of [NubrickBridgePlatform] to use.
  ///
  /// Defaults to [MethodChannelNubrickBridge].
  static NubrickBridgePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [NubrickBridgePlatform] when
  /// they register themselves.
  static set instance(NubrickBridgePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getNubrickSDKVersion() {
    throw UnimplementedError(
        'getNubrickSDKVersion() has not been implemented.');
  }

  Future<String?> connectClient(
      String projectId, NubrickCachePolicy cachePolicy) {
    throw UnimplementedError('connectClient() has not been implemented.');
  }

  Future<String?> getUserId() {
    throw UnimplementedError('getUserId() has not been implemented.');
  }

  Future<void> setUserProperties(Map<String, dynamic> properties) {
    throw UnimplementedError('setUserProperties() has not been implemented.');
  }

  Future<Map<String, String>?> getUserProperties() {
    throw UnimplementedError('getUserProperties() has not been implemented.');
  }

  Future<String?> connectEmbedding(
      String id, String channelId, dynamic arguments) {
    throw UnimplementedError('connectEmbedding() has not been implemented.');
  }

  Future<String?> disconnectEmbedding(String channelId) {
    throw UnimplementedError('disconnectEmbedding() has not been implemented.');
  }

  Future<RemoteConfigPhase?> connectRemoteConfig(String id, String channelId) {
    throw UnimplementedError('connectRemoteConfig() has not been implemented.');
  }

  Future<String?> disconnectRemoteConfig(String channelId) {
    throw UnimplementedError(
        'disconnectRemoteConfig() has not been implemented.');
  }

  Future<String?> getRemoteConfigValue(String channelId, String key) {
    throw UnimplementedError(
        'getRemoteConfigValue() has not been implemented.');
  }

  Future<String?> connectEmbeddingInRemoteConfigValue(String key,
      String channelId, String embeddingChannelId, dynamic arguments) {
    throw UnimplementedError(
        'connectEmbeddingInRemoteConfigValue() has not been implemented.');
  }

  Future<UIRootBlock?> connectTooltip(String name) {
    throw UnimplementedError('connectTooltip() has not been implemented.');
  }

  Future<String?> connectTooltipEmbedding(
      String channelId, UIRootBlock rootBlock) {
    throw UnimplementedError(
        'connectTooltipEmbedding() has not been implemented.');
  }

  Future<void> callTooltipEmbeddingDispatch(
      String channelId, UIBlockEventDispatcher event) {
    throw UnimplementedError(
        'callTooltipEmbeddingDispatch() has not been implemented.');
  }

  Future<String?> disconnectTooltipEmbedding(String channelId) {
    throw UnimplementedError(
        'disconnectTooltipEmbedding() has not been implemented.');
  }

  Future<String?> dispatch(String name) {
    throw UnimplementedError('dispatch() has not been implemented.');
  }

  /// Records a crash with the given error data.
  ///
  /// This method sends the error data to the native implementation
  /// for crash reporting.
  Future<void> recordCrash(Map<String, dynamic> errorData) {
    throw UnimplementedError('recordCrash() has not been implemented.');
  }
}
