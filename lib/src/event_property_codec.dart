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

Map<String, Object> decodeEventProperties(dynamic raw) {
  if (raw is! Map) return const {};

  final properties = <String, Object>{};
  for (final entry in raw.entries) {
    if (entry.key is! String || entry.value is! Map) continue;
    final encoded = entry.value as Map;
    final value = encoded['value'];
    switch (encoded['type']) {
      case 'integer' when value is int:
      case 'float' when value is double && value.isFinite:
      case 'string' when value is String:
      case 'boolean' when value is bool:
        properties[entry.key as String] = value;
      case 'timestamp' when value is String:
        final timestamp = DateTime.tryParse(value);
        if (timestamp != null) {
          properties[entry.key as String] = timestamp.toUtc();
        }
    }
  }
  return properties;
}
