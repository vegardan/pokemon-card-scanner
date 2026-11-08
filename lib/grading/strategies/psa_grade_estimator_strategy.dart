import 'dart:math' as math;

import 'package:pokemon_card_scanner/grading/strategies/grade_estimator_strategy.dart';
import 'package:pokemon_card_scanner/models/analysis/analysis_result.dart';
import 'package:pokemon_card_scanner/models/analysis/estimated_grade.dart';
import 'package:pokemon_card_scanner/models/card_side.dart';
import 'package:pokemon_card_scanner/models/grading_profile.dart';
import 'package:pokemon_card_scanner/vision/crease_analyzer.dart';

class PSAGradeEstimatorStrategy implements GradeEstimatorStrategy {
  const PSAGradeEstimatorStrategy();

  @override
  String get name => 'PSA';

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
            score = 2.0;
            description = '${damaged.join(', ')} wear detected (PSA 2 max)';
          } else {
            score = 10.0;
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
          final bool isNotEvaluated = s.creaseAnalysis?.status == CreaseStatus.notEvaluated;
          final double score;
          final String description;
          final Map<String, dynamic> details = {
            'defectCount': s.defectCount,
            'defectAreaRatio': s.defectAreaRatio,
            if (s.creaseAnalysis != null)
              'creaseStatus': s.creaseAnalysis!.status.name,
          };

          if (isNotEvaluated) {
            score = 0.0;
            description = 'Crease screening not evaluated';
            details['unmeasured'] = true;
          } else if (s.defectCount > 0) {
            score = 3.0;
            description = '${s.defectCount} crease(s) detected (PSA 3 max)';
          } else {
            score = 10.0;
            description = 'No obvious creases detected';
          }

          subGrades.add(
            SubGrade(
              category: 'Creases',
              score: score,
              description: description,
              details: details,
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

    final overall = scorable.isEmpty
        ? 10.0
        : scorable.map((s) => s.score).reduce(math.min);

    return EstimatedGrade(
      overallScore: overall.round().clamp(1, 10),
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
      final frontScore = _evaluateSideCentering(CardSide.front, fLR, fTB);
      final backScore = _evaluateSideCentering(CardSide.back, bLR, bTB);
      final score = math.min(frontScore, backScore);
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
          'frontScore': frontScore,
          'backScore': backScore,
        },
      );
    }

    // Case B: Front unmeasured, Back measured
    if (!c.frontMeasured && c.backMeasured) {
      final score = _evaluateSideCentering(CardSide.back, bLR, bTB);
      return SubGrade(
        category: 'Centering',
        score: score,
        description: 'Back ${fmt(bLR)} (Front unmeasured)',
        details: {
          'frontMeasured': false,
          'backMeasured': true,
          'backLeftRight': bLR,
          'backTopBottom': bTB,
          'backScore': score,
          'provisional': true,
          'note': 'Front border could not be detected; centering estimated from card back.',
        },
      );
    }

    // Case C: Front measured, Back unmeasured
    if (c.frontMeasured && !c.backMeasured) {
      final score = _evaluateSideCentering(CardSide.front, fLR, fTB);
      return SubGrade(
        category: 'Centering',
        score: score,
        description: 'Front ${fmt(fLR)} (Back unmeasured)',
        details: {
          'frontMeasured': true,
          'backMeasured': false,
          'frontLeftRight': fLR,
          'frontTopBottom': fTB,
          'frontScore': score,
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

  static double _evaluateSideCentering(CardSide side, double lr, double tb) {
    return GradingProfile.psa.centeringScoreForSide(
          side: side,
          leftRight: lr,
          topBottom: tb,
        ) ??
        1.0;
  }
}
