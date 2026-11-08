import 'package:pokemon_card_scanner/centering/centering_check.dart';
import 'package:pokemon_card_scanner/models/analysis/analysis_input.dart';
import 'package:pokemon_card_scanner/models/analysis/analysis_result.dart';
import 'package:pokemon_card_scanner/vision/analyses/card_analyzer.dart';

class CenteringAnalyzer implements CardAnalyzer {
  const CenteringAnalyzer();

  @override
  String get id => 'centering';

  @override
  String get displayName => 'Centering';

  @override
  AnalysisCategory get category => AnalysisCategory.centering;

  @override
  bool get isEnabled => true;

  @override
  Future<AnalysisResult> analyze(AnalysisInput input) async {
    CenteringResult? frontResult = input.frontCentering;
    CenteringResult? backResult = input.backCentering;

    if (frontResult == null && !input.frontImage.isEmpty) {
      try {
        frontResult = checkCentering(input.frontImage, front: true);
      } catch (_) {}
    }

    if (backResult == null && !input.backImage.isEmpty) {
      try {
        backResult = checkCentering(input.backImage, front: false);
      } catch (_) {}
    }

    final frontMeasured = frontResult != null;
    final backMeasured = backResult != null;

    final fLR = frontResult != null ? frontResult.leftMm / (frontResult.leftMm + frontResult.rightMm) : 0.50;
    final fTB = frontResult != null ? frontResult.topMm / (frontResult.topMm + frontResult.bottomMm) : 0.50;
    final bLR = backResult != null ? backResult.leftMm / (backResult.leftMm + backResult.rightMm) : 0.50;
    final bTB = backResult != null ? backResult.topMm / (backResult.topMm + backResult.bottomMm) : 0.50;

    final confidence = (frontMeasured && backMeasured)
        ? 0.95
        : (frontMeasured || backMeasured)
        ? 0.80
        : 0.50;

    return CenteringAnalysisResult(
      analyzerId: id,
      confidence: confidence,
      frontLeftRightRatio: fLR,
      frontTopBottomRatio: fTB,
      backLeftRightRatio: bLR,
      backTopBottomRatio: bTB,
      frontMeasured: frontMeasured,
      backMeasured: backMeasured,
      frontResult: frontResult,
      backResult: backResult,
    );
  }
}
