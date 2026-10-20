// Adds this project's Chinese names (assets/zh_lexicon/pocket_lexicon.json.gz)
// as extra views of their tags in the bundled E5 pack, so Chinese queries
// reach tags whose only document was their English name.
//
// Encodes with the bundled model through the app's own tokenizer and checks
// first that it reproduces the stored vectors. Re-running replaces the
// views it added before. Windows only (loads the onnxruntime plugin DLL):
//
//   pwsh -File scripts/run_flutter_tests.ps1 -Path tool/semantic_search/append_pocket_views_test.dart
@Timeout(Duration(minutes: 9))
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/e5_tokenizer.dart';
import 'package:onnxruntime_v2/onnxruntime_v2.dart';

const _pack = 'assets/semantic_search';
const _lexicon = 'assets/zh_lexicon/pocket_lexicon.json.gz';
const _dimension = 384;
const _generated = ['vectors.i8', 'scales.f32', 'tags.json'];

String _onnxLibrary() {
  final config =
      jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
          as Map;
  final package = (config['packages'] as List).cast<Map>().firstWhere(
    (entry) => entry['name'] == 'onnxruntime_v2',
  );
  return '${Uri.parse(package['rootUri'] as String).toFilePath()}/windows/onnxruntime.dll';
}

Map<String, Object> _fileEntry(List<int> bytes) => {
  'sha256': sha256.convert(bytes).toString(),
  'bytes': bytes.length,
};

/// numpy.rint: halves go to the even neighbour.
int _rint(double value) {
  final floor = value.floorToDouble();
  final diff = value - floor;
  if (diff > 0.5) return floor.toInt() + 1;
  if (diff < 0.5) return floor.toInt();
  return floor.toInt().isEven ? floor.toInt() : floor.toInt() + 1;
}

class _Pack {
  _Pack(this.tags, this.values, this.scales);

  /// `[tag, post count, label, view count]` rows.
  final List<List<Object?>> tags;
  final List<Int8List> values;
  final List<double> scales;

  List<int> encodeTags() => utf8.encode(jsonEncode(tags));

  List<int> encodeValues() {
    final out = BytesBuilder(copy: false);
    for (final row in values) {
      out.add(row.buffer.asUint8List(row.offsetInBytes, row.lengthInBytes));
    }
    return out.takeBytes();
  }

  List<int> encodeScales() {
    final data = ByteData(scales.length * 4);
    for (var i = 0; i < scales.length; i++) {
      data.setFloat32(i * 4, scales[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }

  int rowOf(int tag) {
    var row = 0;
    for (var i = 0; i < tag; i++) {
      row += tags[i][3] as int;
    }
    return row;
  }
}

void main() {
  test('append pocket views to the E5 pack', () async {
    DynamicLibrary.open(_onnxLibrary());
    final manifestFile = File('$_pack/manifest.json');
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    final tags =
        (jsonDecode(File('$_pack/tags.json').readAsStringSync()) as List)
            .cast<List>()
            .map((row) => List<Object?>.of(row))
            .toList();
    final valueBytes = File('$_pack/vectors.i8').readAsBytesSync();
    final scaleData = ByteData.sublistView(
      File('$_pack/scales.f32').readAsBytesSync(),
    );
    final scales = [
      for (var i = 0; i < scaleData.lengthInBytes ~/ 4; i++)
        scaleData.getFloat32(i * 4, Endian.little),
    ];
    final values = [
      for (var i = 0; i < scales.length; i++)
        Int8List.sublistView(valueBytes, i * _dimension, (i + 1) * _dimension),
    ];
    var pack = _Pack(tags, values, scales);
    expect(values.length, manifest['views']);
    // ignore: avoid_print
    print(
      'tags.json re-encodes byte for byte: '
      '${sha256.convert(pack.encodeTags()) == sha256.convert(File('$_pack/tags.json').readAsBytesSync())}',
    );

    // Strip the views a previous run added, back to the reviewed pack.
    final previous = manifest['pocket'] as Map<String, dynamic>?;
    if (previous != null) {
      final added = (previous['tags'] as Map).cast<String, int>();
      final labels = (previous['labels'] as Map).cast<String, String>();
      final keptValues = <Int8List>[];
      final keptScales = <double>[];
      var row = 0;
      for (final tag in pack.tags) {
        final name = tag[0] as String;
        final count = tag[3] as int;
        final drop = added[name] ?? 0;
        for (var view = 0; view < count; view++, row++) {
          if (view >= count - drop) continue;
          keptValues.add(pack.values[row]);
          keptScales.add(pack.scales[row]);
        }
        if (drop > 0) {
          tag[3] = count - drop;
          tag[2] = labels[name] ?? '';
        }
      }
      pack = _Pack(pack.tags, keptValues, keptScales);
      final base = (previous['base'] as Map)['files'] as Map;
      expect(_fileEntry(pack.encodeTags()), base['tags.json']);
      expect(_fileEntry(pack.encodeValues()), base['vectors.i8']);
      expect(_fileEntry(pack.encodeScales()), base['scales.f32']);
    }
    final baseFiles = {
      'tags.json': _fileEntry(pack.encodeTags()),
      'vectors.i8': _fileEntry(pack.encodeValues()),
      'scales.f32': _fileEntry(pack.encodeScales()),
    };
    final baseViews = pack.values.length;

    final tokenizer = E5Tokenizer(
      File('$_pack/tokenizer.json').readAsStringSync(),
    );
    final options = OrtSessionOptions()..setIntraOpNumThreads(4);
    final session = OrtSession.fromBuffer(
      File('$_pack/model.onnx').readAsBytesSync(),
      options,
    );
    Float32List embed(String passage) {
      final ids = tokenizer.encodePassage(passage);
      final inputs = {
        'token_type_ids': OrtValueTensor.createTensorWithDataList(
          Int64List(ids.length),
          [1, ids.length],
        ),
        'input_ids': OrtValueTensor.createTensorWithDataList(
          Int64List.fromList(ids),
          [1, ids.length],
        ),
        'attention_mask': OrtValueTensor.createTensorWithDataList(
          Int64List.fromList(List.filled(ids.length, 1)),
          [1, ids.length],
        ),
      };
      final runOptions = OrtRunOptions();
      final outputs = session.run(runOptions, inputs);
      final pooled = Float32List(_dimension);
      final hidden = (outputs.first!.value as List).first as List;
      for (final token in hidden) {
        final row = token as List;
        for (var d = 0; d < _dimension; d++) {
          pooled[d] += (row[d] as num).toDouble() / ids.length;
        }
      }
      for (final output in outputs) {
        output?.release();
      }
      for (final input in inputs.values) {
        input.release();
      }
      runOptions.release();
      var norm = 0.0;
      for (final value in pooled) {
        norm += value * value;
      }
      norm = math.sqrt(norm);
      for (var d = 0; d < _dimension; d++) {
        pooled[d] /= norm;
      }
      return pooled;
    }

    // The base view of a tag is "tag; label": re-encoding it must give back
    // the stored row, or the new rows would not be comparable. The pack was
    // encoded by onnxruntime in Python, in padded batches; the app's runtime
    // lands about 0.997 cosine from it for every text, with no score bias
    // against queries (median +0.0007 over 60 labelled tags).
    final random = math.Random(20261020);
    var worst = 1.0;
    var total = 0.0;
    for (var i = 0; i < 64; i++) {
      final tag = random.nextInt(pack.tags.length);
      final name = pack.tags[tag][0] as String;
      final label = pack.tags[tag][2] as String;
      final stored = pack.values[pack.rowOf(tag)];
      final vector = embed(label.isEmpty ? name : '$name; $label');
      var dot = 0.0;
      var norm = 0.0;
      for (var d = 0; d < _dimension; d++) {
        dot += vector[d] * stored[d];
        norm += stored[d] * stored[d];
      }
      worst = math.min(worst, dot / math.sqrt(norm));
      total += dot / math.sqrt(norm);
    }
    // ignore: avoid_print
    print(
      'reproduction cosine over 64 base views: worst $worst, '
      'mean ${total / 64}',
    );
    expect(worst, greaterThan(0.99));
    expect(total / 64, greaterThan(0.995));

    final lexiconBytes = File(_lexicon).readAsBytesSync();
    final rows =
        ((jsonDecode(utf8.decode(gzip.decode(lexiconBytes))) as Map)['entries']
                as List)
            .cast<List>();
    final position = {
      for (var i = 0; i < pack.tags.length; i++) pack.tags[i][0] as String: i,
    };
    final extra = <int, List<String>>{};
    for (final row in rows) {
      final tag = position[row[0] as String];
      if (tag == null) continue;
      final name = pack.tags[tag][0] as String;
      final label = pack.tags[tag][2] as String;
      final seen = {label.isEmpty ? name : '$name; $label'};
      final aliases = (row[4] as List).cast<String>();
      for (final text in [row[3] as String, aliases.join(', ')]) {
        if (text.trim().isNotEmpty && seen.add(text.trim())) {
          (extra[tag] ??= []).add(text.trim());
        }
      }
    }

    final addedCounts = <String, int>{};
    final originalLabels = <String, String>{};
    final newValues = <Int8List>[];
    final newScales = <double>[];
    var row = 0;
    for (var tag = 0; tag < pack.tags.length; tag++) {
      final count = pack.tags[tag][3] as int;
      for (var view = 0; view < count; view++, row++) {
        newValues.add(pack.values[row]);
        newScales.add(pack.scales[row]);
      }
      final texts = extra[tag];
      if (texts == null) continue;
      final name = pack.tags[tag][0] as String;
      for (final text in texts) {
        final vector = embed(text);
        var peak = 0.0;
        for (final value in vector) {
          peak = math.max(peak, value.abs());
        }
        final scale = Float32List.fromList([peak / 127.0])[0];
        newValues.add(
          Int8List.fromList([
            for (final value in vector) _rint(value / scale).clamp(-127, 127),
          ]),
        );
        newScales.add(scale);
      }
      addedCounts[name] = texts.length;
      originalLabels[name] = pack.tags[tag][2] as String;
      pack.tags[tag][3] = count + texts.length;
      final pocketLabel = rows.firstWhere((entry) => entry[0] == name)[3];
      if ((pack.tags[tag][2] as String).isEmpty) {
        pack.tags[tag][2] = pocketLabel;
      }
    }
    pack = _Pack(pack.tags, newValues, newScales);
    final outputs = {
      'tags.json': pack.encodeTags(),
      'vectors.i8': pack.encodeValues(),
      'scales.f32': pack.encodeScales(),
    };
    for (final name in _generated) {
      File('$_pack/$name').writeAsBytesSync(outputs[name]!);
    }
    manifest['views'] = pack.values.length;
    manifest['document'] =
        'view 1: canonical tag; existing zh_cn. Extra views: AME zh name, zh '
        'aliases, note; Aaalice Pocket zh name and aliases';
    final files = manifest['files'] as Map<String, dynamic>;
    for (final name in _generated) {
      files[name] = _fileEntry(outputs[name]!);
    }
    manifest['pocket'] = {
      'lexicon_sha256': sha256.convert(lexiconBytes).toString(),
      'tags': addedCounts,
      'labels': originalLabels,
      'base': {'views': baseViews, 'files': baseFiles},
    };
    manifestFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    );
    // ignore: avoid_print
    print(
      'Added ${pack.values.length - baseViews} views for '
      '${addedCounts.length} tags',
    );
    options.release();
    session.release();
  });
}
