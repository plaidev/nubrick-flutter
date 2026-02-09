import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:nubrick_flutter/tooltip/overlay.dart';

/// NubrickProvider is the main provider for the Nativebrik SDK.
///
/// reference: https://docs.nativebrik.com/reference/flutter/nativebrikprovider
///
/// Usage:
/// ```dart
/// NubrickProvider(
///   child: App(),
/// )
/// ```
class NubrickProvider extends StatefulWidget {
  final Widget child;
  const NubrickProvider({super.key, required this.child});

  @override
  State<NubrickProvider> createState() => NubrickProviderState();
}

class NubrickProviderState extends State<NubrickProvider> {
  final Map<String, GlobalKey> _keys = {};

  /// Get a global key by ID
  GlobalKey? getKey(String id) => _keys[id];

  /// Store a global key with an ID
  void storeKey(String id, GlobalKey key) {
    _keys[id] = key;
  }

  /// Remove a global key by ID
  void removeKey(String id, GlobalKey key) {
    final currentKey = _keys[id];
    if (identical(currentKey, key)) {
      _keys.remove(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        _render(context),
        NubrickTooltipOverlay(keysReference: _keys),
      ],
    );
  }

  Widget _render(BuildContext context) {
    const String viewType = "nubrick-overlay-view";
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        // overlay view controller will be attached when the nubrick bridge plugin is intialized.
        return const SizedBox.shrink();
      case TargetPlatform.android:
        // to support in-app-messeging for android, we need to attach the overlay view into the flutter widget tree.
        return const SizedBox(
          height: 1,
          width: 1,
          child: AndroidView(
            viewType: viewType,
            layoutDirection: TextDirection.ltr,
            creationParams: <String, dynamic>{},
            creationParamsCodec: StandardMessageCodec(),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Extension to access NubrickProvider from build context
extension NubrickProviderExtension on BuildContext {
  NubrickProviderState? get nubrickProvider {
    return findAncestorStateOfType<NubrickProviderState>();
  }
}
