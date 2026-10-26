import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../../data/models/gallery/nai_image_metadata.dart';
import '../../../../../data/models/gallery/nai_prompt_export_codec.dart';
import '../../../../adaptive/interaction_policy.dart';
import '../../app_toast.dart';
import '../../prompt_copy_split_button.dart';
import '../../save_as_preset_dialog.dart';
import 'prompt_copy_dialog.dart';

/// The detail panel's actions under the metadata: the copy menu, the seed
/// and saving the parameters as a preset.
class DetailActionButtons extends StatelessWidget {
  final NaiImageMetadata metadata;

  /// Starts picking single tags to copy; null hides the menu item.
  final VoidCallback? onPickTags;

  const DetailActionButtons({
    super.key,
    required this.metadata,
    this.onPickTags,
  });

  Future<void> _copyPositivePrompt(BuildContext context) async {
    final prompt = await PromptCopyDialog.show(context, metadata: metadata);
    if (!context.mounted) return;
    await _writePrompt(context, prompt);
  }

  Future<void> _copyAllTags(BuildContext context) =>
      _writePrompt(context, NaiPromptExportCodec.encode(metadata));

  Future<void> _customCopyTags(BuildContext context) async {
    final prompt = await PromptCopyDialog.showExport(
      context,
      metadata: metadata,
    );
    if (!context.mounted) return;
    await _writePrompt(context, prompt);
  }

  Future<void> _writePrompt(BuildContext context, String? prompt) async {
    if (prompt == null || prompt.trim().isEmpty || !context.mounted) return;
    await Clipboard.setData(ClipboardData(text: prompt));
    if (context.mounted) {
      AppToast.success(context, context.l10n.gallery_promptCopied);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The copy menu takes a row of its own so its label shows whole
          // on a phone; the seed and preset actions share the next row.
          SizedBox(
            width: double.infinity,
            child: PromptCopySplitButton(
              primaryLabel: context.l10n.onlineGallery_copyAllTags,
              menuTooltip: context.l10n.common_copy,
              menuButtonKey: const ValueKey('detail-copy-menu'),
              onPressed: () => _copyAllTags(context),
              menuChildren: [
                if (onPickTags case final pickTags?)
                  MenuItemButton(
                    key: const ValueKey('detail-pick-tags'),
                    onPressed: pickTags,
                    leadingIcon: const Icon(Icons.checklist_rounded, size: 18),
                    child: Text(context.l10n.detail_pickTags),
                  ),
                MenuItemButton(
                  onPressed: () => _customCopyTags(context),
                  leadingIcon: const Icon(Icons.tune, size: 18),
                  child: Text(context.l10n.onlineGallery_customCopyTags),
                ),
                MenuItemButton(
                  onPressed: () => _copyPositivePrompt(context),
                  leadingIcon: const Icon(Icons.shield_outlined, size: 18),
                  child: Text(
                    context.l10n.detail_copyLabel(
                      context.l10n.prompt_positivePrompt,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (metadata.seed != null) ...[
                Expanded(
                  child: _ActionButton(
                    icon: Icons.tag,
                    label: context.l10n.localGallery_copySeed,
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: metadata.seed.toString()),
                      );
                      AppToast.success(
                        context,
                        context.l10n.gallery_seedCopied,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: _ActionButton(
                  icon: Icons.bookmark_add,
                  label: context.l10n.detail_savePreset,
                  onPressed: () =>
                      SaveAsPresetDialog.show(context, metadata: metadata),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 操作按钮
class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 150),
          constraints: BoxConstraints(
            minHeight: context.interactionPolicy.minimumControlExtent,
          ),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: _isHovered
                ? colorScheme.primary.withValues(alpha: 0.1)
                : colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: _isHovered
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: _isHovered
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
