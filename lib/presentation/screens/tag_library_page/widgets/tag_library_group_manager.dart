import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/gallery/gallery_tree_drop_slot.dart';
import '../../../../data/models/tag_library/tag_library_category.dart';
import '../../../adaptive/adaptive_presenter.dart';
import '../../../adaptive/content_sized_adaptive_form.dart';
import '../../../adaptive/interaction_policy.dart';
import '../../../providers/tag_library_page_provider.dart';
import '../../../services/library_sidebar_move_service.dart';
import '../../../themes/core/layered_surface_style.dart';
import '../../../widgets/common/app_toast.dart';
import '../../../widgets/tag_library/library_group_style.dart';
import '../tag_library_sections.dart';
import 'tag_library_group_create_sheet.dart';

enum _GroupAction { rename, addSubgroup, delete }

/// Lists every group as a tree: drag to reorder, and rename, add subgroups or
/// delete from each row's menu. [onDelete] confirms and deletes a group.
Future<void> showTagLibraryGroupManager({
  required BuildContext context,
  required Future<void> Function(String categoryId) onDelete,
}) {
  return AdaptivePresenter.showPanel<void>(
    context: context,
    title: context.l10n.tagLibrary_manageGroups,
    initialChildSize: 0.8,
    builder: (panelContext, scrollController) => _GroupManagerBody(
      scrollController: scrollController,
      onDelete: onDelete,
    ),
  );
}

/// A group in the flattened tree, with its depth for indenting.
typedef _Row = ({TagLibraryCategory category, int depth});

class _GroupManagerBody extends ConsumerWidget {
  const _GroupManagerBody({
    required this.scrollController,
    required this.onDelete,
  });

  final ScrollController scrollController;
  final Future<void> Function(String categoryId) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(tagLibraryPageNotifierProvider);
    final counts = state.categoryEntryCounts;
    final tree = TagLibraryGroupTree(state.categories);
    final rows = <_Row>[];
    void walk(String? parentId, int depth) {
      for (final category in tree.childrenOf(parentId)) {
        rows.add((category: category, depth: depth));
        walk(category.id, depth + 1);
      }
    }

    walk(null, 0);

    Future<void> reorder(int oldIndex, int newIndex) async {
      final moved = rows[oldIndex].category;
      final after = [...rows];
      after.insert(newIndex, after.removeAt(oldIndex));
      // Dropped rows join the group of the row they now sit above, or follow
      // the last row at the end of the list.
      final next = newIndex + 1 < after.length ? after[newIndex + 1] : null;
      final previous = newIndex > 0 ? after[newIndex - 1] : null;
      final target = next ?? previous;
      if (target == null) return;
      await ref
          .read(librarySidebarMoveServiceProvider)
          .moveTagCategory(
            moved.id,
            target.category.id,
            next != null
                ? GalleryTreeDropSlot.before
                : GalleryTreeDropSlot.after,
          );
    }

    // The hint scrolls with the rows so short screens keep the list usable.
    final hint = Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Text(
        context.l10n.tagLibrary_manageGroupsHint,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    return Column(
      key: const ValueKey('tag-library-group-manager'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: rows.isEmpty
              ? ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  children: [
                    hint,
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        context.l10n.tagLibrary_noGroups,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.outline),
                      ),
                    ),
                  ],
                )
              : ReorderableListView.builder(
                  key: const ValueKey('tag-library-group-list'),
                  scrollController: scrollController,
                  buildDefaultDragHandles: false,
                  header: hint,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: rows.length,
                  onReorderItem: reorder,
                  itemBuilder: (context, index) => _GroupRow(
                    key: ValueKey(
                      'tag-library-group-row-${rows[index].category.id}',
                    ),
                    index: index,
                    category: rows[index].category,
                    depth: rows[index].depth,
                    count: counts[rows[index].category.id] ?? 0,
                    style: LibraryGroupStyle.of(
                      rows[index].category.id,
                      state.categories,
                    ),
                    onAction: (action) =>
                        _handle(context, ref, rows[index].category, action),
                  ),
                ),
        ),
        SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              key: const ValueKey('tag-library-new-group'),
              onPressed: () => showTagLibraryGroupCreateSheet(context: context),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              icon: const Icon(Icons.add_rounded),
              label: Text(context.l10n.tagLibrary_newCategory),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handle(
    BuildContext context,
    WidgetRef ref,
    TagLibraryCategory category,
    _GroupAction action,
  ) async {
    switch (action) {
      case _GroupAction.rename:
        final name = await showTagLibraryGroupNameForm(
          context: context,
          title: context.l10n.common_rename,
          initialName: category.name,
        );
        if (name == null || !context.mounted) return;
        final renamed = await ref
            .read(tagLibraryPageNotifierProvider.notifier)
            .renameCategory(category.id, name);
        if (!renamed && context.mounted) {
          AppToast.error(context, context.l10n.tagLibrary_categoryNameExists);
        }
      case _GroupAction.addSubgroup:
        await showTagLibraryGroupCreateSheet(
          context: context,
          parentId: category.id,
        );
      case _GroupAction.delete:
        await onDelete(category.id);
    }
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    super.key,
    required this.index,
    required this.category,
    required this.depth,
    required this.count,
    required this.style,
    required this.onAction,
  });

  final int index;
  final TagLibraryCategory category;
  final int depth;
  final int count;
  final LibraryGroupStyle style;
  final ValueChanged<_GroupAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extent = context.interactionPolicy.minimumControlExtent;
    final l10n = context.l10n;
    return Material(
      color: theme.colorScheme.surface,
      child: ReorderableDelayedDragStartListener(
        index: index,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: extent + 8),
          child: Row(
            children: [
              ReorderableDragStartListener(
                key: ValueKey('tag-library-group-handle-${category.id}'),
                index: index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: SizedBox.square(
                    dimension: extent,
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ),
              SizedBox(width: depth * 24.0),
              LibraryGroupIcon(style: style, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  category.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: depth == 0 ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '$count',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              PopupMenuButton<_GroupAction>(
                key: ValueKey('tag-library-group-menu-${category.id}'),
                tooltip: l10n.common_edit,
                icon: const Icon(Icons.edit_outlined, size: 20),
                onSelected: onAction,
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: _GroupAction.rename,
                    child: _MenuRow(
                      icon: Icons.drive_file_rename_outline_rounded,
                      label: l10n.common_rename,
                    ),
                  ),
                  PopupMenuItem(
                    value: _GroupAction.addSubgroup,
                    child: _MenuRow(
                      icon: Icons.create_new_folder_outlined,
                      label: l10n.tagLibrary_addSubCategory,
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: _GroupAction.delete,
                    child: _MenuRow(
                      icon: Icons.delete_outline_rounded,
                      label: l10n.common_delete,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20, color: color),
      const SizedBox(width: 12),
      Expanded(
        child: Text(label, style: TextStyle(color: color)),
      ),
    ],
  );
}

/// Asks for a group name; returns it trimmed, or null when cancelled.
Future<String?> showTagLibraryGroupNameForm({
  required BuildContext context,
  required String title,
  String initialName = '',
}) {
  return AdaptivePresenter.showForm<String>(
    context: context,
    title: title,
    dialogWidth: 420,
    builder: (formContext, scrollController) => _GroupNameForm(
      scrollController: scrollController,
      initialName: initialName,
    ),
  );
}

class _GroupNameForm extends StatefulWidget {
  const _GroupNameForm({
    required this.scrollController,
    required this.initialName,
  });

  final ScrollController scrollController;
  final String initialName;

  @override
  State<_GroupNameForm> createState() => _GroupNameFormState();
}

class _GroupNameFormState extends State<_GroupNameForm> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ContentSizedAdaptiveForm(
      key: const ValueKey('tag-library-group-name-form'),
      scrollController: widget.scrollController,
      content: [
        TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: context.l10n.tagLibrary_categoryNameHint,
            filled: true,
            fillColor: controlSurfaceColor(theme.colorScheme),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.common_cancel),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) => FilledButton(
                onPressed: value.text.trim().isEmpty ? null : _submit,
                child: Text(context.l10n.common_confirm),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
