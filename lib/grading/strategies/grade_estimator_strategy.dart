import 'package:pokemon_card_scanner/models/analysis/analysis_result.dart';
import 'package:pokemon_card_scanner/models/analysis/estimated_grade.dart';

abstract interface class GradeEstimatorStrategy {
  String get name;
  EstimatedGrade estimate(List<AnalysisResult> results);
}
