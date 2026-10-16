import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../adaptive/adaptive_presenter.dart';
import '../../../../adaptive/window_size_class.dart';
import '../../../../providers/character_prompt_provider.dart';
import 'character_panel_toast.dart';
import 'character_place_view.dart';

/// Opens placing characters by hand as a full-height sheet; positions switch
/// to manual on the way in.
Future<void> showCharacterPlacement(BuildContext context, {String? select}) {
  return AdaptivePresenter.showForm<void>(
    context: context,
    title: context.l10n.characterPanel_placeTitle,
    dialogWidth: 720,
    showHeader: false,
    // Markers are dragged on the canvas; a sheet following the same drag
    // would close under the finger.
    allowDragDismissal: false,
    builder: (context, scrollController) =>
        CharacterPlacementSheet(initialSelection: select),
  );
}

class CharacterPlacementSheet extends ConsumerStatefulWidget {
  const CharacterPlacementSheet({super.key, this.initialSelection});

  final String? initialSelection;

  @override
  ConsumerState<CharacterPlacementSheet> createState() =>
      _CharacterPlacementSheetState();
}

class _CharacterPlacementSheetState
    extends ConsumerState<CharacterPlacementSheet> {
  CharacterPanelToastData? _toast;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    final notifier = ref.read(characterPromptNotifierProvider.notifier);
    if (ref.read(characterPromptNotifierProvider).globalAiChoice) {
      // Not while the first frame builds: providers can't change then.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) notifier.setGlobalAiChoice(false);
      });
    }
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2400), _hideToast);
    setState(() => _toast = CharacterPanelToastData(message: message));
  }

  void _hideToast() {
    _toastTimer?.cancel();
    _toastTimer = null;
    if (mounted && _toast != null) setState(() => _toast = null);
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        key: const ValueKey('character-placement'),
        height: context.adaptiveWindow.isCompact
            ? constraints.maxHeight
            : constraints.maxHeight.clamp(0.0, 720.0),
        child: Stack(
          children: [
            Positioned.fill(
              child: CharacterPlaceView(
                initialSelection: widget.initialSelection,
                onDone: _close,
                onHandToAi: () {
                  ref
                      .read(characterPromptNotifierProvider.notifier)
                      .setGlobalAiChoice(true);
                  _close();
                },
                onMessage: _showToast,
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              // Above the footer's buttons.
              bottom: 84,
              child: CharacterPanelToast(toast: _toast, onDismiss: _hideToast),
            ),
          ],
        ),
      ),
    );
  }
}
