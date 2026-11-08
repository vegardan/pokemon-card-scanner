import 'dart:math' as math;

import 'package:pokemon_card_scanner/controllers/grading_profile_controller.dart';
import 'package:pokemon_card_scanner/grading/strategies/grade_estimator_strategy.dart';
import 'package:pokemon_card_scanner/models/analysis/analysis_result.dart';
import 'package:pokemon_card_scanner/models/analysis/estimated_grade.dart';
import 'package:pokemon_card_scanner/models/card_side.dart';
import 'package:pokemon_card_scanner/models/grading_profile.dart';

class DefaultGradeEstimatorStrategy implements GradeEstimatorStrategy {
  final GradingProfile? profile;

  const DefaultGradeEstimatorStrategy({this.profile});

  GradingProfile get _activeProfile =>
      profile ?? GradingProfileController.instance.value;

  @override
  String get name => 'Default';

  @override
  EstimatedGrade estimate(List<AnalysisResult> results) {
    final subGrades = <SubGrade>[];

    for (final result in results) {
      switch (result) {
        case CenteringAnalysisResult c:
          subGrades.add(_estimateCentering(c));
        case EdgeAnalysisResult _:
          subGrades.add(
            const SubGrade(
              category: 'Edges',
              score: 0.0,
              description: 'Edge wear analysis has not been implemented yet',
              details: {
                'unimplemented': true,
                'note': 'Edge wear analysis has not been implemented yet.',
              },
            ),
          );
        case CornerAnalysisResult k:
          final damaged = k.backCorners.where((c) => c.isDamaged).map((c) => c.name).toList();

          final double score;
          final String description;

          if (damaged.isNotEmpty) {
            score = (10.0 - (damaged.length * 1.0) - (k.maxCornerWear * 1.5)).clamp(1.0, 8.5);
            description = '${damaged.join(', ')} wear detected';
          } else if (k.maxCornerWear > 0.4) {
            score = 9.0;
            description = 'Minor corner wear detected';
          } else {
            score = 9.5;
            description = 'Clean corners';
          }

          subGrades.add(
            SubGrade(
              category: 'Corners',
              score: score,
              description: description,
              details: {
                'backCorners': k.backCorners.map((c) => c.toJson()).toList(),
              },
            ),
          );
        case SurfaceAnalysisResult s:
          final double score;
          final String description;

          if (s.defectCount > 0) {
            score = (10.0 - (s.defectCount * 2.0)).clamp(1.0, 7.0);
            description = '${s.defectCount} possible crease(s) detected';
          } else {
            score = 9.5;
            description = 'No obvious creases detected';
          }

          subGrades.add(
            SubGrade(
              category: 'Creases',
              score: score,
              description: description,
              details: {
                'defectCount': s.defectCount,
                'defectAreaRatio': s.defectAreaRatio,
                if (s.creaseAnalysis != null)
                  'creaseStatus': s.creaseAnalysis!.status.name,
              },
            ),
          );
      }
    }

    final scorable = subGrades
        .where((s) =>
            s.details?['unmeasured'] != true &&
            s.details?['unimplemented'] != true &&
            s.score > 0)
        .toList();

    final average = scorable.isEmpty
        ? 10.0
        : scorable.map((s) => s.score).reduce((a, b) => a + b) / scorable.length;

    return EstimatedGrade(
      overallScore: average.round().clamp(1, 10),
      strategyName: name,
      subGrades: subGrades,
    );
  }

  SubGrade _estimateCentering(CenteringAnalysisResult c) {
    final fLR = c.frontResult != null
        ? c.frontResult!.leftRight
        : (math.max(c.frontLeftRightRatio, 1.0 - c.frontLeftRightRatio) * 100);
    final fTB = c.frontResult != null
        ? c.frontResult!.topBottom
        : (math.max(c.frontTopBottomRatio, 1.0 - c.frontTopBottomRatio) * 100);

    final bLR = c.backResult != null
        ? c.backResult!.leftRight
        : (math.max(c.backLeftRightRatio, 1.0 - c.backLeftRightRatio) * 100);
    final bTB = c.backResult != null
        ? c.backResult!.topBottom
        : (math.max(c.backTopBottomRatio, 1.0 - c.backTopBottomRatio) * 100);

    String fmt(double val) => '${val.round()}/${100 - val.round()}';

    // Case A: Both measured
    if (c.frontMeasured && c.backMeasured) {
      final score = _evaluateCenteringScore(_activeProfile, fLR, fTB, bLR, bTB);
      return SubGrade(
        category: 'Centering',
        score: score,
        description: 'Front ${fmt(fLR)} • Back ${fmt(bLR)}',
        details: {
          'frontMeasured': true,
          'backMeasured': true,
          'frontLeftRight': fLR,
          'frontTopBottom': fTB,
          'backLeftRight': bLR,
          'backTopBottom': bTB,
        },
      );
    }

    // Case B: Front unmeasured, Back measured (common on full-art/illustration rares)
    if (!c.frontMeasured && c.backMeasured) {
      final rawScore = _evaluateSideScore(_activeProfile, CardSide.back, bLR, bTB);
      // Cap at 9.0 since front is unverified
      final score = rawScore.clamp(1.0, 9.0);
      return SubGrade(
        category: 'Centering',
        score: score,
        description: 'Back ${fmt(bLR)} (Front unmeasured)',
        details: {
          'frontMeasured': false,
          'backMeasured': true,
          'backLeftRight': bLR,
          'backTopBottom': bTB,
          'provisional': true,
          'note': 'Front border could not be detected; centering estimated from card back.',
        },
      );
    }

    // Case C: Front measured, Back unmeasured
    if (c.frontMeasured && !c.backMeasured) {
      final rawScore = _evaluateSideScore(_activeProfile, CardSide.front, fLR, fTB);
      // Cap at 9.0 since back is unverified
      final score = rawScore.clamp(1.0, 9.0);
      return SubGrade(
        category: 'Centering',
        score: score,
        description: 'Front ${fmt(fLR)} (Back unmeasured)',
        details: {
          'frontMeasured': true,
          'backMeasured': false,
          'frontLeftRight': fLR,
          'frontTopBottom': fTB,
          'provisional': true,
          'note': 'Back border could not be detected; centering estimated from card front.',
        },
      );
    }

    // Case D: Both unmeasured
    return const SubGrade(
      category: 'Centering',
      score: 0.0,
      description: 'Could not be measured',
      details: {
        'frontMeasured': false,
        'backMeasured': false,
        'unmeasured': true,
        'note': 'Card borders could not be detected on either side.',
      },
    );
  }

  double _evaluateCenteringScore(
    GradingProfile profile,
    double fLR,
    double fTB,
    double bLR,
    double bTB,
  ) {
    final score = profile.centeringScore(
      frontLeftRight: fLR,
      frontTopBottom: fTB,
      backLeftRight: bLR,
      backTopBottom: bTB,
    );
    if (score != null) return score;

    final maxRatio = [fLR, fTB, bLR, bTB].reduce(math.max);
    if (maxRatio >= 95) return 1.0;
    return 2.0;
  }

  double _evaluateSideScore(
    GradingProfile profile,
    CardSide side,
    double lr,
    double tb,
  ) {
    final score = profile.centeringScoreForSide(
      side: side,
      leftRight: lr,
      topBottom: tb,
    );
    if (score != null) return score;

    final maxRatio = math.max(lr, tb);
    if (maxRatio >= 95) return 1.0;
    return 2.0;
  }
}
