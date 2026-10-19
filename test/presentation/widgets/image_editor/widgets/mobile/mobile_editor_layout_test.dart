import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/adaptive/interaction_policy.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/canvas/editor_canvas.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/core/editor_state.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/image_editor_controller.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/image_editor_types.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/image_editor_workspace.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/layers/layer_role.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/tools/brush_tool.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/widgets/mobile/focused_inpaint_bar.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/widgets/toolbar/mobile_toolbar.dart';

final _inpaintConfig = ImageEditorSessionConfig(
  initialSize: const Size(512, 512),
  mode: ImageEditorMode.inpaint,
  debugOptions: const ImageEditorDebugOptions(disableDropRegion: true),
);

const _touch = InteractionPolicy(
  modality: InteractionModality.touch,
  touchAvailable: true,
  precisePointerAvailable: false,
);

/// 泵入移动端布局的重绘会话，并补一张图片层，让「编辑」可切换
Future<EditorState> _pumpInpaint(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final session = ImageEditorController(config: _inpaintConfig);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: InteractionPolicyScope(
        initialPolicy: _touch,
        child: ImageEditorWorkspace(
          controller: session,
          config: _inpaintConfig,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final state = tester.widget<EditorCanvas>(find.byType(EditorCanvas)).state;
  final mask = state.layerManager.maskLayers.single;
  state.layerManager.addLayer(name: 'Source');
  // 新建图层会成为当前图层；会话开始时编辑的是蒙版
  state.layerManager.setActiveLayer(mask.id);
  await tester.pumpAndSettle();
  return state;
}

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the role switch swaps the tool bar and remembers each tool', (
    tester,
  ) async {
    final state = await _pumpInpaint(tester);
    expect(state.activeLayerRole, LayerRole.mask);
    expect(_key('editor-tool-group-inpaint'), findsOneWidget);
    expect(_key('editor-tool-group-edit'), findsNothing);

    await _tap(tester, _key('editor-tool-inpaint:eraser'));
    await _tap(tester, _key('editor-role-image'));
    expect(state.activeLayerRole, LayerRole.image);
    expect(_key('editor-tool-group-edit'), findsOneWidget);
    expect(_key('editor-tool-group-inpaint'), findsNothing);
    // 橡皮擦两边都有，换到图片层时沿用
    expect(state.currentTool?.id, 'eraser');

    await _tap(tester, _key('editor-tool-slot-edit:family:retouch'));
    expect(state.currentTool?.id, 'blur');

    await _tap(tester, _key('editor-role-mask'));
    expect(state.activeLayerRole, LayerRole.mask);
    expect(state.currentTool?.id, 'eraser');
    await _tap(tester, _key('editor-role-image'));
    expect(state.currentTool?.id, 'blur');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tool missing from the new bar falls back to the brush', (
    tester,
  ) async {
    final state = await _pumpInpaint(tester);
    await _tap(tester, _key('editor-tool-inpaint:frame'));
    expect(state.currentTool?.id, 'frame');

    await _tap(tester, _key('editor-role-image'));
    expect(state.currentTool?.id, 'brush');
    expect(isEditorToolShownOnMobile(state, state.currentTool!), isTrue);
  });

  testWidgets('mask brush size comes from the chips and the side slider', (
    tester,
  ) async {
    final state = await _pumpInpaint(tester);
    final brush = state.currentTool! as BrushTool;
    expect(_key('editor-tool-slider-size'), findsOneWidget);
    expect(_key('editor-tool-slider-opacity'), findsNothing);

    await _tap(tester, _key('editor-size-chip-80'));
    expect(brush.maskSize, 80);

    final slider = _key('editor-tool-slider-size');
    await tester.drag(slider, const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(brush.maskSize, greaterThan(80));
    expect(_key('editor-size-preview'), findsNothing, reason: '松手后预览消失');

    // 图片笔刷另有不透明度
    await _tap(tester, _key('editor-role-image'));
    expect(_key('editor-tool-slider-opacity'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('undo and redo sit side by side at the bottom right', (
    tester,
  ) async {
    await _pumpInpaint(tester);
    final undo = tester.getRect(find.byTooltip('Undo'));
    final redo = tester.getRect(find.byTooltip('Redo'));
    final canvas = tester.getRect(find.byType(EditorCanvas));
    expect(redo.left, greaterThanOrEqualTo(undo.right));
    expect(redo.top, undo.top);
    expect(canvas.right - redo.right, lessThan(24));
    expect(canvas.bottom - redo.bottom, lessThan(24));
    final slider = tester.getRect(_key('editor-tool-slider-size'));
    expect(slider.bottom, lessThanOrEqualTo(redo.top));
  });

  testWidgets('all settings opens the tool panel in a sheet', (tester) async {
    await _pumpInpaint(tester);
    await _tap(tester, _key('editor-tool-settings-button'));
    expect(_key('editor-tool-settings-sheet'), findsOneWidget);
    expect(
      find.descendant(
        of: _key('editor-tool-settings-sheet'),
        matching: find.text('Mask Brush'),
      ),
      findsOneWidget,
    );
    await _tap(tester, find.byTooltip('Close'));
    expect(_key('editor-tool-settings-sheet'), findsNothing);
  });

  testWidgets('focused inpaint runs in a bar instead of a floating card', (
    tester,
  ) async {
    final state = await _pumpInpaint(tester);
    expect(find.byType(FocusedInpaintBar), findsNothing);
    expect(find.text('Focused Inpaint'), findsNothing);

    await _tap(tester, _key('editor-focus-chip'));
    expect(find.byType(FocusedInpaintBar), findsOneWidget);
    expect(state.currentTool?.id, 'rect_selection');
    final bar = tester.widget<FocusedInpaintBar>(
      find.byType(FocusedInpaintBar),
    );
    expect(bar.step, FocusedInpaintStep.selectArea);
    expect(bar.hasArea, isFalse);

    // 框好区域前不能进入第二步
    await _tap(tester, _key('editor-focus-step-paint'));
    expect(state.currentTool?.id, 'rect_selection');

    await _tap(tester, find.byTooltip('Exit focused inpaint'));
    expect(find.byType(FocusedInpaintBar), findsNothing);
    expect(state.currentTool?.id, 'brush');
  });

  testWidgets('the more sheet groups mask and canvas actions', (tester) async {
    await _pumpInpaint(tester);
    await _tap(tester, find.byTooltip('More'));
    for (final id in [
      'load-mask',
      'reset-mask',
      'output-resolution',
      'shift-edges',
      'crop-to-frame',
    ]) {
      expect(_key('editor-more-$id'), findsOneWidget, reason: id);
    }
    expect(_key('editor-more-clear-layer'), findsNothing);
    expect(_key('editor-more-effects'), findsNothing);
  });

  for (final scenario in const <({Size size, double scale})>[
    (size: Size(320, 720), scale: 1),
    (size: Size(320, 720), scale: 3),
    (size: Size(600, 760), scale: 1),
    (size: Size(390, 844), scale: 1.6),
    (size: Size(780, 360), scale: 1),
  ]) {
    testWidgets('no overflow with every bar shown: '
        '${scenario.size} x${scenario.scale}', (tester) async {
      final state = await _pumpInpaint(
        tester,
        size: scenario.size,
        textScale: scenario.scale,
      );
      await _tap(tester, _key('editor-focus-chip'));
      expect(tester.takeException(), isNull);
      for (final toolId in ['brush', 'magic_wand', 'fill', 'frame']) {
        state.setToolById(toolId);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: toolId);
      }
      await _tap(tester, _key('editor-role-image'));
      for (final toolId in ['brush', 'clone_stamp', 'color_picker', 'move']) {
        state.setToolById(toolId);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: toolId);
      }
      expect(find.byTooltip('More').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Done').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Undo').hitTestable(), findsOneWidget);
      if (scenario.size.width > scenario.size.height) {
        final bar = tester.getRect(find.byType(MobileToolbar));
        expect(bar.width, MobileToolbar.extent, reason: '横屏竖排在左侧');
      }
    });
  }
}
