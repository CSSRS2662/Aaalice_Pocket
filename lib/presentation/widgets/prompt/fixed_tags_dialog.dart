import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../adaptive/adaptive_presenter.dart';
import '../../providers/fixed_tag_usage_provider.dart';
import '../../providers/fixed_tags_provider.dart';
import '../../providers/fixed_tags_sort_provider.dart';
import '../../providers/name_sort_key_provider.dart';
import '../../providers/tag_library_page_provider.dart';
import 'fixed_tags_dialog_controller.dart';
import 'fixed_tags_dialog_coordinator.dart';
import 'fixed_tags_dialog_models.dart';
import 'fixed_tags_dialog_view.dart';

export 'fixed_tag_library_picker_dialog.dart' show FixedTagLibraryPickerDialog;

/// 固定词管理对话框。
///
/// 该 shell 只负责连接唯一业务 Provider 与对话框本地生命周期；展示、交互
/// 编排和几何状态分别由 view、coordinator 与 controller 承担。
class FixedTagsDialog extends ConsumerStatefulWidget {
  const FixedTagsDialog({super.key, this.presentationManaged = false});

  final bool presentationManaged;

  static Future<void> show(BuildContext context) {
    return AdaptivePresenter.showForm<void>(
      context: context,
      showHeader: false,
      dialogWidth: 980,
      builder: (_, __) => const FixedTagsDialog(presentationManaged: true),
    );
  }

  @override
  ConsumerState<FixedTagsDialog> createState() => _FixedTagsDialogState();
}

class _FixedTagsDialogState extends ConsumerState<FixedTagsDialog> {
  late final FixedTagsDialogController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FixedTagsDialogController();
    // 旧数据里关联条目的分组可能已落后于词库。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(fixedTagsNotifierProvider.notifier)
          .reconcileCategoriesWithLibrary();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sort = ref.watch(fixedTagsSortProvider);
    final viewData = FixedTagsDialogViewData(
      state: ref.watch(fixedTagsNotifierProvider),
      libraryEntries: ref.watch(
        tagLibraryPageNotifierProvider.select((state) => state.entries),
      ),
      libraryCategories: ref.watch(
        tagLibraryPageNotifierProvider.select((state) => state.categories),
      ),
      sort: sort,
      usage: ref.watch(fixedTagUsageProvider),
      // 拼音表只在按名称排序时加载。
      nameSortKey: sort.sort == FixedTagsSort.name
          ? ref.watch(nameSortKeyProvider).valueOrNull
          : null,
    );
    final commands = FixedTagsDialogCoordinator(ref).commands(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => FixedTagsDialogView(
        data: viewData,
        commands: commands,
        controller: _controller,
        presentationManaged: widget.presentationManaged,
      ),
    );
  }
}
