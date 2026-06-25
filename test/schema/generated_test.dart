import 'package:flutter_test/flutter_test.dart';
import 'package:nubrick_flutter/schema/generated.dart';

void main() {
  group('Tooltip schema payload', () {
    test('UIRootBlock can round-trip through UIBlock', () {
      final rootBlock = UIRootBlock(id: 'root', data: null);
      final union = UIBlock.asUIRootBlock(rootBlock);

      final encoded = union.encode();
      final decoded = UIBlock.decode(encoded);

      expect(encoded?['__typename'], 'UIRootBlock');
      expect(decoded, isA<UIBlockUIRootBlock>());
      expect((decoded as UIBlockUIRootBlock).data.id, rootBlock.id);
      expect(decoded.data.data, rootBlock.data);
    });
  });
}
