import 'dart:convert';

/// Coordinates belong to the resized, perspective-corrected back image.
/// Endpoints describe a line hypothesis, not measured physical damage length.
typedef PossibleCrease = ({
  double angle,
  double rho,
  double x1,
  double y1,
  double x2,
  double y2,
  double prominence,
});

enum CreaseStatus { notEvaluated, noCandidates, possibleCreases }

/// Persistable analysis metadata. It neither contains an image nor assigns a grade.
class CreaseAnalysis {
  static const schemaVersion = 1;
  static const method = 'back_tiled_reference_v1';
  static const unavailable = CreaseAnalysis.notEvaluated(
    'No stored crease analysis.',
  );

  final int width, height;
  final List<PossibleCrease> candidates;
  final String? notEvaluatedReason;

  CreaseAnalysis({
    required this.width,
    required this.height,
    required List<PossibleCrease> candidates,
  }) : candidates = List.unmodifiable(candidates),
       notEvaluatedReason = null;

  const CreaseAnalysis.notEvaluated(String reason)
    : width = 0,
      height = 0,
      candidates = const [],
      notEvaluatedReason = reason;

  bool get evaluated => notEvaluatedReason == null;
  CreaseStatus get status => !evaluated
      ? CreaseStatus.notEvaluated
      : candidates.isEmpty
      ? CreaseStatus.noCandidates
      : CreaseStatus.possibleCreases;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'method': method,
    'status': status.name,
    'width': width,
    'height': height,
    'reason': notEvaluatedReason,
    'candidates': [
      for (final line in candidates)
        {
          'angle': line.angle,
          'rho': line.rho,
          'x1': line.x1,
          'y1': line.y1,
          'x2': line.x2,
          'y2': line.y2,
          'prominence': line.prominence,
        },
    ],
  };

  /// Legacy, invalid or unknown metadata must never appear as a clean result.
  static CreaseAnalysis decode(String? stored) {
    if (stored == null) return unavailable;
    try {
      final json = jsonDecode(stored) as Map<String, dynamic>;
      if (json['schemaVersion'] != schemaVersion || json['method'] != method) {
        return const CreaseAnalysis.notEvaluated(
          'Stored crease analysis uses an unsupported version.',
        );
      }
      if (json['status'] == CreaseStatus.notEvaluated.name) {
        return CreaseAnalysis.notEvaluated(json['reason'] as String);
      }
      final width = json['width'] as int, height = json['height'] as int;
      if (width <= 0 || height <= 0) {
        throw const FormatException('Invalid image dimensions');
      }
      double number(Map<String, dynamic> line, String key) {
        final value = (line[key] as num).toDouble();
        if (!value.isFinite) {
          throw const FormatException('Invalid line coordinate');
        }
        return value;
      }

      final candidates = <PossibleCrease>[];
      for (final item in json['candidates'] as List) {
        final line = item as Map<String, dynamic>;
        candidates.add((
          angle: number(line, 'angle'),
          rho: number(line, 'rho'),
          x1: number(line, 'x1'),
          y1: number(line, 'y1'),
          x2: number(line, 'x2'),
          y2: number(line, 'y2'),
          prominence: number(line, 'prominence'),
        ));
      }
      final analysis = CreaseAnalysis(
        width: width,
        height: height,
        candidates: candidates,
      );
      if (analysis.status.name != json['status']) {
        throw const FormatException('Inconsistent status');
      }
      return analysis;
    } catch (_) {
      return const CreaseAnalysis.notEvaluated(
        'Stored crease analysis could not be read.',
      );
    }
  }
}
