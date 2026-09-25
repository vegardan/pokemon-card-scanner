import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pokemon_card_scanner/models/pokemon_card.dart';
import 'package:sqflite/sqflite.dart';

class ScannedCardRepository {
  static final instance = ScannedCardRepository._();

  late final Future<Database> _database = _openDatabase();

  ScannedCardRepository._();

  Future<Database> _openDatabase() async {
    final databasePath = await getDatabasesPath();
    return openDatabase(
      join(databasePath, 'pokemon_card_scanner.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE scanned_cards (
            scan_id INTEGER PRIMARY KEY AUTOINCREMENT,
            front_image_path TEXT,
            back_image_path TEXT,
            created_at_ms INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  Future<ScannedPokemonCard> saveCapturedScan({required Uint8List frontPhotoBytes, required Uint8List backPhotoBytes}) async {
    final db = await _database;
    final createdAt = DateTime.now();

    final savedScan = await db.transaction((transaction) async {
      final scanId = await transaction.insert('scanned_cards', {'created_at_ms': createdAt.millisecondsSinceEpoch});
      final frontImagePath = await _writeCapturedImage(scanId, 'front', frontPhotoBytes);
      final backImagePath = await _writeCapturedImage(scanId, 'back', backPhotoBytes);
      await transaction.update('scanned_cards', {'front_image_path': frontImagePath, 'back_image_path': backImagePath}, where: 'scan_id = ?', whereArgs: [scanId]);

      return (scanId: scanId, frontImagePath: frontImagePath, backImagePath: backImagePath);
    });

    final imagePaths = [savedScan.frontImagePath, savedScan.backImagePath];

    return ScannedPokemonCard(
      scanId: savedScan.scanId,
      catalogCard: null,
      estimatedGrading: null,
      capturedImagePaths: imagePaths,
      capturedImages: imagePaths.map((path) => FileImage(File(path))).toList(),
      createdAt: createdAt,
    );
  }

  Future<List<ScannedPokemonCard>> loadAll() async {
    final db = await _database;
    final rows = await db.query('scanned_cards', orderBy: 'created_at_ms DESC');

    return rows.map((row) {
      final paths = [row['front_image_path'] as String?, row['back_image_path'] as String?].whereType<String>().toList();
      return ScannedPokemonCard(
        scanId: row['scan_id']! as int,
        catalogCard: null,
        estimatedGrading: null,
        capturedImagePaths: paths,
        capturedImages: paths.map((path) => FileImage(File(path))).toList(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at_ms']! as int),
      );
    }).toList();
  }

  Future<String> _writeCapturedImage(int scanId, String side, Uint8List bytes) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final scansDirectory = Directory(join(documentsDirectory.path, 'scanned_cards'));
    if (!await scansDirectory.exists()) {
      await scansDirectory.create(recursive: true);
    }

    final imagePath = join(scansDirectory.path, '$scanId-$side.jpg');
    await File(imagePath).writeAsBytes(bytes, flush: true);
    return imagePath;
  }
}
