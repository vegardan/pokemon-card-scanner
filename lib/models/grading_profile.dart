import 'dart:math';

import 'package:pokemon_card_scanner/models/card_side.dart';

/// A published centering guideline, independent of captured measurements.
class _CenteringRule {
  final double score;
  final double frontMax;
  final double backMax;

  const _CenteringRule(this.score, {required this.frontMax, required this.backMax});

  bool matchesSide(CardSide side, double leftRight, double topBottom) {
    if (side == CardSide.back) return max(leftRight, topBottom) <= backMax;
    return max(leftRight, topBottom) <= frontMax;
  }

  bool matches(double frontLeftRight, double frontTopBottom, double backLeftRight, double backTopBottom) =>
      matchesSide(CardSide.front, frontLeftRight, frontTopBottom) && matchesSide(CardSide.back, backLeftRight, backTopBottom);
}

final class GradingProfile {
  final List<_CenteringRule> _centeringRules;

  const GradingProfile._(this._centeringRules);

  double? centeringScore({required double frontLeftRight, required double frontTopBottom, required double backLeftRight, required double backTopBottom}) {
    final ratios = [frontLeftRight, frontTopBottom, backLeftRight, backTopBottom];
    if (ratios.any((value) => !value.isFinite || value < 50 || value > 100)) return null;
    for (final rule in _centeringRules) {
      if (rule.matches(frontLeftRight, frontTopBottom, backLeftRight, backTopBottom)) return rule.score;
    }
    return null;
  }

  /// Estimates one side independently, using its own centering tolerances.
  double? centeringScoreForSide({required CardSide side, required double leftRight, required double topBottom}) {
    if ([leftRight, topBottom].any((value) => !value.isFinite || value < 50 || value > 100)) return null;
    for (final rule in _centeringRules) {
      if (rule.matchesSide(side, leftRight, topBottom)) return rule.score;
    }
    return null;
  }

  // Verified on 2026-11-03 against https://www.psacard.com/gradingstandards#cards
  // PSA centering guidelines, with separate front and reverse tolerances.
  // These estimate centering eligibility only; final grades also depend on condition and grader discretion.
  // PSA 4 shares PSA 5 limits; PSA 2 and 1.5 share PSA 3 limits.
  // PSA 1 and half-point increases have no explicit numeric centering thresholds.
  // Only the highest score for each distinct centering limit is listed.
  static const psa = GradingProfile._([
    _CenteringRule(10, frontMax: 55, backMax: 75),
    _CenteringRule(9, frontMax: 60, backMax: 90),
    _CenteringRule(8, frontMax: 65, backMax: 90),
    _CenteringRule(7, frontMax: 70, backMax: 90),
    _CenteringRule(6, frontMax: 80, backMax: 90),
    _CenteringRule(5, frontMax: 85, backMax: 90),
    _CenteringRule(3, frontMax: 90, backMax: 90),
  ]);
}
