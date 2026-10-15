import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../../data/models/character/character_prompt.dart';
import '../../../../adaptive/adaptive_presenter.dart';
import '../../../../adaptive/window_size_class.dart';
import '../../../../providers/character_prompt_provider.dart';
import '../../../../themes/theme_extension.dart';
import '../../../../widgets/common/keyboard_dismiss_region.dart';
import 'character_panel_add_view.dart';
import 'character_panel_edit_view.dart';
import 'character_panel_grid_view.dart';
import 'character_panel_toast.dart';
import '../mobile_generation_header.dart';
import 'character_place_view.dart';

/// Opens the character panel from the prompt page's character button.
Future<void> showCharacterPanel(BuildContext context) {
  return AdaptivePresenter.showForm<void>(
    context: context,
    title: context.l10n.characterPanel_title,
    // Room for three card columns, or canvas and controls side by side.
    dialogWidth: 720,
    showHeader: false,
    // Markers are dragged on the placement canvas; a sheet following the
    // same drag would close under the finger.
    allowDragDismissal: false,
    builder: (context, scrollController) => const CharacterPanel(),
  );
}

enum CharacterPanelPage { grid, add, edit, place }

/// One sheet for every character task: the card grid, adding, editing one
/// character and placing them. Pages replace each other inside the sheet,
/// which grows to its full height only for placing.
class CharacterPanel extends ConsumerStatefulWidget {
  const CharacterPanel({super.key});

  @override
  ConsumerState<CharacterPanel> createState() => _CharacterPanelState();
}

class _CharacterPanelState extends ConsumerState<CharacterPanel> {
  CharacterPanelPage _page = CharacterPanelPage.grid;
  String? _editId;
  String? _placeSelection;
  CharacterPanelPage _placeReturn = CharacterPanelPage.grid;
  CharacterPanelToastData? _toast;
  Timer? _toastTimer;
  late final CharacterPromptNotifier _notifier = ref.read(
    characterPromptNotifierProvider.notifier,
  );

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  void _show(CharacterPanelPage page) => setState(() => _page = page);

  void _openEdit(String id) => setState(() {
    _editId = id;
    _page = CharacterPanelPage.edit;
  });

  void _openPlace({String? select, required CharacterPanelPage returnTo}) {
    if (ref.read(characterPromptNotifierProvider).globalAiChoice) {
      _notifier.setGlobalAiChoice(false);
    }
    setState(() {
      _placeSelection = select;
      _placeReturn = returnTo;
      _page = CharacterPanelPage.place;
    });
  }

  void _back() {
    final characters = ref.read(characterPromptNotifierProvider).characters;
    final editable = characters.any((item) => item.id == _editId);
    setState(() {
      _page = switch (_page) {
        CharacterPanelPage.place
            when _placeReturn == CharacterPanelPage.edit && editable =>
          CharacterPanelPage.edit,
        _ => CharacterPanelPage.grid,
      };
    });
  }

  void _close() => Navigator.of(context).maybePop();

  void _showToast(CharacterPanelToastData toast) {
    _toastTimer?.cancel();
    _toastTimer = Timer(
      toast.onUndo == null
          ? const Duration(milliseconds: 2400)
          : const Duration(seconds: 5),
      _hideToast,
    );
    setState(() => _toast = toast);
  }

  void _hideToast() {
    _toastTimer?.cancel();
    _toastTimer = null;
    if (mounted && _toast != null) setState(() => _toast = null);
  }

  void _delete(CharacterPrompt character) {
    final characters = ref.read(characterPromptNotifierProvider).characters;
    final index = characters.indexWhere((item) => item.id == character.id);
    if (index < 0) return;
    _notifier.removeCharacter(character.id);
    if (_page == CharacterPanelPage.edit && _editId == character.id) {
      setState(() => _page = CharacterPanelPage.grid);
    }
    _showToast(
      CharacterPanelToastData(
        message: context.l10n.characterPanel_deleted(character.name),
        onUndo: () {
          _hideToast();
          final current = ref.read(characterPromptNotifierProvider).characters;
          if (current.any((item) => item.id == character.id)) return;
          _notifier.replaceAll([
            ...current.take(index),
            character,
            ...current.skip(index),
          ]);
        },
      ),
    );
  }

  /// The bottom sheet already stops this far below the status bar.
  static const double _sheetTopGap = 16;

  double _height(BoxConstraints constraints) {
    final available = constraints.maxHeight;
    if (!context.adaptiveWindow.isCompact) return math.min(available, 720);
    if (_page == CharacterPanelPage.place) return available;
    // Up to the bottom of the generation header, which stays in view above
    // the sheet with the model and size.
    const headerClearance = MobileGenerationHeader.toolbarHeight - _sheetTopGap;
    return math.min(available, math.max(available - headerClearance, 420));
  }

  Widget _buildPage() {
    final editId = _editId;
    return switch (_page) {
      CharacterPanelPage.grid => CharacterPanelGridView(
        key: const ValueKey('character-panel-grid'),
        onClose: _close,
        onOpenAdd: () => _show(CharacterPanelPage.add),
        onOpenEdit: _openEdit,
        onOpenPlace: () => _openPlace(returnTo: CharacterPanelPage.grid),
        onDelete: _delete,
        onMessage: (message) =>
            _showToast(CharacterPanelToastData(message: message)),
      ),
      CharacterPanelPage.add => CharacterPanelAddView(
        key: const ValueKey('character-panel-add'),
        onBack: _back,
        onAdded: _openEdit,
      ),
      CharacterPanelPage.edit when editId != null => CharacterPanelEditView(
        key: const ValueKey('character-panel-edit'),
        characterId: editId,
        onBack: _back,
        onOpenEdit: _openEdit,
        onOpenPlace: () =>
            _openPlace(select: editId, returnTo: CharacterPanelPage.edit),
        onDelete: _delete,
      ),
      CharacterPanelPage.place => CharacterPlaceView(
        key: const ValueKey('character-panel-place'),
        initialSelection: _placeSelection,
        onDone: _back,
        onHandToAi: () {
          _notifier.setGlobalAiChoice(true);
          _back();
        },
        onMessage: (message) =>
            _showToast(CharacterPanelToastData(message: message)),
      ),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    // A character removed elsewhere while its editor is open.
    ref.listen(characterPromptNotifierProvider, (_, next) {
      if (_page != CharacterPanelPage.edit) return;
      if (next.characters.any((item) => item.id == _editId)) return;
      setState(() => _page = CharacterPanelPage.grid);
    });
    final theme = Theme.of(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : theme.appTheme.normalDuration;
    return PopScope(
      canPop: _page == CharacterPanelPage.grid,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: KeyboardDismissRegion(
        enabled: context.adaptiveWindow.isCompact,
        child: LayoutBuilder(
          builder: (context, constraints) => AnimatedContainer(
            key: const ValueKey('character-panel'),
            duration: duration,
            curve: theme.appTheme.standardCurve,
            height: _height(constraints),
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: duration,
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: _buildPage(),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  // Above the placement footer's buttons.
                  bottom: _page == CharacterPanelPage.place ? 84 : 12,
                  child: CharacterPanelToast(
                    toast: _toast,
                    onDismiss: _hideToast,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
