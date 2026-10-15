import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Placement canvas toggles: snapping to the 5×5 cell centres and showing the
/// latest image behind the markers.
typedef CharacterPlaceOptions = ({bool snap, bool backdrop});

/// Kept for the session only; these are viewing aids, not settings.
final characterPlaceOptionsProvider = StateProvider<CharacterPlaceOptions>(
  (ref) => (snap: false, backdrop: true),
);
