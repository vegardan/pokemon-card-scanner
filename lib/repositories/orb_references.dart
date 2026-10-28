import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../vision/card_constants.dart';

class OrbReferences {
  final String indexPath;
  final List<String> ids;
  final int shardSize;
  static const assetRoot = 'assets/data/orb_references';
  static const _indexChunkBytes = 1024 * 1024;
  static Future<OrbReferences>? _loading;

  OrbReferences._(this.indexPath, this.ids, this.shardSize);

  static Future<Uint8List> loadBack() async {
    final data = await rootBundle.load('$assetRoot/back.json.gz');

    if (data.lengthInBytes > 128 * 1024) {
      throw const FormatException('Oversized back reference');
    }

    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static Future<OrbReferences> load() async {
    try {
      final store = await (_loading ??= _load());

      if (!await File(store.indexPath).exists()) {
        return await (_loading = _load());
      }

      return store;
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  static Future<OrbReferences> _load() async {
    final manifest = jsonDecode(await rootBundle.loadString('$assetRoot/manifest.json')) as Map<String, dynamic>;

    if (manifest['features_per_card'] != CardConstants.featuresPerCard || manifest['shard_size'] != CardConstants.shardSize) {
      throw const FormatException('Unsupported ORB references');
    }

    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/orb-${manifest['index_id']}.bin';
    final file = File(path);
    final expected = manifest['index_bytes'] as int;
    final chunks = manifest['index_chunks'] as int;
    final ids = manifest['ids'] as List;

    if (expected != ids.length * CardConstants.featuresPerCard * CardConstants.descriptorSize || expected <= 0 || chunks != (expected / _indexChunkBytes).ceil()) {
      throw const FormatException('Invalid index size or chunk count');
    }

    if (!await file.exists() || await file.length() != expected) {
      // use .tmp so the index is replaced only after writing and validating it
      final temporary = File('$path.tmp');
      final destination = await temporary.open(mode: FileMode.write);

      try {
        for (var i = 0; i < chunks; i++) {
          final data = await rootBundle.load('$assetRoot/retrieval_${i.toString().padLeft(3, '0')}.bin');

          if (data.lengthInBytes > _indexChunkBytes) {
            throw const FormatException('Oversized index chunk');
          }

          await destination.writeFrom(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        }

        await destination.flush();
      } finally {
        await destination.close();
      }

      if (await temporary.length() != expected) {
        await temporary.delete();
        throw const FormatException('Incomplete retrieval index');
      }

      if (await file.exists()) await file.delete();

      await temporary.rename(path);
    }

    return OrbReferences._(path, List<String>.from(ids), CardConstants.shardSize);
  }

  Future<List<Uint8List>> loadCandidates(List<int> candidates) async {
    if (candidates.length > CardConstants.candidateLimit || candidates.any((i) => i < 0 || i >= ids.length)) {
      throw const FormatException('Invalid candidate shortlist');
    }

    final result = <Uint8List>[];

    for (final shard in candidates.map((i) => (i / shardSize).toInt()).toSet()) {
      final data = await rootBundle.load('$assetRoot/${shard.toString().padLeft(5, '0')}.json.gz');

      if (data.lengthInBytes > 512 * 1024) {
        throw const FormatException('Reference shard exceeds memory budget');
      }

      result.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    }

    return result;
  }
}
