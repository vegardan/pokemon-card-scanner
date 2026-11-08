import 'package:pokemon_card_scanner/centering/centering_check.dart';
import 'package:pokemon_card_scanner/models/analysis/corner_wear_data.dart';
import 'package:pokemon_card_scanner/models/crease_analysis.dart';
import 'package:pokemon_card_scanner/models/jpeg_data.dart';

enum AnalysisCategory { centering, edges, corners, surface }

sealed class AnalysisResult {
  final String analyzerId;
  final AnalysisCategory category;
  final double confidence;

  const AnalysisResult({required this.analyzerId, required this.category, required this.confidence});
}

class CenteringAnalysisResult extends AnalysisResult {
  final double frontLeftRightRatio;
  final double frontTopBottomRatio;
  final double backLeftRightRatio;
  final double backTopBottomRatio;
  final bool frontMeasured;
  final bool backMeasured;
  final CenteringResult? frontResult;
  final CenteringResult? backResult;

  const CenteringAnalysisResult({
    required super.analyzerId,
    required super.confidence,
    required this.frontLeftRightRatio,
    required this.frontTopBottomRatio,
    required this.backLeftRightRatio,
    required this.backTopBottomRatio,
    this.frontMeasured = true,
    this.backMeasured = true,
    this.frontResult,
    this.backResult,
  }) : super(category: AnalysisCategory.centering);
}

class EdgeAnalysisResult extends AnalysisResult {
  final double defectPerimeterRatio;
  final double maxDefectLengthPixels;

  const EdgeAnalysisResult({required super.analyzerId, required super.confidence, required this.defectPerimeterRatio, required this.maxDefectLengthPixels}) : super(category: AnalysisCategory.edges);
}

class CornerAnalysisResult extends AnalysisResult {
  final double averageCornerWear;
  final double maxCornerWear;
  final List<CornerInspectionData> frontCorners;
  final List<CornerInspectionData> backCorners;
  final JpegData? annotatedFrontPhoto;
  final JpegData? annotatedBackPhoto;

  const CornerAnalysisResult({
    required super.analyzerId,
    required super.confidence,
    required this.averageCornerWear,
    required this.maxCornerWear,
    this.frontCorners = const [],
    this.backCorners = const [],
    this.annotatedFrontPhoto,
    this.annotatedBackPhoto,
  }) : super(category: AnalysisCategory.corners);
}

class SurfaceAnalysisResult extends AnalysisResult {
  final int defectCount;
  final double defectAreaRatio;
  final CreaseAnalysis? creaseAnalysis;

  const SurfaceAnalysisResult({required super.analyzerId, required super.confidence, required this.defectCount, required this.defectAreaRatio, this.creaseAnalysis})
    : super(category: AnalysisCategory.surface);
}
