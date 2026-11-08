import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_card_scanner/repositories/scanned_card_repository.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  for (final state in [
    (false, false),
    (false, true),
    (true, false),
    (true, true),
  ]) {
    test(
      'upgrade preserves existing tables: crease=${state.$1}, centering=${state.$2}',
      () async {
        final db = _SchemaDatabase(state.$1, state.$2);
        await ScannedCardRepository.upgradeSchema(db);
        expect(db.estimatedGrade, isTrue);
        expect(db.gradeReport, isTrue);
        expect(db.crease, isTrue);
        expect(db.centering, isTrue);
        expect(db.executed.length, 2 + (state.$1 ? 0 : 1) + (state.$2 ? 0 : 1));
        final count = db.executed.length;
        await ScannedCardRepository.upgradeSchema(db);
        expect(db.executed.length, count);
        expect(
          db.executed.any(
            (sql) => RegExp(r'^\s*(DROP|DELETE|REPLACE)\b').hasMatch(sql),
          ),
          isFalse,
        );
      },
    );
  }
}

class _SchemaDatabase implements DatabaseExecutor {
  bool estimatedGrade = false;
  bool gradeReport = false;
  bool crease, centering;
  final executed = <String>[];
  _SchemaDatabase(this.crease, this.centering);

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    if (sql == 'PRAGMA table_info(scanned_cards)') {
      return [
        if (estimatedGrade) {'name': 'estimated_grade'},
        if (gradeReport) {'name': 'grade_report_json'},
        if (crease) {'name': 'back_crease_analysis'},
      ];
    }
    if (sql.contains('sqlite_master')) {
      return [
        if (centering) {'name': 'card_centering'},
      ];
    }
    throw StateError('Unexpected query: $sql');
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    executed.add(sql);
    if (sql.startsWith('ALTER TABLE scanned_cards ADD COLUMN estimated_grade')) {
      expect(estimatedGrade, isFalse);
      estimatedGrade = true;
    } else if (sql.startsWith(
      'ALTER TABLE scanned_cards ADD COLUMN grade_report_json',
    )) {
      expect(gradeReport, isFalse);
      gradeReport = true;
    } else if (sql.startsWith(
      'ALTER TABLE scanned_cards ADD COLUMN back_crease_analysis',
    )) {
      expect(crease, isFalse);
      crease = true;
    } else if (sql.contains('CREATE TABLE card_centering')) {
      expect(centering, isFalse);
      expect(sql, contains('ON DELETE CASCADE'));
      centering = true;
    } else {
      throw StateError('Unexpected mutation: $sql');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
