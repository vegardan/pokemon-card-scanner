import 'dart:math';

import 'package:pokemon_card_scanner/models/card_side.dart';

/// A published centering guideline, independent of captured measurements.
class CenteringRule {
  final double score;
  final double frontMax;
  final double backMax;

  const CenteringRule(this.score, {required this.frontMax, required this.backMax});

  bool matchesSide(CardSide side, double leftRight, double topBottom) {
    if (side == CardSide.back) return max(leftRight, topBottom) <= backMax;
    return max(leftRight, topBottom) <= frontMax;
  }

  bool matches(double frontLeftRight, double frontTopBottom, double backLeftRight, double backTopBottom) =>
      matchesSide(CardSide.front, frontLeftRight, frontTopBottom) && matchesSide(CardSide.back, backLeftRight, backTopBottom);
}

class GradingProfile {
  final String name;
  final String shortName;
  final String sourceUrl;

  /// Highest score first. Only scores with explicit centering rules are listed.
  final List<CenteringRule> centeringRules;

  const GradingProfile({required this.name, required this.shortName, required this.sourceUrl, required this.centeringRules});

  double? centeringScore({required double frontLeftRight, required double frontTopBottom, required double backLeftRight, required double backTopBottom}) {
    final ratios = [frontLeftRight, frontTopBottom, backLeftRight, backTopBottom];
    if (ratios.any((value) => !value.isFinite || value < 50 || value > 100)) return null;
    for (final rule in centeringRules) {
      if (rule.matches(frontLeftRight, frontTopBottom, backLeftRight, backTopBottom)) return rule.score;
    }
    return null;
  }

  /// Estimates one side independently, using its own centering tolerances.
  double? centeringScoreForSide({required CardSide side, required double leftRight, required double topBottom}) {
    if ([leftRight, topBottom].any((value) => !value.isFinite || value < 50 || value > 100)) return null;
    for (final rule in centeringRules) {
      if (rule.matchesSide(side, leftRight, topBottom)) return rule.score;
    }
    return null;
  }

  // Verified against the live PSA grade tabs on 2026-11-03.
  // PSA centering guidelines, with separate front and reverse tolerances.
  // These estimate centering eligibility only; final grades also depend on condition and grader discretion.
  // PSA 4 shares PSA 5 limits; PSA 2 and 1.5 share PSA 3 limits.
  // PSA 1 and half-point increases have no explicit numeric centering thresholds.
  // Only the highest score for each distinct centering limit is listed.
  static const psa = GradingProfile(
    name: 'PSA',
    shortName: 'PSA',
    sourceUrl: 'https://www.psacard.com/gradingstandards#cards',
    centeringRules: [
      CenteringRule(10, frontMax: 55, backMax: 75),
      CenteringRule(9, frontMax: 60, backMax: 90),
      CenteringRule(8, frontMax: 65, backMax: 90),
      CenteringRule(7, frontMax: 70, backMax: 90),
      CenteringRule(6, frontMax: 80, backMax: 90),
      CenteringRule(5, frontMax: 85, backMax: 90),
      CenteringRule(3, frontMax: 90, backMax: 90),
    ],
  );

  // Verified against the live BGS grade tabs on 2026-11-03.
  // Both 10 labels use 50/50 front and 55/45 back; 9.5 allows 55/45 on both front axes.
  // These approximate centering eligibility, not Beckett's proprietary subgrade algorithm.
  static const beckett = GradingProfile(
    name: 'Beckett (BGS)',
    shortName: 'BGS',
    sourceUrl: 'https://beckett.com/grading#scale',
    centeringRules: [
      // Current Pristine criteria: https://www.beckett.com/grading
      CenteringRule(10, frontMax: 50, backMax: 55),
      CenteringRule(9.5, frontMax: 55, backMax: 60),
      CenteringRule(9, frontMax: 55, backMax: 70),
      CenteringRule(8, frontMax: 60, backMax: 80),
      CenteringRule(7, frontMax: 65, backMax: 90),
      CenteringRule(6, frontMax: 70, backMax: 95),
      CenteringRule(5, frontMax: 75, backMax: 95),
      CenteringRule(4, frontMax: 80, backMax: 100),
      CenteringRule(3, frontMax: 85, backMax: 100),
      CenteringRule(2, frontMax: 90, backMax: 100),
      CenteringRule(1, frontMax: 100, backMax: 100),
    ],
  );

  static const values = [psa, beckett];
}
