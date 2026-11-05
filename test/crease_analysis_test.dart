import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_card_scanner/models/crease_analysis.dart';

void main() {
  test('stored results preserve all statuses and exact line coordinates', () {
    final results = [
      const CreaseAnalysis.notEvaluated('Alignment unavailable.'),
      CreaseAnalysis(width: 600, height: 832, candidates: []),
      CreaseAnalysis(
        width: 600,
        height: 832,
        candidates: [
          (
            angle: 175.2,
            rho: -312.4,
            x1: 30.1,
            y1: 159.9,
            x2: 569.8,
            y2: 122.3,
            prominence: 47.1,
          ),
        ],
      ),
    ];
    for (final result in results) {
      final restored = CreaseAnalysis.decode(jsonEncode(result.toJson()));
      expect(restored.toJson(), result.toJson());
      expect(restored.status, result.status);
      expect(
        () => restored.candidates.add((
          angle: 0,
          rho: 0,
          x1: 0,
          y1: 0,
          x2: 1,
          y2: 1,
          prominence: 0,
        )),
        throwsUnsupportedError,
      );
    }
  });

  test('legacy, corrupt and unsupported results never imply no candidates', () {
    final empty = CreaseAnalysis(
      width: 600,
      height: 832,
      candidates: [],
    ).toJson();
    for (final stored in [
      null,
      '{',
      '{}',
      jsonEncode({...empty, 'schemaVersion': 999}),
      jsonEncode({...empty, 'width': 0}),
      jsonEncode({...empty, 'status': 'possibleCreases'}),
    ]) {
      expect(CreaseAnalysis.decode(stored).status, CreaseStatus.notEvaluated);
    }
  });
}
