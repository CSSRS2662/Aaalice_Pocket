import 'package:flutter/material.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../core/editor_state.dart';
import '../../layers/layer_role.dart';
import 'editor_segmented_switch.dart';

/// 移动端顶栏：返回、重绘会话的「重绘 | 编辑」或编辑会话的标题、图层、更多与完成
class MobileEditorTopBar extends StatelessWidget {
  const MobileEditorTopBar({
    super.key,
    required this.state,
    required this.title,
    required this.doneLabel,
    required this.onDone,
    required this.doneListenable,
    required this.canDone,
    required this.onShowLayers,
    required this.onShowMore,
  });

  final EditorState state;
  final String title;
  final String doneLabel;
  final VoidCallback onDone;
  final Listenable doneListenable;
  final bool Function() canDone;
  final VoidCallback onShowLayers;
  final VoidCallback onShowMore;

  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final showsBack = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    return Material(
      color: theme.colorScheme.surface,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;
            final roomy = constraints.maxWidth >= 360 && !largeText;
            return Row(
              children: [
                if (showsBack)
                  const BackButton()
                else
                  const SizedBox(width: 12),
                const SizedBox(width: 4),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: state.rolePolicy.rolesEnabled
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: EditorRoleSwitch(
                              state: state,
                              showIcons: constraints.maxWidth >= 400,
                            ),
                          )
                        : Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge,
                          ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.editor_layers,
                  icon: const Icon(Icons.layers_outlined),
                  onPressed: onShowLayers,
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
                  icon: const Icon(Icons.more_vert),
                  onPressed: onShowMore,
                ),
                ListenableBuilder(
                  listenable: doneListenable,
                  builder: (context, _) {
                    final onPressed = canDone() ? onDone : null;
                    return Tooltip(
                      message: doneLabel,
                      excludeFromSemantics: roomy,
                      child: roomy
                          ? FilledButton(
                              onPressed: onPressed,
                              child: Text(doneLabel),
                            )
                          : IconButton.filled(
                              icon: const Icon(Icons.check),
                              onPressed: onPressed,
                            ),
                    );
                  },
                ),
                const SizedBox(width: 8),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 重绘会话的编辑对象：重绘改蒙版，编辑改图片；切换即切到该角色的图层
class EditorRoleSwitch extends StatelessWidget {
  const EditorRoleSwitch({
    super.key,
    required this.state,
    this.showIcons = true,
  });

  final EditorState state;
  final bool showIcons;

  @override
  Widget build(BuildContext context) {
    final layers = state.layerManager;
    return ListenableBuilder(
      listenable: Listenable.merge([layers, layers.activeLayerNotifier]),
      builder: (context, _) {
        final l10n = context.l10n;
        return EditorSegmentedSwitch<LayerRole>(
          segments: [
            EditorSegment(
              key: const ValueKey('editor-role-mask'),
              value: LayerRole.mask,
              label: l10n.editor_toolGroupInpaint,
              icon: showIcons ? Icons.gesture : null,
              enabled: layers.preferredLayerFor(LayerRole.mask) != null,
            ),
            EditorSegment(
              key: const ValueKey('editor-role-image'),
              value: LayerRole.image,
              label: l10n.editor_toolGroupEdit,
              icon: showIcons ? Icons.image_outlined : null,
              enabled: layers.preferredLayerFor(LayerRole.image) != null,
            ),
          ],
          selected: state.activeLayerRole,
          onSelected: (role) {
            final layer = layers.preferredLayerFor(role);
            if (layer != null && layer.id != layers.activeLayer?.id) {
              layers.setActiveLayer(layer.id);
            }
          },
        );
      },
    );
  }
}
