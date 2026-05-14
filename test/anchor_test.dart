import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubrick_flutter/anchor/anchor.dart';
import 'package:nubrick_flutter/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('updates provider registry when anchor id changes', (
    WidgetTester tester,
  ) async {
    final providerKey = GlobalKey<NubrickProviderState>();

    await tester.pumpWidget(
      _ProviderHarness(
        providerKey: providerKey,
        anchorId: 'anchor-a',
      ),
    );

    final originalKey = providerKey.currentState!.getKey('anchor-a');

    expect(originalKey, isNotNull);
    expect(providerKey.currentState!.getKey('anchor-b'), isNull);

    await tester.pumpWidget(
      _ProviderHarness(
        providerKey: providerKey,
        anchorId: 'anchor-b',
      ),
    );

    expect(providerKey.currentState!.getKey('anchor-a'), isNull);
    expect(providerKey.currentState!.getKey('anchor-b'), same(originalKey));
  });

  testWidgets('moves registry entry when anchor provider changes', (
    WidgetTester tester,
  ) async {
    final firstProviderKey = GlobalKey<NubrickProviderState>();
    final secondProviderKey = GlobalKey<NubrickProviderState>();
    final anchorStateKey = GlobalKey();

    await tester.pumpWidget(
      _MoveBetweenProvidersHarness(
        useSecondProvider: false,
        firstProviderKey: firstProviderKey,
        secondProviderKey: secondProviderKey,
        anchorStateKey: anchorStateKey,
      ),
    );

    final originalKey = firstProviderKey.currentState!.getKey('anchor-a');

    expect(originalKey, isNotNull);
    expect(secondProviderKey.currentState!.getKey('anchor-a'), isNull);

    await tester.pumpWidget(
      _MoveBetweenProvidersHarness(
        useSecondProvider: true,
        firstProviderKey: firstProviderKey,
        secondProviderKey: secondProviderKey,
        anchorStateKey: anchorStateKey,
      ),
    );

    expect(firstProviderKey.currentState!.getKey('anchor-a'), isNull);
    expect(
        secondProviderKey.currentState!.getKey('anchor-a'), same(originalKey));
  });
}

class _ProviderHarness extends StatelessWidget {
  final GlobalKey<NubrickProviderState> providerKey;
  final String anchorId;

  const _ProviderHarness({
    required this.providerKey,
    required this.anchorId,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: NubrickProvider(
        key: providerKey,
        child: NubrickAnchor(
          anchorId,
          child: const SizedBox(width: 10, height: 10),
        ),
      ),
    );
  }
}

class _MoveBetweenProvidersHarness extends StatelessWidget {
  final bool useSecondProvider;
  final GlobalKey<NubrickProviderState> firstProviderKey;
  final GlobalKey<NubrickProviderState> secondProviderKey;
  final GlobalKey anchorStateKey;

  const _MoveBetweenProvidersHarness({
    required this.useSecondProvider,
    required this.firstProviderKey,
    required this.secondProviderKey,
    required this.anchorStateKey,
  });

  @override
  Widget build(BuildContext context) {
    final anchor = NubrickAnchor(
      'anchor-a',
      key: anchorStateKey,
      child: const SizedBox(width: 10, height: 10),
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          Expanded(
            child: NubrickProvider(
              key: firstProviderKey,
              child: useSecondProvider ? const SizedBox.shrink() : anchor,
            ),
          ),
          Expanded(
            child: NubrickProvider(
              key: secondProviderKey,
              child: useSecondProvider ? anchor : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}
