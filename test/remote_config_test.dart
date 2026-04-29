import 'package:flutter_test/flutter_test.dart';
import 'package:nubrick_flutter/channel/nubrick_flutter_platform_interface.dart';
import 'package:nubrick_flutter/remote_config.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakeNubrickFlutterPlatform extends NubrickFlutterPlatform
    with MockPlatformInterfaceMixin {
  String? lastConnectedRemoteConfigChannelId;
  String? lastDisconnectedRemoteConfigChannelId;
  String? lastDisconnectedEmbeddingChannelId;

  @override
  Future<RemoteConfigPhase?> connectRemoteConfig(
      String id, String channelId) async {
    lastConnectedRemoteConfigChannelId = channelId;
    return RemoteConfigPhase.completed;
  }

  @override
  Future<String?> disconnectRemoteConfig(String channelId) async {
    lastDisconnectedRemoteConfigChannelId = channelId;
    return 'ok';
  }

  @override
  Future<String?> disconnectEmbedding(String channelId) async {
    lastDisconnectedEmbeddingChannelId = channelId;
    return 'ok';
  }
}

void main() {
  group('NubrickRemoteConfigVariant', () {
    late NubrickFlutterPlatform originalPlatform;
    late _FakeNubrickFlutterPlatform fakePlatform;

    setUp(() {
      originalPlatform = NubrickFlutterPlatform.instance;
      fakePlatform = _FakeNubrickFlutterPlatform();
      NubrickFlutterPlatform.instance = fakePlatform;
    });

    tearDown(() {
      NubrickFlutterPlatform.instance = originalPlatform;
    });

    test('dispose disconnects remote config state', () async {
      final variant = await NubrickRemoteConfig('test-config').fetch();

      await variant.dispose();

      expect(
        fakePlatform.lastDisconnectedRemoteConfigChannelId,
        fakePlatform.lastConnectedRemoteConfigChannelId,
      );
      expect(fakePlatform.lastDisconnectedEmbeddingChannelId, isNull);
    });
  });
}
