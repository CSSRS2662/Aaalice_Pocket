import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/prompt_edit_document.dart';
import 'package:nai_launcher/presentation/screens/generation/widgets/prompt_group_summary.dart';

Future<String> _summaryText(
  WidgetTester tester,
  String text, {
  double width = 140,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: PromptGroupSummary(
              text: text,
              style: const TextStyle(fontSize: 13, height: 1.45),
              emptyLabel: 'empty',
            ),
          ),
        ),
      ),
    ),
  );
  final widget = tester.widget<Text>(
    find.descendant(
      of: find.byType(PromptGroupSummary),
      matching: find.byType(Text),
    ),
  );
  return widget.data ?? widget.textSpan!.toPlainText();
}

void main() {
  test('hidden count counts every tag of a weighted group', () {
    final items = PromptEditDocument.parse('a, 1.2::b, c::, d');
    expect(items, hasLength(3));
    expect(PromptGroupSummary.hiddenTagCount(items, 1), 3);
    expect(PromptGroupSummary.hiddenTagCount(items, 3), 0);
  });

  testWidgets('long sections keep whole tags and count the rest', (
    tester,
  ) async {
    final tags = List.generate(30, (index) => 'tag_$index');
    final text = await _summaryText(tester, tags.join(', '));

    final match = RegExp(r'^((?:tag_\d+, )*tag_\d+) \+(\d+)$').firstMatch(text);
    expect(match, isNotNull, reason: text);
    final shown = match!.group(1)!.split(', ');
    expect(shown, tags.take(shown.length));
    expect(shown.length + int.parse(match.group(2)!), tags.length);
  });

  testWidgets('short sections show everything without a count', (tester) async {
    expect(
      await _summaryText(tester, 'smile, blush', width: 300),
      'smile, blush',
    );
  });

  testWidgets('weights stay readable and disabled tags are shown', (
    tester,
  ) async {
    expect(
      await _summaryText(tester, '1.2::smile::, /*disabled:cat*/', width: 400),
      '1.2::smile::, cat',
    );
  });

  testWidgets('an empty section shows its hint', (tester) async {
    expect(await _summaryText(tester, ' , '), 'empty');
  });
}
