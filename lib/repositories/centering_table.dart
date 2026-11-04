import 'dart:typed_data';

import 'package:pokemon_card_scanner/centering/centering_check.dart';
import 'package:sqflite/sqflite.dart';

class CenteringTable {
  CenteringTable._();

  static Future<void> create(DatabaseExecutor db) => db.execute('''
    CREATE TABLE card_centering (
      scan_id INTEGER NOT NULL REFERENCES scanned_cards(scan_id) ON DELETE CASCADE,
      side TEXT NOT NULL CHECK (side IN ('front', 'back')),
      left_mm REAL NOT NULL,
      right_mm REAL NOT NULL,
      top_mm REAL NOT NULL,
      bottom_mm REAL NOT NULL,
      analysis_image BLOB NOT NULL,
      PRIMARY KEY (scan_id, side)
    )
  ''');

  static Future<void> save(DatabaseExecutor db, int scanId, String side, CenteringResult? result) async {
    if (result == null) return;
    await db.insert('card_centering', {
      'scan_id': scanId,
      'side': side,
      'left_mm': result.leftMm,
      'right_mm': result.rightMm,
      'top_mm': result.topMm,
      'bottom_mm': result.bottomMm,
      'analysis_image': result.analysisImage,
    });
  }

  static CenteringResult _read(Map<String, Object?> row) => CenteringResult(
    (row['left_mm'] as num).toDouble(),
    (row['right_mm'] as num).toDouble(),
    (row['top_mm'] as num).toDouble(),
    (row['bottom_mm'] as num).toDouble(),
    row['analysis_image'] as Uint8List,
  );

  static Future<Map<(int, String), CenteringResult>> loadAll(DatabaseExecutor db) async {
    final rows = await db.query('card_centering');
    return {for (final row in rows) (row['scan_id'] as int, row['side'] as String): _read(row)};
  }
}
