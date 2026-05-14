import 'package:flutter/material.dart';
import '../provider.dart';

/// A widget that acts as an anchor point for tooltips or onboarding stories in the Nubrick dashboard.
///
/// The [NubrickAnchor] registers its position and key with the Nubrick provider, allowing
/// external overlays (such as tooltips or onboarding highlights) to be precisely positioned
/// relative to this widget. This is useful for guiding users through features or workflows
/// as part of an onboarding experience.
///
/// reference: https://docs.nubrick.app/reference/flutter/nubrickanchor
///
/// Usage:
/// Wrap any widget you want to highlight with [NubrickAnchor], providing a unique [id].
/// The Nubrick dashboard can then use this anchor to display contextual UI, such as a tooltip
/// or story step, at the correct location.
///
/// Example:
/// ```dart
/// NubrickAnchor(
///   'unique-feature-id',
///   child: MyFeatureWidget(),
/// )
/// ```
class NubrickAnchor extends StatefulWidget {
  final String id;
  final Widget child;

  const NubrickAnchor(
    this.id, {
    super.key,
    required this.child,
  });

  @override
  // ignore: library_private_types_in_public_api
  _AnchorState createState() => _AnchorState();
}

class _AnchorState extends State<NubrickAnchor> {
  final GlobalKey childKey = GlobalKey();
  NubrickProviderState? _provider;
  String? _registeredId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncRegistration(context.nubrickProvider, widget.id);
  }

  @override
  void didUpdateWidget(covariant NubrickAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRegistration(context.nubrickProvider, widget.id);
  }

  @override
  void activate() {
    super.activate();
    _syncRegistration(context.nubrickProvider, widget.id);
  }

  void _syncRegistration(NubrickProviderState? provider, String id) {
    if (_provider == provider && _registeredId == id) {
      return;
    }

    final previousProvider = _provider;
    final previousId = _registeredId;
    if (previousProvider != null && previousId != null) {
      previousProvider.removeKey(previousId, childKey);
    }

    _provider = provider;
    _registeredId = null;

    if (provider != null) {
      provider.storeKey(id, childKey);
      _registeredId = id;
    }
  }

  @override
  void dispose() {
    // Remove the key when the widget is disposed
    final provider = _provider;
    final registeredId = _registeredId;
    if (provider != null && registeredId != null) {
      provider.removeKey(registeredId, childKey);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: childKey,
      child: widget.child,
    );
  }
}
