import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/adaptive/interaction_policy.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/tools/closed_region_fill_tool.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/tools/frame_tool.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/widgets/toolbar/mobile_toolbar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'toolbar_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // EditorState 构造时会异步读取工具设置
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const closedFill = ClosedRegionFillTool.toolId;

  Widget bottomBar(Widget toolbar) =>
      Align(alignment: Alignment.bottomCenter, child: toolbar);

  testWidgets('the bar lists only the tools of the layer being edited', (
    tester,
  ) async {
    final (:state, :source, :mask) = createInpaintToolbarState();
    await pumpToolbarHost(
      tester,
      size: const Size(360, 720),
      policy: InteractionPolicy.touchFirst,
      child: bottomBar(MobileToolbar(state: state)),
    );

    // 蒙版层：重绘组与通用组，没有编辑组，也不再显示组标题
    expect(toolGroup('inpaint'), findsOneWidget);
    expect(toolGroup('common'), findsOneWidget);
    expect(toolGroup('edit'), findsNothing);
    expect(find.text('重绘'), findsNothing);
    expectEntryInGroup('inpaint', closedFill);
    expectEntryInGroup('inpaint', FrameTool.toolId);
    for (final label in ['画笔', '按色', '封闭', '取景框', '选区']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await tester.tap(toolEntry('inpaint', 'eraser'));
    await tester.pump();
    expect(state.layerManager.activeLayer, same(mask));
    expect(state.currentTool?.id, 'eraser');
    expect(isEntrySelected(tester, 'inpaint', 'eraser'), isTrue);

    // 图片层：换成编辑组
    state.layerManager.setActiveLayer(source.id);
    await tester.pump();
    expect(toolGroup('inpaint'), findsNothing);
    expectEntryInGroup('edit', 'blur');
    expect(find.text('填充'), findsOneWidget);
  });

  testWidgets('tapping a selected folded slot moves to the next family tool', (
    tester,
  ) async {
    final (:state, :source, mask: _) = createInpaintToolbarState();
    state.layerManager.setActiveLayer(source.id);
    await pumpToolbarHost(
      tester,
      size: const Size(360, 720),
      policy: InteractionPolicy.touchFirst,
      child: bottomBar(MobileToolbar(state: state)),
    );

    final retouch = toolSlot('edit', 'retouch');
    await tester.tap(retouch);
    await tester.pump();
    expect(state.currentTool?.id, 'blur');

    await tester.tap(retouch);
    await tester.pump();
    expect(state.currentTool?.id, 'clone_stamp');
    expect(state.layerManager.activeLayer, same(source));
    expect(isEntrySelected(tester, 'edit', 'clone_stamp'), isTrue);
    expect(find.text('仿制'), findsOneWidget);
  });

  testWidgets('long-press opens the family above the bottom bar', (
    tester,
  ) async {
    final (:state, :source, mask: _) = createInpaintToolbarState();
    state.layerManager.setActiveLayer(source.id);
    await pumpToolbarHost(
      tester,
      size: const Size(360, 720),
      policy: InteractionPolicy.touchFirst,
      child: bottomBar(MobileToolbar(state: state)),
    );
    final slot = toolSlot('edit', 'region');
    await tester.ensureVisible(slot);
    await tester.pump();

    await tester.longPress(slot);
    await tester.pump();

    expect(flyoutLabels(tester), ['填充', '魔棒']);
    final slotRect = tester.getRect(slot);
    final items = find.byType(MenuItemButton);
    expect(tester.getRect(items.last).bottom, lessThanOrEqualTo(slotRect.top));
    for (final item in items.evaluate()) {
      final rect = tester.getRect(find.byWidget(item.widget));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
      expect(rect.height, greaterThanOrEqualTo(44));
    }
    expect(tester.takeException(), isNull);

    await chooseFlyoutEntry(tester, flyoutEntry('edit', 'magic_wand'));
    expect(state.currentTool?.id, 'magic_wand');

    // 折叠按钮没有提示气泡，说明只在二级菜单里
    expect(
      find.descendant(of: slot, matching: find.byType(Tooltip)),
      findsNothing,
    );
  });

  for (final width in const [320.0, 600.0]) {
    for (final textScale in const [1.0, 3.0]) {
      for (final locale in const [Locale('zh'), Locale('en')]) {
        testWidgets('every tool stays reachable: $width $locale x$textScale', (
          tester,
        ) async {
          final (:state, :source, mask: _) = createInpaintToolbarState();
          await pumpToolbarHost(
            tester,
            size: Size(width, 720),
            locale: locale,
            textScale: textScale,
            policy: InteractionPolicy.touchFirst,
            child: bottomBar(MobileToolbar(state: state)),
          );

          Future<void> expectReachable(Finder target) async {
            await tester.ensureVisible(target);
            await tester.pump();
            final rect = tester.getRect(target);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
            expect(rect.height, greaterThanOrEqualTo(44));
            expect(rect.width, greaterThanOrEqualTo(44));
          }

          expect(tester.takeException(), isNull);
          for (final target in [
            toolEntry('inpaint', 'brush'),
            toolEntry('inpaint', FrameTool.toolId),
            toolSlot('common', 'selection'),
          ]) {
            await expectReachable(target);
          }

          state.layerManager.setActiveLayer(source.id);
          await tester.pump();
          expect(tester.takeException(), isNull);
          for (final target in [
            toolEntry('edit', 'color_picker'),
            toolSlot('edit', 'retouch'),
            toolSlot('common', 'selection'),
          ]) {
            await expectReachable(target);
          }
        });
      }
    }
  }

  testWidgets('a landscape rail stacks the same tools vertically', (
    tester,
  ) async {
    final (:state, source: _, mask: _) = createInpaintToolbarState();
    await pumpToolbarHost(
      tester,
      size: const Size(780, 360),
      policy: InteractionPolicy.touchFirst,
      child: Align(
        alignment: Alignment.centerLeft,
        child: MobileToolbar(state: state, axis: Axis.vertical),
      ),
    );

    final brush = tester.getRect(toolEntry('inpaint', 'brush'));
    final eraser = tester.getRect(toolEntry('inpaint', 'eraser'));
    expect(eraser.top, greaterThanOrEqualTo(brush.bottom));
    expect(brush.left, eraser.left);
    final selection = toolSlot('common', 'selection');
    await tester.ensureVisible(selection);
    await tester.pump();
    expect(tester.getRect(selection).bottom, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
  });
}
