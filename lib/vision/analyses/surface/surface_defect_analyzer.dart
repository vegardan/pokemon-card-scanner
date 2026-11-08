import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:pokemon_card_scanner/models/analysis/analysis_input.dart';
import 'package:pokemon_card_scanner/models/analysis/analysis_result.dart';
import 'package:pokemon_card_scanner/vision/analyses/card_analyzer.dart';
import 'package:pokemon_card_scanner/vision/crease_analyzer.dart';

class SurfaceDefectAnalyzer implements CardAnalyzer {
  const SurfaceDefectAnalyzer();

  @override
  String get id => 'surface_defect';

  @override
  String get displayName => 'Creases';

  @override
  AnalysisCategory get category => AnalysisCategory.surface;

  @override
  bool get isEnabled => true;

  @override
  Future<AnalysisResult> analyze(AnalysisInput input) async {
    try {
      final CreaseAnalysis result;
      if (input.backCreases != null && input.backCreases!.evaluated) {
        result = input.backCreases!;
      } else {
        final Uint8List backBytes;
        if (input.backPhoto != null && input.backPhoto!.bytes.isNotEmpty) {
          backBytes = input.backPhoto!.bytes;
        } else {
          final (okBack, encoded) = cv.imencode('.jpg', input.backImage);
          if (!okBack || encoded.isEmpty) {
            return const SurfaceAnalysisResult(analyzerId: 'surface_defect', confidence: 0.80, defectCount: 0, defectAreaRatio: 0.0);
          }
          backBytes = encoded;
        }

        Uint8List? refBytes;
        try {
          final data = await rootBundle.load('assets/pokemon_back.png');
          refBytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        } catch (_) {}

        result = await compute(CreaseAnalyzer.analyze, (photo: backBytes, reference: refBytes, expectedNoise: null, alignmentVerified: true, minimumProminence: CreaseAnalyzer.minimumCandidateScore));
      }

      final count = result.candidates.length;
      final ratio = count > 0 ? (count * 0.02).clamp(0.0, 1.0) : 0.0;

      return SurfaceAnalysisResult(analyzerId: id, confidence: result.evaluated ? 0.90 : 0.70, defectCount: count, defectAreaRatio: ratio, creaseAnalysis: result);
    } catch (_) {
      return const SurfaceAnalysisResult(analyzerId: 'surface_defect', confidence: 0.70, defectCount: 0, defectAreaRatio: 0.0);
    }
  }
}
