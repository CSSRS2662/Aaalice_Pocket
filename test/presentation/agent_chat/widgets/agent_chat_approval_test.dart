import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/agent_chat/models/agent_approval_change.dart';
import 'package:nai_launcher/presentation/agent_chat/widgets/agent_chat_approval.dart';
import 'package:nai_launcher/presentation/themes/core/layered_surface_style.dart';
import 'package:nai_launcher/presentation/themes/modules/color/palettes/pocket_palette.dart';

void main() {
  Widget app({
    required double width,
    required Widget child,
    TextScaler textScaler = TextScaler.noScaling,
    ThemeData? theme,
  }) {
    return MaterialApp(
      theme: theme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true, textScaler: textScaler),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: width, child: child),
            ),
          ),
        ),
      ),
    );
  }

  AgentChatApprovalCard approval({
    Key? key,
    String requestId = 'request-1',
    Map<String, dynamic>? args,
    int? estimatedAnlas = 12,
    List<String> fileTargets = const [],
    ValueChanged<bool>? onResolve,
  }) {
    return AgentChatApprovalCard(
      key: key ?? ValueKey(requestId),
      toolName: 'submit_generation',
      args:
          args ??
          {
            'prompt': 'A detailed three-day weather chart',
            'model': 'nai-diffusion-4-full',
            'images': 1,
          },
      estimatedAnlas: estimatedAnlas,
      fileTargets: fileTargets,
      onResolve: onResolve ?? (_) {},
    );
  }

  testWidgets(
    'approval text and actions keep readable contrast in both themes',
    (tester) async {
      double contrast(Color foreground, Color background) {
        final a = Color.alphaBlend(foreground, background).computeLuminance();
        final b = background.computeLuminance();
        return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
      }

      for (final palette in [
        const PocketPalette().lightScheme,
        const PocketPalette().darkScheme,
      ]) {
        final scheme = resolveLayeredSurfaceColors(palette);
        await tester.pumpWidget(
          app(
            width: 600,
            theme: ThemeData(colorScheme: scheme),
            child: approval(),
          ),
        );
        final surface = tester.widget<Container>(
          find.byKey(const ValueKey('agent-chat-approval-surface')),
        );
        final background = (surface.decoration! as BoxDecoration).color!;
        expect(background.a, 1);
        for (final text
            in find
                .descendant(
                  of: find.byKey(const ValueKey('agent-chat-approval-surface')),
                  matching: find.byType(Text),
                )
                .evaluate()
                .map((element) => element.widget as Text)) {
          if (text.style?.color case final color?) {
            expect(
              contrast(color, background),
              greaterThanOrEqualTo(4.5),
              reason: text.data,
            );
          }
        }
        for (final button in [
          tester.widget<FilledButton>(
            find.byKey(const ValueKey('agent-chat-approval-deny')),
          ),
          tester.widget<FilledButton>(
            find.byKey(const ValueKey('agent-chat-approval-allow')),
          ),
        ]) {
          final style = button.style!;
          expect(
            contrast(
              style.foregroundColor!.resolve({})!,
              style.backgroundColor!.resolve({})!,
            ),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    },
  );

  testWidgets('is bounded at required widths with TextScaler 3', (
    tester,
  ) async {
    const target = r'C:\Users\Alice\Pictures\novelai\render-final.png';
    for (final width in [320.0, 360.0, 412.0, 600.0, 840.0, 1180.0, 1600.0]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(
        app(
          width: width,
          textScaler: const TextScaler.linear(3),
          child: approval(fileTargets: const [target]),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('agent-chat-approval-surface')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull, reason: 'width $width');

      final buttonFinder = find.byWidgetPredicate(
        (widget) => widget is ButtonStyleButton,
      );
      expect(buttonFinder, findsNWidgets(2));
      for (final element in buttonFinder.evaluate()) {
        expect(
          tester.getSize(find.byWidget(element.widget)).height,
          greaterThanOrEqualTo(48),
        );
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('shows an estimate only when authoritative estimate exists', (
    tester,
  ) async {
    await tester.pumpWidget(app(width: 360, child: approval()));
    expect(find.textContaining('12 Anlas'), findsOneWidget);

    await tester.pumpWidget(
      app(width: 360, child: approval(estimatedAnlas: null)),
    );
    expect(find.textContaining('Anlas'), findsNothing);
  });

  testWidgets('expands sanitized parameters without credentials or paths', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        width: 360,
        child: approval(
          args: {
            'api_token': 'pst-super-secret-token-value',
            'password': 'hunter2',
            'output_path': r'C:\Users\Alice\private\result.png',
            'image': Uint8List.fromList([1, 2, 3]),
            'prompt': 'safe prompt',
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('agent-chat-approval-details')));
    await tester.pumpAndSettle();

    expect(find.textContaining('[redacted]'), findsWidgets);
    expect(find.textContaining('[local path]'), findsWidgets);
    expect(find.textContaining('[binary omitted]'), findsWidgets);
    expect(find.textContaining('safe prompt'), findsWidgets);
    expect(find.textContaining('pst-super-secret-token-value'), findsNothing);
    expect(find.textContaining(r'C:\Users\Alice'), findsNothing);
  });

  testWidgets('shows the write target while path arguments stay redacted', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        width: 360,
        child: approval(
          args: const {'destination_path': r'C:\Users\Alice\art\out.png'},
          fileTargets: const [r'C:\Users\Alice\art\out.png'],
        ),
      ),
    );

    expect(find.textContaining(r'C:\Users\Alice\art\out.png'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('agent-chat-approval-details')));
    await tester.pumpAndSettle();

    expect(find.textContaining('[local path]'), findsWidgets);
    expect(find.textContaining(r'C:\Users\Alice\art\out.png'), findsOneWidget);
  });

  testWidgets(
    'same tool and arguments become actionable for a new request id',
    (tester) async {
      final decisions = <bool>[];
      await tester.pumpWidget(
        app(width: 360, child: approval(onResolve: decisions.add)),
      );

      final allow = find.byKey(const ValueKey('agent-chat-approval-allow'));
      await tester.tap(allow);
      await tester.tap(allow);
      await tester.pump();
      expect(decisions, [isTrue]);

      await tester.pumpWidget(
        app(
          width: 360,
          child: approval(requestId: 'request-2', onResolve: decisions.add),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('agent-chat-approval-deny')));
      expect(decisions, [isTrue, isFalse]);
    },
  );

  testWidgets('delete approvals retain irreversible-risk wording', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        width: 360,
        child: AgentChatApprovalCard(
          toolName: 'delete_tag_library_entry',
          args: const {'id': 'entry-1'},
          estimatedAnlas: null,
          fileTargets: const [],
          onResolve: (_) {},
        ),
      ),
    );

    expect(find.textContaining('cannot be undone'), findsOneWidget);
    expect(find.textContaining('Anlas'), findsNothing);
  });

  testWidgets('a rewrite shows its changes as a diff', (tester) async {
    await tester.pumpWidget(
      app(
        width: 360,
        child: AgentChatApprovalCard(
          toolName: 'update_tag_library_entry',
          args: const {'entry_id': 'entry-1', 'content': 'blue eyes, grin'},
          estimatedAnlas: null,
          fileTargets: const [],
          changes: const [
            AgentApprovalChange(
              field: 'content',
              before: 'blue eyes, smile',
              after: 'blue eyes, grin',
            ),
            AgentApprovalChange(
              field: 'favorite',
              before: 'false',
              after: 'true',
            ),
          ],
          onResolve: (_) {},
        ),
      ),
    );

    expect(find.textContaining('Check the changes below'), findsOneWidget);
    final content = tester.widget<RichText>(
      find.descendant(
        of: find.byKey(const ValueKey('agent-chat-approval-change-content')),
        matching: find.byType(RichText),
      ),
    );
    final spans = <TextSpan>[];
    content.text.visitChildren((span) {
      if (span is TextSpan && span.text != null) spans.add(span);
      return true;
    });
    final removed = spans.singleWhere((span) => span.text == 'smile');
    final added = spans.singleWhere((span) => span.text == 'grin');
    expect(removed.style?.decoration, TextDecoration.lineThrough);
    expect(added.style?.decoration, isNot(TextDecoration.lineThrough));
    expect(added.style?.color, isNot(removed.style?.color));
    expect(
      spans.where((span) => span.text == 'blue eyes, ').single.style,
      isNull,
      reason: 'unchanged text keeps the body style',
    );
    // Switches read as the old value struck, then the new one.
    expect(find.textContaining('No'), findsOneWidget);
    expect(find.textContaining('Yes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
