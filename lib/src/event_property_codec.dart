Map<String, Object> normalizeEventProperties(Map<String, Object?> input) {
  final normalized = <String, Object>{};
  for (final entry in input.entries) {
    final value = entry.value;
    if (value is int || value is String || value is bool) {
      normalized[entry.key] = value as Object;
    } else if (value is double && value.isFinite) {
      normalized[entry.key] = value;
    } else if (value is DateTime) {
      final timestamp = value.toUtc();
      if (timestamp.year >= 1 && timestamp.year <= 9999) {
        normalized[entry.key] = timestamp;
      }
    }
  }
  return normalized;
}

Map<String, Map<String, Object>> encodeEventProperties(
    Map<String, Object> properties) {
  final encoded = <String, Map<String, Object>>{};
  for (final entry in properties.entries) {
    final value = entry.value;
    encoded[entry.key] = switch (value) {
      int() => {'type': 'integer', 'value': value},
      double() => {'type': 'float', 'value': value},
      String() => {'type': 'string', 'value': value},
      bool() => {'type': 'boolean', 'value': value},
      DateTime() => {
          'type': 'timestamp',
          'value': value.toUtc().toIso8601String(),
        },
      _ => throw StateError('Unsupported normalized event property'),
    };
  }
  return encoded;
}
