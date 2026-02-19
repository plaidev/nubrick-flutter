import 'package:nubrick_flutter/channel/nubrick_flutter_platform_interface.dart';
import 'package:nubrick_flutter/utils/random.dart';

enum RemoteConfigPhase {
  failed,
  notFound,
  completed,
}

/// A remote config that can be fetched from nubrick.
///
/// - **Nubrick** must be initialized before using this class.
/// - Dispose the variant after using it not to leak resources.
///
/// reference: https://docs.nativebrik.com/reference/flutter/nativebrikremoteconfig
///
/// Usage:
/// ```dart
/// final config = NubrickRemoteConfig("ID OR CUSTOM ID");
/// final variant = await config.fetch();
/// final phase = variant.phase;
/// final value = await variant.get("KEY");
/// await variant.dispose();
/// ```
///
class NubrickRemoteConfig {
  final String id;
  final _channelId = generateRandomString(32);
  NubrickRemoteConfig(this.id);

  Future<NubrickRemoteConfigVariant> fetch() async {
    var phase = await NubrickFlutterPlatform.instance
        .connectRemoteConfig(id, _channelId);
    return NubrickRemoteConfigVariant._(
        _channelId, phase ?? RemoteConfigPhase.failed);
  }
}

class NubrickRemoteConfigVariant {
  final String channelId;
  final RemoteConfigPhase phase;
  NubrickRemoteConfigVariant._(this.channelId, this.phase);

  Future<String?> get(String key) async {
    return await NubrickFlutterPlatform.instance
        .getRemoteConfigValue(channelId, key);
  }

  Future<int?> getAsInt(String key) async {
    var value = await get(key);
    return value != null ? int.tryParse(value) : null;
  }

  Future<double?> getAsDouble(String key) async {
    var value = await get(key);
    return value != null ? double.tryParse(value) : null;
  }

  Future<bool?> getAsBool(String key) async {
    var value = await get(key);
    return value != null ? value == "TRUE" : null;
  }

  Future<void> dispose() async {
    await NubrickFlutterPlatform.instance.disconnectEmbedding(channelId);
  }
}
