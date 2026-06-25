import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubrick_flutter/channel/nubrick_flutter_platform_interface.dart';
import 'package:nubrick_flutter/nubrick_flutter.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakeNubrickFlutterPlatform extends NubrickFlutterPlatform
    with MockPlatformInterfaceMixin {
  final List<dynamic> updatedArguments = [];
  String? connectedEmbeddingChannelId;

  @override
  Future<String?> connectClient(String projectId) async => 'ok';

  @override
  Future<String?> connectEmbedding(
      String id, String channelId, dynamic arguments) async {
    connectedEmbeddingChannelId = channelId;
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

Future<void> _sendEmbeddingMethod(
  WidgetTester tester,
  String channelId,
  String method, [
  dynamic arguments,
]) async {
  const codec = StandardMethodCodec();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'Nubrick/Embedding/$channelId',
    codec.encodeMethodCall(MethodCall(method, arguments)),
    null,
  );
}

Map<String, dynamic> _fixedSize(double value) => {
      'kind': 'fixed',
      'value': value,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NubrickEmbedding', () {
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

    testWidgets('reports missing height once when completed without height',
        (tester) async {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: UnconstrainedBox(
          child: NubrickEmbedding(
            'test-embedding',
            width: 320,
            builder: (context, phase, child) => const SizedBox.shrink(),
          ),
        ),
      ));
      await tester.pump();

      final channelId = fakePlatform.connectedEmbeddingChannelId;
      expect(channelId, isNotNull);

      await _sendEmbeddingMethod(
          tester, channelId!, 'embedding-phase-update', 'completed');
      await tester.pump();

      expect(tester.takeException().toString(),
          contains('NubrickEmbedding has no height'));

      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('reports missing width once when completed without width',
        (tester) async {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: UnconstrainedBox(
          child: NubrickEmbedding(
            'test-embedding',
            height: 180,
            builder: (context, phase, child) => const SizedBox.shrink(),
          ),
        ),
      ));
      await tester.pump();

      final channelId = fakePlatform.connectedEmbeddingChannelId;
      expect(channelId, isNotNull);

      await _sendEmbeddingMethod(
          tester, channelId!, 'embedding-phase-update', 'completed');
      await tester.pump();

      expect(tester.takeException().toString(),
          contains('NubrickEmbedding has no width'));

      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'does not report missing dimensions when initial size follows completed before next frame',
        (tester) async {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: UnconstrainedBox(
          child: NubrickEmbedding(
            'test-embedding',
            builder: (context, phase, child) => const SizedBox.shrink(),
          ),
        ),
      ));
      await tester.pump();

      final channelId = fakePlatform.connectedEmbeddingChannelId;
      expect(channelId, isNotNull);

      await _sendEmbeddingMethod(
          tester, channelId!, 'embedding-phase-update', 'completed');
      await _sendEmbeddingMethod(
        tester,
        channelId,
        'embedding-initial-size',
        {
          'width': _fixedSize(320),
          'height': _fixedSize(180),
        },
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
