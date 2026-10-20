import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nai_launcher/core/autocomplete/autocomplete_cache_database.dart';
import 'package:nai_launcher/core/autocomplete/autocomplete_providers.dart';
import 'package:nai_launcher/core/autocomplete/autocomplete_settings.dart';
import 'package:nai_launcher/core/autocomplete/completion_models.dart';
import 'package:nai_launcher/core/autocomplete/danbooru_completion_source.dart';
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/autocomplete_services_provider.dart';
import 'package:nai_launcher/presentation/widgets/autocomplete/autocomplete_overlay_handle.dart';
import 'package:nai_launcher/presentation/widgets/autocomplete/autocomplete_wrapper.dart';

/// Already in the field, so its tile is faded and cannot be picked.
const _written = 'blue_sky, ';

final _surface = find.byKey(const ValueKey('autocomplete-popup-surface'));
final _insert = find.byKey(const ValueKey('autocomplete-pick-insert'));

Finder _tile(String tag) => find.byKey(ValueKey('autocomplete-candidate-$tag'));

void main() {
  late TextEditingController controller;
  late FocusNode focusNode;

  setUp(() async {
    Hive.init(
      '${Directory.systemTemp.path}/autocomplete_picks_'
      '${DateTime.now().microsecondsSinceEpoch}',
    );
    // Memory backend: writes under FakeAsync never finish and lock the box.
    await Hive.openBox(StorageKeys.settingsBox, bytes: Uint8List(0));
    await Hive.openBox(StorageKeys.historyBox, bytes: Uint8List(0));
    controller = TextEditingController(text: '${_written}blu')
      ..selection = const TextSelection.collapsed(offset: _written.length + 3);
    focusNode = FocusNode();
  });

  tearDown(() async {
    controller.dispose();
    focusNode.dispose();
    await Hive.close().timeout(const Duration(seconds: 10));
  });

  Future<void> pumpField(
    WidgetTester tester, {
    AutocompleteOverlayHandle? handle,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          autocompleteSettingsProvider.overrideWith((ref) => _Settings()),
          autocompleteServicesProvider.overrideWithValue(
            AutocompleteServices(
              localSources: [_BlueSource()],
              dictionaryTranslations: const _NoTranslations(),
              llmTranslations: const _NoTranslations(),
              danbooru: _NoDanbooru(),
            ),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AutocompleteWrapper(
              controller: controller,
              focusNode: focusNode,
              overlayHandle: handle,
              maxLines: 4,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                maxLines: 4,
              ),
            ),
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();
    final field = find.byType(TextField);
    await tester.enterText(field, '${_written}bl');
    await tester.pump();
    await tester.enterText(field, '${_written}blu');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.text('blue_hair'), findsOne);
  }

  Future<void> longPress(WidgetTester tester, String tag) async {
    await tester.longPress(_tile(tag));
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, String tag) async {
    await tester.tap(_tile(tag));
    await tester.pump();
  }

  testWidgets('a long press starts multi-select; Enter writes the picks', (
    tester,
  ) async {
    await pumpField(tester);

    await longPress(tester, 'blue_hair');
    expect(find.text('Insert 1'), findsOne);
    expect(controller.text, '${_written}blu', reason: '长按只开始多选，不插入');

    await tap(tester, 'blush');
    await tap(tester, 'blue_eyes');
    expect(find.text('Insert 3'), findsOne);
    await tap(tester, 'blush');
    expect(find.text('Insert 2'), findsOne);
    // A written tag cannot be picked.
    await tester.tap(_tile('blue_sky'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Insert 2'), findsOne);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.text, '${_written}blue_hair, blue_eyes, ');
    expect(controller.selection.extentOffset, controller.text.length);
    expect(_insert, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a line break typed by a soft keyboard writes the picks', (
    tester,
  ) async {
    await pumpField(tester);
    await longPress(tester, 'blush');
    await tap(tester, 'blue_hair');

    await tester.enterText(find.byType(TextField), '${_written}blu\n');
    await tester.pump();

    expect(controller.text, '${_written}blush, blue_hair, ');
    expect(controller.text, isNot(contains('\n')));
    expect(_insert, findsNothing);
  });

  testWidgets('the insert button writes the picks', (tester) async {
    await pumpField(tester);
    await longPress(tester, 'blue_eyes');

    await tester.tap(_insert);
    await tester.pump();

    expect(controller.text, '${_written}blue_eyes, ');
  });

  testWidgets('Back, Escape, cancel or the last drop leave multi-select only', (
    tester,
  ) async {
    await pumpField(tester);

    await longPress(tester, 'blue_hair');
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(_insert, findsNothing);
    expect(_surface, findsOne, reason: '返回只退出多选，弹窗保留');

    await longPress(tester, 'blue_hair');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(_insert, findsNothing);
    expect(_surface, findsOne);

    await longPress(tester, 'blue_hair');
    await tester.tap(find.byKey(const ValueKey('autocomplete-pick-cancel')));
    await tester.pump();
    expect(_insert, findsNothing);

    await longPress(tester, 'blue_hair');
    await tap(tester, 'blue_hair');
    expect(_insert, findsNothing);
    expect(_surface, findsOne);
    expect(controller.text, '${_written}blu');

    // Out of the mode, a tap inserts again.
    await tap(tester, 'blush');
    expect(controller.text, '${_written}blush, ');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an editor handling Back steps the popup back via its handle', (
    tester,
  ) async {
    final handle = AutocompleteOverlayHandle(hostHandlesBack: true);
    addTearDown(handle.dispose);
    await pumpField(tester, handle: handle);
    await longPress(tester, 'blue_hair');

    handle.dismiss();
    await tester.pump();
    expect(_insert, findsNothing);
    expect(_surface, findsOne);

    handle.dismiss();
    await tester.pump();
    expect(_surface, findsNothing);
  });
}

class _BlueSource implements CompletionSource {
  static const _tags = ['blue_eyes', 'blue_hair', 'blush', 'blue_sky'];

  @override
  Future<List<CompletionCandidate>> search(CompletionQuery query) async {
    if (query.relatedTag != null) return const [];
    return [
      for (final tag in _tags)
        CompletionCandidate(
          canonicalTag: tag,
          category: TagCategory.general,
          postCount: 1000,
          matchKind: CompletionMatchKind.englishPrefix,
          sources: const {CompletionSourceKind.base},
        ),
    ];
  }
}

class _Settings extends AutocompleteSettingsNotifier {
  _Settings() : super(LocalStorageService()) {
    state = const AutocompleteSettings(
      danbooruEnabled: false,
      relatedTagsEnabled: false,
      zhInstallPromptDismissed: true,
    );
  }
}

class _NoTranslations implements TranslationResolver {
  const _NoTranslations();

  @override
  Future<Map<String, String>> resolve(
    List<String> canonicalTags, {
    required String locale,
  }) async => const {};
}

class _NoDanbooru extends DanbooruCompletionSource {
  _NoDanbooru() : super(cache: _MemoryCache());

  @override
  Future<List<CompletionCandidate>> search(CompletionQuery query) async =>
      const [];

  @override
  Future<List<CompletionCandidate>> relatedTags(
    String tag, {
    int limit = 20,
  }) async => const [];
}

class _MemoryCache extends AutocompleteCacheDatabase {
  @override
  Future<CachedAutocompletePayload?> getRemote(String key) async => null;

  @override
  Future<void> putRemote(
    String key,
    List<Map<String, dynamic>> payload,
  ) async {}
}
