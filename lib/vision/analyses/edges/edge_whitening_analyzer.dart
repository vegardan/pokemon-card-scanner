import 'package:pokemon_card_scanner/models/analysis/analysis_input.dart';
import 'package:pokemon_card_scanner/models/analysis/analysis_result.dart';
import 'package:pokemon_card_scanner/vision/analyses/card_analyzer.dart';

class EdgeWhiteningAnalyzer implements CardAnalyzer {
  const EdgeWhiteningAnalyzer();

  @override
  String get id => 'edge_whitening';

  @override
  String get displayName => 'Edge Whitening';

  @override
  AnalysisCategory get category => AnalysisCategory.edges;

  @override
  bool get isEnabled => true;

  @override
  Future<AnalysisResult> analyze(AnalysisInput input) async {
    // Stub implementation
    return const EdgeAnalysisResult(analyzerId: 'edge_whitening', confidence: 0.90, defectPerimeterRatio: 0.01, maxDefectLengthPixels: 2.0);
  }
}
