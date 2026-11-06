import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pokemon_card_scanner/centering/centering_check.dart';
import 'package:pokemon_card_scanner/models/analysis/estimated_grade.dart';
import 'package:pokemon_card_scanner/models/crease_analysis.dart';
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
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE scanned_cards (
            scan_id INTEGER PRIMARY KEY AUTOINCREMENT,
            card_id TEXT NOT NULL,
            front_image_path TEXT,
            back_image_path TEXT,
            created_at_ms INTEGER NOT NULL,
            estimated_grade INTEGER,
            grade_report_json TEXT,
            back_crease_analysis TEXT
          )
        ''');
        await CenteringTable.create(db);
      },
      onUpgrade: (db, oldVersion, newVersion) => upgradeSchema(db),
    );
  }

  static Future<void> upgradeSchema(DatabaseExecutor db) async {
    final columns = await db.rawQuery('PRAGMA table_info(scanned_cards)');
    final columnNames = columns.map((c) => c['name'] as String).toSet();

    if (!columnNames.contains('estimated_grade')) {
      await db.execute('ALTER TABLE scanned_cards ADD COLUMN estimated_grade INTEGER');
    }
    if (!columnNames.contains('grade_report_json')) {
      await db.execute('ALTER TABLE scanned_cards ADD COLUMN grade_report_json TEXT');
    }
    if (!columnNames.contains('back_crease_analysis')) {
      await db.execute('ALTER TABLE scanned_cards ADD COLUMN back_crease_analysis TEXT');
    }

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'card_centering'",
    );
    if (tables.isEmpty) {
      await CenteringTable.create(db);
    }
  }

  Future<ScannedPokemonCard> save(
    JpegData frontPhoto,
    JpegData backPhoto,
    CatalogPokemonCard catalogCard, {
    EstimatedGrade? estimatedGrade,
    CenteringResult? frontCentering,
    CenteringResult? backCentering,
    CreaseAnalysis backCreases = CreaseAnalysis.unavailable,
    JpegData? annotatedFrontCorners,
    JpegData? annotatedBackCorners,
  }) async {
    final db = await _database;
    final createdAt = DateTime.now();

    final savedScan = await db.transaction((transaction) async {
      final scanId = await transaction.insert('scanned_cards', {
        'created_at_ms': createdAt.millisecondsSinceEpoch,
        'card_id': catalogCard.id,
        'estimated_grade': estimatedGrade?.overallScore,
        'back_crease_analysis': jsonEncode(backCreases.toJson()),
      });

      await CenteringTable.save(transaction, scanId, 'front', frontCentering);
      await CenteringTable.save(transaction, scanId, 'back', backCentering);

      final frontImagePath = await _writeCapturedImage(scanId, 'front', frontPhoto);
      final backImagePath = await _writeCapturedImage(scanId, 'back', backPhoto);

      String? frontCornersPath;
      String? backCornersPath;
      if (annotatedFrontCorners != null) {
        frontCornersPath = await _writeCapturedImage(scanId, 'corners-front', annotatedFrontCorners);
      }
      if (annotatedBackCorners != null) {
        backCornersPath = await _writeCapturedImage(scanId, 'corners-back', annotatedBackCorners);
      }

      var finalGrade = estimatedGrade;
      if (finalGrade != null && (frontCornersPath != null || backCornersPath != null)) {
        final updatedSubGrades = finalGrade.subGrades.map((sub) {
          if (sub.category == 'Corners') {
            final details = Map<String, dynamic>.from(sub.details ?? {});
            if (frontCornersPath != null) details['frontAnnotatedPath'] = frontCornersPath;
            if (backCornersPath != null) details['backAnnotatedPath'] = backCornersPath;
            return SubGrade(
              category: sub.category,
              score: sub.score,
              description: sub.description,
              details: details,
            );
          }
          return sub;
        }).toList();

        finalGrade = EstimatedGrade(
          overallScore: finalGrade.overallScore,
          strategyName: finalGrade.strategyName,
          subGrades: updatedSubGrades,
          notes: finalGrade.notes,
        );
      }

      final gradeReportJson = finalGrade != null ? jsonEncode(finalGrade.toJson()) : null;

      await transaction.update(
        'scanned_cards',
        {
          'front_image_path': frontImagePath,
          'back_image_path': backImagePath,
          'grade_report_json': gradeReportJson,
        },
        where: 'scan_id = ?',
        whereArgs: [scanId],
      );

      return (
        scanId: scanId,
        frontImagePath: frontImagePath,
        backImagePath: backImagePath,
        finalGrade: finalGrade,
      );
    });

    return ScannedPokemonCard(
      scanId: savedScan.scanId,
      catalogCard: catalogCard,
      frontCentering: frontCentering,
      backCentering: backCentering,
      estimatedGrading: savedScan.finalGrade?.overallScore,
      gradeReport: savedScan.finalGrade,
      frontImagePath: savedScan.frontImagePath,
      backImagePath: savedScan.backImagePath,
      createdAt: createdAt,
      backCreases: backCreases,
    );
  }

  Future<List<ScannedPokemonCard>> loadAll() async {
    final db = await _database;
    final rows = await db.query('scanned_cards', orderBy: 'created_at_ms DESC');
    final centering = await CenteringTable.loadAll(db);
    final cards = <ScannedPokemonCard>[];

    for (final row in rows) {
      final catalogCard = await PokemonCardCatalog.findById(row['card_id'] as String);

      if (catalogCard == null) continue;

      final gradeScore = row['estimated_grade'] as int?;
      final reportJsonStr = row['grade_report_json'] as String?;
      EstimatedGrade? gradeReport;

      if (reportJsonStr != null && reportJsonStr.isNotEmpty) {
        try {
          gradeReport = EstimatedGrade.fromJson(jsonDecode(reportJsonStr) as Map<String, dynamic>);
        } catch (_) {
          // Ignore corrupted JSON
        }
      }

      cards.add(
        ScannedPokemonCard(
          scanId: row['scan_id']! as int,
          catalogCard: catalogCard,
          frontCentering: centering[(row['scan_id'] as int, 'front')],
          backCentering: centering[(row['scan_id'] as int, 'back')],
          estimatedGrading: gradeScore ?? gradeReport?.overallScore,
          gradeReport: gradeReport,
          frontImagePath: row['front_image_path'] as String,
          backImagePath: row['back_image_path'] as String,
          createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at_ms']! as int),
          backCreases: CreaseAnalysis.decode(row['back_crease_analysis'] as String?),
        ),
      );
    }

    return cards;
  }

  Future<void> delete(ScannedPokemonCard card) async {
    final db = await _database;
    await db.delete('scanned_cards', where: 'scan_id = ?', whereArgs: [card.scanId]);

    final cornerDetails = card.gradeReport?.subGrades
        .where((s) => s.category == 'Corners')
        .firstOrNull
        ?.details;
    final extraPaths = [
      cornerDetails?['frontAnnotatedPath'] as String?,
      cornerDetails?['backAnnotatedPath'] as String?,
    ];

    for (final imagePath in [card.frontImagePath, card.backImagePath, ...extraPaths]) {
      if (imagePath == null) continue;
      final imageFile = File(imagePath);

      if (await imageFile.exists()) {
        await imageFile.delete();
      }
    }
  }

  Future<String> _writeCapturedImage(int scanId, String side, JpegData image) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final scansDirectory = Directory(join(documentsDirectory.path, 'scanned_cards'));

    if (!await scansDirectory.exists()) {
      await scansDirectory.create(recursive: true);
    }

    final imagePath = join(scansDirectory.path, '$scanId-$side.jpg');
    await File(imagePath).writeAsBytes(image.bytes, flush: true);
    return imagePath;
  }
}
