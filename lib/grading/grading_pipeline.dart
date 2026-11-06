import 'package:flutter/foundation.dart';
import 'package:pokemon_card_scanner/grading/strategies/default_grade_estimator_strategy.dart';
import 'package:pokemon_card_scanner/grading/strategies/grade_estimator_strategy.dart';
import 'package:pokemon_card_scanner/models/analysis/analysis_input.dart';
import 'package:pokemon_card_scanner/models/analysis/analysis_result.dart';
import 'package:pokemon_card_scanner/models/analysis/estimated_grade.dart';
import 'package:pokemon_card_scanner/vision/analyses/card_analyzer.dart';
import 'package:pokemon_card_scanner/vision/analyses/centering/centering_analyzer.dart';
import 'package:pokemon_card_scanner/vision/analyses/corners/corner_wear_analyzer.dart';
import 'package:pokemon_card_scanner/vision/analyses/edges/edge_whitening_analyzer.dart';
import 'package:pokemon_card_scanner/vision/analyses/surface/surface_defect_analyzer.dart';

class PipelineRunResult {
  final EstimatedGrade grade;
  final List<AnalysisResult> results;

  const PipelineRunResult({required this.grade, required this.results});
}

class GradingPipeline {
  final List<CardAnalyzer> analyzers;
  final GradeEstimatorStrategy strategy;

  GradingPipeline({
    List<CardAnalyzer>? analyzers,
    this.strategy = const DefaultGradeEstimatorStrategy(),
  }) : analyzers = analyzers ?? defaultAnalyzers;

  static const List<CardAnalyzer> defaultAnalyzers = [
    CenteringAnalyzer(),
    EdgeWhiteningAnalyzer(),
    CornerWearAnalyzer(),
    SurfaceDefectAnalyzer(),
  ];

  Future<PipelineRunResult> run(
    AnalysisInput input, {
    void Function(String step)? onProgress,
  }) async {
    final active = analyzers.where((a) => a.isEnabled).toList();
    final results = <AnalysisResult>[];

    for (final analyzer in active) {
      onProgress?.call('Analyzing ${analyzer.displayName}...');
      try {
        final result = await analyzer.analyze(input);
        results.add(result);
      } catch (error, stack) {
        debugPrint('Analyzer ${analyzer.id} failed: $error\n$stack');
      }
    }

    onProgress?.call('Estimating grade...');
    final grade = strategy.estimate(results);
    return PipelineRunResult(grade: grade, results: results);
  }
}
