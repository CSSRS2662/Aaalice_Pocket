// Builds assets/zh_lexicon/pocket_lexicon.json.gz from the reviewed
// pocket_translations.json: Chinese names this project wrote for catalog tags
// that no bundled or installable source translates. Offline and deterministic.
//
//   dart run tool/zh_lexicon/build_pocket_lexicon.dart
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _sourcePath = 'tool/zh_lexicon/pocket_translations.json';
const _catalogPath = 'assets/databases/tag_catalog.db';
const _amePath = 'assets/zh_lexicon/ame_lexicon.json.gz';
const _outputPath = 'assets/zh_lexicon/pocket_lexicon.json.gz';
const _manifestPath = 'assets/zh_lexicon/pocket_manifest.json';

final _hanzi = RegExp(r'[㐀-鿿]');

Future<void> main() async {
  sqfliteFfiInit();
  final sourceBytes = File(_sourcePath).readAsBytesSync();
  final entries =
      ((jsonDecode(utf8.decode(sourceBytes)) as Map)['entries'] as List)
          .cast<Map>();

  final catalog = await databaseFactoryFfi.openDatabase(
    File(_catalogPath).absolute.path,
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );
  final records = <String, (int, int)>{
    for (final row in await catalog.rawQuery(
      'SELECT name, category, post_count FROM tags',
    ))
      (row['name'] as String).toLowerCase(): (
        row['category'] as int,
        row['post_count'] as int,
      ),
  };
  final bundled = {
    for (final row in await catalog.rawQuery('SELECT tag FROM zh_translations'))
      (row['tag'] as String).toLowerCase(),
  };
  await catalog.close();
  final ame = {
    for (final row
        in ((jsonDecode(
                      utf8.decode(
                        gzip.decode(File(_amePath).readAsBytesSync()),
                      ),
                    )
                    as Map)['entries']
                as List)
            .cast<List>())
      if ((row[3] as String).isNotEmpty || (row[4] as List).isNotEmpty)
        (row[0] as String).toLowerCase(),
  };

  final problems = <String>[];
  final seen = <String>{};
  final rows = <List<Object>>[];
  for (final entry in entries) {
    final tag = (entry['tag'] as String).trim().toLowerCase();
    final zh = (entry['zh'] as String).trim();
    final record = records[tag];
    if (record == null) {
      problems.add('$tag: not in the catalog');
    } else if (!seen.add(tag)) {
      problems.add('$tag: listed twice');
    } else if (zh.isEmpty) {
      problems.add('$tag: empty name');
    } else if (bundled.contains(tag) || ame.contains(tag)) {
      problems.add('$tag: already translated by a bundled source');
    }
    if (record == null) continue;
    // Like the AME rows: only Chinese aliases help a Chinese lookup.
    final aliases = <String>{
      for (final alias
          in (entry['aliases'] as List? ?? const []).cast<String>())
        if (alias.trim() != zh && _hanzi.hasMatch(alias)) alias.trim(),
    }.toList();
    rows.add([tag, record.$1, record.$2, zh, aliases]);
  }
  if (problems.isNotEmpty) {
    stderr.writeln(problems.join('\n'));
    exit(1);
  }
  rows.sort((a, b) => (a[0] as String).compareTo(b[0] as String));

  final json = jsonEncode({'version': 1, 'entries': rows});
  final output = GZipCodec(level: 9).encode(utf8.encode(json));
  File(_outputPath).writeAsBytesSync(output);
  final catalogDigest = sha256.convert(File(_catalogPath).readAsBytesSync());
  final manifest = {
    'source': {
      'name': 'Aaalice Pocket translations',
      'path': _sourcePath,
      'license': 'MIT',
      'sha256': sha256.convert(sourceBytes).toString(),
    },
    'catalog_sha256': catalogDigest.toString(),
    'format': '[tag, catalog_category, post_count, zh_label, [cjk_aliases]]',
    'entries': rows.length,
    'file': {
      'name': 'pocket_lexicon.json.gz',
      'bytes': output.length,
      'sha256': sha256.convert(output).toString(),
    },
  };
  File(_manifestPath).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );
  stdout.writeln('Wrote ${rows.length} entries (${output.length} bytes)');
}
