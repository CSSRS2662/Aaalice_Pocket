import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/agent/resources/agent_chat_resource_reference.dart';
import 'package:nai_launcher/core/agent/resources/agent_chat_resource_reference_codec.dart';
import 'package:nai_launcher/presentation/agent_chat/services/generation_image_favorite_toolbox.dart';
import 'package:nai_launcher/presentation/providers/image_generation_provider.dart';

void main() {
  late Directory root;
  late File imageFile;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('generation-favorite-test-');
    imageFile = File('${root.path}/image.png');
    await imageFile.writeAsBytes(const [1, 2, 3]);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('persists favorite through the indexed local-gallery owner', () async {
    final image = _image('generated', imageFile.path);
    final writes = <bool>[];
    final toolbox = GenerationImageFavoriteToolbox.forTesting(
      resolveImage: (_) => image,
      readFavorite: (_) async =>
          const LocalGalleryFavoriteRecord(id: 17, favorite: false),
      writeFavorite: (_, favorite) async {
        writes.add(favorite);
        return favorite;
      },
    );

    final result = await toolbox.tools().single.execute('favorite', {
      'resource_ref': _ref('generated'),
      'favorite': true,
    });

    expect(result.isError, isFalse);
    expect(result.details['local_gallery_image_id'], 17);
    expect(result.details['favorite'], isTrue);
    expect(writes, [true]);
    expect(
      (result.details['local_gallery_resource_ref'] as Map)['resourceId'],
      '17',
    );
  });

  test('rejects failed snapshots and unindexed history images', () async {
    final failed = _image(
      'failed',
      imageFile.path,
      kind: GeneratedImageKind.failedStreamSnapshot,
    );
    final failedToolbox = GenerationImageFavoriteToolbox.forTesting(
      resolveImage: (_) => failed,
      readFavorite: (_) async => fail('must not read local gallery'),
      writeFavorite: (_, __) async => fail('must not mutate local gallery'),
    );

    final failedResult = await failedToolbox.tools().single.execute('failed', {
      'resource_ref': _ref('failed'),
      'favorite': true,
    });
    expect(failedResult.details['code'], 'failed_stream_snapshot');

    final unindexedToolbox = GenerationImageFavoriteToolbox.forTesting(
      resolveImage: (_) => _image('unindexed', imageFile.path),
      readFavorite: (_) async => null,
      writeFavorite: (_, __) async => fail('must not mutate local gallery'),
    );
    final unindexedResult = await unindexedToolbox.tools().single.execute(
      'unindexed',
      {'resource_ref': _ref('unindexed'), 'favorite': true},
    );
    expect(unindexedResult.details['code'], 'local_record_required');
  });

  test(
    'favoriting an unsaved history image saves it into the gallery',
    () async {
      final unsaved = GeneratedImage(
        id: 'unsaved',
        bytes: Uint8List.fromList(const [1, 2, 3]),
        width: 1,
        height: 1,
      );
      String? savedPath;
      final writes = <bool>[];
      final toolbox = GenerationImageFavoriteToolbox.forTesting(
        resolveImage: (_) =>
            savedPath == null ? unsaved : unsaved.copyWithFilePath(savedPath!),
        saveToGallery: (image) async {
          expect(image.id, 'unsaved');
          return savedPath = imageFile.path;
        },
        readFavorite: (path) async {
          expect(path, imageFile.path);
          return const LocalGalleryFavoriteRecord(id: 5, favorite: false);
        },
        writeFavorite: (_, favorite) async {
          writes.add(favorite);
          return favorite;
        },
      );

      final result = await toolbox.tools().single.execute('save', {
        'resource_ref': _ref('unsaved'),
        'favorite': true,
      });

      expect(result.isError, isFalse);
      expect(result.details['favorite'], isTrue);
      expect(result.details['local_gallery_image_id'], 5);
      expect(writes, [true]);
    },
  );

  test('unfavoriting an image outside the gallery changes nothing', () async {
    final toolbox = GenerationImageFavoriteToolbox.forTesting(
      resolveImage: (_) => GeneratedImage(
        id: 'outside',
        bytes: Uint8List.fromList(const [1, 2, 3]),
        width: 1,
        height: 1,
      ),
      saveToGallery: (_) async => fail('must not save to unfavorite'),
      readFavorite: (_) async => fail('must not read local gallery'),
      writeFavorite: (_, __) async => fail('must not mutate local gallery'),
    );

    final result = await toolbox.tools().single.execute('outside', {
      'resource_ref': _ref('outside'),
      'favorite': false,
    });

    expect(result.isError, isFalse);
    expect(result.details['favorite'], isFalse);
  });

  test(
    'rechecks generation history after asynchronous record lookup',
    () async {
      final image = _image('race', imageFile.path);
      final read = Completer<LocalGalleryFavoriteRecord?>();
      var available = true;
      final toolbox = GenerationImageFavoriteToolbox.forTesting(
        resolveImage: (_) => available ? image : null,
        readFavorite: (_) => read.future,
        writeFavorite: (_, __) async => fail('must not mutate stale resource'),
      );

      final pending = toolbox.tools().single.execute('race', {
        'resource_ref': _ref('race'),
        'favorite': true,
      });
      available = false;
      read.complete(const LocalGalleryFavoriteRecord(id: 9, favorite: false));

      final result = await pending;
      expect(result.details['code'], 'stale_image_resource');
    },
  );
}

GeneratedImage _image(
  String id,
  String path, {
  GeneratedImageKind kind = GeneratedImageKind.completed,
}) => GeneratedImage(
  id: id,
  bytes: Uint8List.fromList(const [1, 2, 3]),
  width: 1,
  height: 1,
  filePath: path,
  kind: kind,
);

Map<String, Object> _ref(String id) =>
    AgentChatResourceReferenceCodec.encodeJsonMap(
      AgentChatResourceReference(
        kind: AgentChatResourceKind.generatedImage,
        source: 'generation_history',
        resourceId: id,
      ),
    );
