import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubrick_flutter/channel/nubrick_flutter_platform_interface.dart';
import 'package:nubrick_flutter/nubrick_flutter.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakeNubrickFlutterPlatform extends NubrickFlutterPlatform
    with MockPlatformInterfaceMixin {
  final List<dynamic> updatedArguments = [];

  @override
  Future<String?> connectClient(String projectId) async => 'ok';

  @override
  Future<String?> connectEmbedding(
      String id, String channelId, dynamic arguments) async {
    return 'ok';
  }

  @override
  Future<String?> disconnectEmbedding(String channelId) async => 'ok';

  @override
  Future<String?> updateEmbeddingArguments(
      String channelId, dynamic arguments) async {
    updatedArguments.add(arguments);
    return 'ok';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NubrickEmbedding arguments', () {
    late NubrickFlutterPlatform originalPlatform;
    late _FakeNubrickFlutterPlatform fakePlatform;

    setUp(() {
      Nubrick.resetForTest();
      originalPlatform = NubrickFlutterPlatform.instance;
      fakePlatform = _FakeNubrickFlutterPlatform();
      NubrickFlutterPlatform.instance = fakePlatform;
      Nubrick.initialize('test-project', trackCrashes: false);
    });

    tearDown(() {
      Nubrick.resetForTest();
      NubrickFlutterPlatform.instance = originalPlatform;
    });

    testWidgets('does not update native arguments for equal map contents',
        (tester) async {
      final initialArguments = {'counter': 1};
      final nextArguments = {'counter': 1};

      await tester.pumpWidget(MaterialApp(
        home: NubrickEmbedding('test-embedding', arguments: initialArguments),
      ));
      await tester.pump();

      await tester.pumpWidget(MaterialApp(
        home: NubrickEmbedding('test-embedding', arguments: nextArguments),
      ));
      await tester.pump();

      expect(fakePlatform.updatedArguments, isEmpty);
    });

    testWidgets('updates native arguments when map contents change',
        (tester) async {
      final initialArguments = {'counter': 1};
      final nextArguments = {'counter': 2};

      await tester.pumpWidget(MaterialApp(
        home: NubrickEmbedding('test-embedding', arguments: initialArguments),
      ));
      await tester.pump();

      await tester.pumpWidget(MaterialApp(
        home: NubrickEmbedding('test-embedding', arguments: nextArguments),
      ));
      await tester.pump();

      expect(fakePlatform.updatedArguments, [
        {'counter': 2},
      ]);
    });
  });
}
