import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/tag_library_page_provider.dart';
import '../../../widgets/autocomplete/autocomplete_config.dart';
import '../../../widgets/autocomplete/autocomplete_wrapper.dart';
import '../../../widgets/gallery/gallery_library_toolbar.dart';

/// The library search box with tag completion, kept in step with the page's
/// search query. Shared by the desktop toolbar and the phone header.
class TagLibrarySearchField extends ConsumerStatefulWidget {
  const TagLibrarySearchField({
    super.key,
    required this.hintText,
    this.focusNode,
  });

  final String hintText;

  /// Lets the page's search shortcut focus the box.
  final FocusNode? focusNode;

  @override
  ConsumerState<TagLibrarySearchField> createState() =>
      _TagLibrarySearchFieldState();
}

class _TagLibrarySearchFieldState extends ConsumerState<TagLibrarySearchField> {
  final TextEditingController _controller = TextEditingController();
  FocusNode? _ownFocusNode;

  FocusNode get _focusNode => widget.focusNode ?? _ownFocusNode!;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) _ownFocusNode = FocusNode();
    _focusNode.onKeyEvent = _handleKeyEvent;
    _sync(ref.read(tagLibraryPageNotifierProvider).searchQuery);
  }

  @override
  void dispose() {
    _controller.dispose();
    _ownFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(
      tagLibraryPageNotifierProvider.select((state) => state.searchQuery),
      (_, next) => _sync(next),
    );
    void update(String value) =>
        ref.read(tagLibraryPageNotifierProvider.notifier).setSearchQuery(value);
    return AutocompleteWrapper(
      controller: _controller,
      focusNode: _focusNode,
      config: const AutocompleteConfig(
        autoInsertComma: false,
        treatSpacesAsSeparators: true,
      ),
      onSuggestionSelected: update,
      child: GalleryLibrarySearchField(
        key: const ValueKey('tag-library-search'),
        controller: _controller,
        focusNode: _focusNode,
        hintText: widget.hintText,
        onChanged: update,
      ),
    );
  }

  void _sync(String query) {
    if (_controller.text == query) return;
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyA) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    return KeyEventResult.handled;
  }
}
