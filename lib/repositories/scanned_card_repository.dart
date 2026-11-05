import 'dart:io';
import 'dart:convert';
import 'package:pokemon_card_scanner/models/crease_analysis.dart';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pokemon_card_scanner/centering/centering_check.dart';
import 'package:pokemon_card_scanner/models/jpeg_data.dart';
import 'package:pokemon_card_scanner/models/pokemon_card.dart';
import 'package:pokemon_card_scanner/repositories/centering_table.dart';
import 'package:pokemon_card_scanner/repositories/pokemon_card_catalog.dart';
import 'package:sqflite/sqflite.dart';

class ScannedCardRepository {
  static final instance = ScannedCardRepository._();
  late final Future<Database> _database = _openDatabase();

  ScannedCardRepository._();

  Future<Database> _openDatabase() async {
    final databasePath = await getDatabasesPath();
    return openDatabase(
      join(databasePath, 'pokemon_card_scanner.db'),
      version: 3,
      onUpgrade: (db, oldVersion, newVersion) => upgradeSchema(db),
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE scanned_cards (
            scan_id INTEGER PRIMARY KEY AUTOINCREMENT,
            card_id TEXT NOT NULL,
            front_image_path TEXT,
            back_image_path TEXT,
            created_at_ms INTEGER NOT NULL,
            back_crease_analysis TEXT
          )
        ''');
        await CenteringTable.create(db);
      },
    );
  }

  /// Upgrade both legacy/centering v1 and crease-only v2 without replacing data.
  static Future<void> upgradeSchema(DatabaseExecutor db) async {
    final columns = await db.rawQuery('PRAGMA table_info(scanned_cards)');
    if (!columns.any((column) => column['name'] == 'back_crease_analysis')) {
      await db.execute(
        'ALTER TABLE scanned_cards ADD COLUMN back_crease_analysis TEXT',
      );
    }
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'card_centering'",
    );
    if (tables.isEmpty) await CenteringTable.create(db);
  }

  Future<ScannedPokemonCard> save(
    JpegData frontPhoto,
    JpegData backPhoto,
    CatalogPokemonCard catalogCard, {
    CenteringResult? frontCentering,
    CenteringResult? backCentering,
    CreaseAnalysis backCreases = CreaseAnalysis.unavailable,
  }) async {
    final db = await _database;
    final createdAt = DateTime.now();

    final savedScan = await db.transaction((transaction) async {
      final scanId = await transaction.insert('scanned_cards', {
        'created_at_ms': createdAt.millisecondsSinceEpoch,
        'card_id': catalogCard.id,
        'back_crease_analysis': jsonEncode(backCreases.toJson()),
      });
      await CenteringTable.save(transaction, scanId, 'front', frontCentering);
      await CenteringTable.save(transaction, scanId, 'back', backCentering);
      final frontImagePath = await _writeCapturedImage(
        scanId,
        'front',
        frontPhoto,
      );
      final backImagePath = await _writeCapturedImage(
        scanId,
        'back',
        backPhoto,
      );
      await transaction.update(
        'scanned_cards',
        {'front_image_path': frontImagePath, 'back_image_path': backImagePath},
        where: 'scan_id = ?',
        whereArgs: [scanId],
      );

      return (
        scanId: scanId,
        frontImagePath: frontImagePath,
        backImagePath: backImagePath,
      );
    });

    return ScannedPokemonCard(
      scanId: savedScan.scanId,
      catalogCard: catalogCard,
      estimatedGrading: null,
      frontImagePath: savedScan.frontImagePath,
      backImagePath: savedScan.backImagePath,
      createdAt: createdAt,
      frontCentering: frontCentering,
      backCentering: backCentering,
      backCreases: backCreases,
    );
  }

  Future<List<ScannedPokemonCard>> loadAll() async {
    final db = await _database;
    final rows = await db.query('scanned_cards', orderBy: 'created_at_ms DESC');
    final centering = await CenteringTable.loadAll(db);
    final cards = <ScannedPokemonCard>[];

    for (final row in rows) {
      final catalogCard = await PokemonCardCatalog.findById(
        row['card_id'] as String,
      );

      // A scan can only be displayed when its card exists in the catalog.
      if (catalogCard == null) continue;

      cards.add(
        ScannedPokemonCard(
          scanId: row['scan_id']! as int,
          backCreases: CreaseAnalysis.decode(
            row['back_crease_analysis'] as String?,
          ),
          frontCentering: centering[(row['scan_id'] as int, 'front')],
          backCentering: centering[(row['scan_id'] as int, 'back')],
          catalogCard: catalogCard,
          estimatedGrading: null,
          frontImagePath: row['front_image_path'] as String,
          backImagePath: row['back_image_path'] as String,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            row['created_at_ms']! as int,
          ),
        ),
      );
    }

    return cards;
  }

  Future<void> delete(ScannedPokemonCard card) async {
    final db = await _database;
    await db.delete(
      'scanned_cards',
      where: 'scan_id = ?',
      whereArgs: [card.scanId],
    );

    for (final imagePath in [card.frontImagePath, card.backImagePath]) {
      final imageFile = File(imagePath);

      if (await imageFile.exists()) {
        await imageFile.delete();
      }
    }
  }

  Future<String> _writeCapturedImage(
    int scanId,
    String side,
    JpegData image,
  ) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final scansDirectory = Directory(
      join(documentsDirectory.path, 'scanned_cards'),
    );

    if (!await scansDirectory.exists()) {
      await scansDirectory.create(recursive: true);
    }

    final imagePath = join(scansDirectory.path, '$scanId-$side.jpg');
    await File(imagePath).writeAsBytes(image.bytes, flush: true);
    return imagePath;
  }
}
