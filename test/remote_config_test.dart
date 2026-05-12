import 'package:flutter_test/flutter_test.dart';
import 'package:nubrick_flutter/channel/nubrick_flutter_platform_interface.dart';
import 'package:nubrick_flutter/nubrick_flutter.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakeNubrickFlutterPlatform extends NubrickFlutterPlatform
    with MockPlatformInterfaceMixin {
  String? lastConnectedRemoteConfigChannelId;
  String? lastDisconnectedRemoteConfigChannelId;
  String? lastDisconnectedEmbeddingChannelId;

  @override
  Future<String?> connectClient(String projectId) async => 'ok';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NubrickRemoteConfigVariant', () {
    late NubrickFlutterPlatform originalPlatform;
    late _FakeNubrickFlutterPlatform fakePlatform;

    setUp(() {
      Nubrick.resetForTest();
      originalPlatform = NubrickFlutterPlatform.instance;
      fakePlatform = _FakeNubrickFlutterPlatform();
      NubrickFlutterPlatform.instance = fakePlatform;
      Nubrick.initialize('test-project');
    });

    tearDown(() {
      Nubrick.resetForTest();
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
