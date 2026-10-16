import 'dart:async';

/// Runs the saves of each generated image one after another.
///
/// Auto-save and the actions that need a real file (favorite, locate) can
/// both write the same result. A save that starts while another one is still
/// writing that image waits for it, then finds the file already linked, so a
/// result never lands in the gallery twice.
class GeneratedImageSaveQueue {
  final Map<String, Future<void>> _pending = {};

  Future<T> run<T>(Iterable<String> imageIds, Future<T> Function() save) {
    final ids = imageIds.toSet();
    final earlier = [
      for (final id in ids)
        if (_pending[id] case final pending?) pending,
    ];
    final result = earlier.isEmpty
        ? Future.sync(save)
        : Future.wait(earlier).then((_) => save());
    final settled = result.then<void>((_) {}, onError: (Object _) {});
    for (final id in ids) {
      _pending[id] = settled;
    }
    unawaited(
      settled.whenComplete(() {
        for (final id in ids) {
          if (identical(_pending[id], settled)) _pending.remove(id);
        }
      }),
    );
    return result;
  }
}
