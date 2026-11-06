import 'package:pokemon_card_scanner/models/analysis/analysis_input.dart';
import 'package:pokemon_card_scanner/models/analysis/analysis_result.dart';

abstract interface class CardAnalyzer {
  String get id;
  String get displayName;
  AnalysisCategory get category;
  bool get isEnabled => true;

  Future<AnalysisResult> analyze(AnalysisInput input);
}
