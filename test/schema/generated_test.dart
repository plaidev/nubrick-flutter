import 'package:flutter_test/flutter_test.dart';
import 'package:nubrick_flutter/schema/generated.dart';

void main() {
  test('ExperimentConfig round-trips trigger event property conditions', () {
    final config = ExperimentConfig(triggerEventPropertyConditions: [
      EventPropertyCondition(
        property: 'score',
        asType: EventPropertyType.INTEGER,
        operator: ConditionOperator.GreaterThan,
        value: '10',
      ),
    ]);

    final encoded = config.encode();
    expect(encoded['triggerEventPropertyConditions'], [
      {
        '__typename': 'EventPropertyCondition',
        'property': 'score',
        'asType': 'INTEGER',
        'operator': 'GreaterThan',
        'value': '10',
      },
    ]);

    final decoded = ExperimentConfig.decode(encoded);
    final condition = decoded?.triggerEventPropertyConditions?.single;
    expect(condition?.property, 'score');
    expect(condition?.asType, EventPropertyType.INTEGER);
    expect(condition?.operator, ConditionOperator.GreaterThan);
    expect(condition?.value, '10');
  });

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
