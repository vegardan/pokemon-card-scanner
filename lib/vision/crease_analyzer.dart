import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'package:pokemon_card_scanner/models/crease_analysis.dart';
export 'package:pokemon_card_scanner/models/crease_analysis.dart';

/// Transient preview plus the metadata returned to the scan and collection.
class CreaseResult extends CreaseAnalysis {
  final Uint8List? preview;

  CreaseResult({
    required this.preview,
    required super.width,
    required super.height,
    required super.candidates,
  });
  const CreaseResult.notEvaluated(super.reason)
    : preview = null,
      super.notEvaluated();

  CreaseAnalysis get analysis => evaluated
      ? CreaseAnalysis(width: width, height: height, candidates: candidates)
      : CreaseAnalysis.notEvaluated(notEvaluatedReason!);
}

class CreaseAnalyzer {
  // Image preparation and reference masking.
  static const _imageWidth = 600;
  static const _blurSize = 3, _sobelSize = 3;
  static const _referenceEdgeThreshold = 90.0;
  static const _maskKernelSize = 3;
  static const _borderFraction = .05;
  static const _frameSearchFraction = .15, _frameCoverage = .60;
  static const _frameGradientThreshold = 20.0;
  static const _frameGuard = 8, _noiseRadius = 3;

  // Missing samples are excluded from both smoothing and the median background.
  static const _smoothRadius = 3, _medianRadius = 20;
  static const _smoothSigma = 1.0;
  static const _angleStep = 5, _sectionCount = 4;
  static const _validWeight = .999;
  static const _minimumSectionPixels = 20, _peakSpacing = 9;
  static const _minimumSectionProminence = 10.0;
  static const _maxSectionPeaks = 25;

  // Shared experimental limits, not validated damage thresholds.
  static const minimumCandidateScore = 35.0;
  static const _minimumSections = 3, _maxSectionGap = 2;
  static const _maxRowStep = 22, _trackSpacing = 15;
  static const _maxTracksPerAngle = 6;
  static const _maxFitError = 3.0;
  static const _groupAngle = 10.0, _groupDistance = 25.0;

  /// Analyze a verified, perspective-corrected card back without changing it.
  static CreaseResult analyze(
    ({
      Uint8List photo,
      Uint8List? reference,
      bool alignmentVerified,
      double minimumProminence,
      Float32List? expectedNoise,
    })
    input,
  ) {
    if (!input.alignmentVerified) {
      return const CreaseResult.notEvaluated(
        'Card alignment was not verified.',
      );
    }
    if (input.reference == null || input.reference!.isEmpty) {
      return const CreaseResult.notEvaluated('Reference image unavailable.');
    }
    if (input.photo.isEmpty) {
      return const CreaseResult.notEvaluated('Photograph unavailable.');
    }
    if (!input.minimumProminence.isFinite || input.minimumProminence < 0) {
      throw ArgumentError('Invalid prominence cutoff');
    }
    final allocated = <cv.Mat>[];
    cv.Mat keep(cv.Mat mat) {
      allocated.add(mat);
      return mat;
    }

    final black = cv.Scalar(0);
    try {
      final ref = keep(cv.imdecode(input.reference!, cv.IMREAD_GRAYSCALE));
      final photo = keep(cv.imdecode(input.photo, cv.IMREAD_GRAYSCALE));
      if (ref.isEmpty || photo.isEmpty) {
        return const CreaseResult.notEvaluated('Image could not be decoded.');
      }
      const width = _imageWidth;
      final height = (ref.rows * width / ref.cols).round();
      if (height < 121) {
        return const CreaseResult.notEvaluated(
          'Reference has an unsupported aspect ratio.',
        );
      }
      final reference = keep(
        cv.resize(ref, (width, height), interpolation: cv.INTER_AREA),
      );
      final corrected = keep(
        cv.resize(photo, (width, height), interpolation: cv.INTER_AREA),
      );
      // Gradients emphasize structural differences rather than absolute brightness.
      final referenceGradient = _gradient(reference, keep);
      final photoGradient = _gradient(corrected, keep);
      final excluded = _referenceMask(referenceGradient, width, height, keep);
      final difference = keep(
        cv.absDiff(photoGradient.magnitude, referenceGradient.magnitude),
      );
      // Custom heuristic: remove residuals explainable by small reference shifts.
      final noise = input.expectedNoise ?? referenceNoise(input.reference!);
      if (noise.length != width * height) {
        throw ArgumentError('Reference noise dimensions');
      }
      final bytesView = difference.data;
      final residual = bytesView.buffer.asFloat32List(
        bytesView.offsetInBytes,
        width * height,
      );
      for (var i = 0; i < residual.length; i++) {
        residual[i] = math.max(0, residual[i] - noise[i]);
      }
      difference.setTo(black, mask: excluded);
      final valid = keep(cv.bitwiseNOT(excluded));
      final candidates = rotatedProfiles(
        difference,
        valid,
        width,
        height,
        input.minimumProminence,
      );
      final (success, bytes) = cv.imencode('.png', corrected);
      if (!success) {
        return const CreaseResult.notEvaluated(
          'Could not prepare crease preview.',
        );
      }
      return CreaseResult(
        preview: bytes,
        width: width,
        height: height,
        candidates: candidates,
      );
    } catch (_) {
      return const CreaseResult.notEvaluated(
        'Image analysis could not be completed.',
      );
    } finally {
      black.dispose();
      for (final mat in allocated.reversed) {
        mat.dispose();
      }
    }
  }

  static ({cv.Mat magnitude, cv.Mat x, cv.Mat y}) _gradient(
    cv.Mat gray,
    cv.Mat Function(cv.Mat) keep,
  ) {
    final blur = keep(cv.gaussianBlur(gray, (_blurSize, _blurSize), 0));
    final gx = keep(cv.sobel(blur, cv.MatType.CV_32F, 1, 0, ksize: _sobelSize));
    final gy = keep(cv.sobel(blur, cv.MatType.CV_32F, 0, 1, ksize: _sobelSize));
    return (magnitude: keep(cv.magnitude(gx, gy)), x: gx, y: gy);
  }

  // Suppress printed contours that otherwise dominate the projection profiles.
  static cv.Mat _referenceMask(
    ({cv.Mat magnitude, cv.Mat x, cv.Mat y}) gradient,
    int width,
    int height,
    cv.Mat Function(cv.Mat) keep,
  ) {
    final white = cv.Scalar(255);
    try {
      final (_, threshold) = cv.threshold(
        gradient.magnitude,
        _referenceEdgeThreshold,
        255,
        cv.THRESH_BINARY,
      );
      keep(threshold);
      final edges = keep(threshold.convertTo(cv.MatType.CV_8UC1));
      final kernel = keep(
        cv.getStructuringElement(cv.MORPH_RECT, (
          _maskKernelSize,
          _maskKernelSize,
        )),
      );
      final excluded = keep(cv.dilate(edges, kernel));
      final emptyMask = keep(cv.Mat.empty());
      final mx = (width * _borderFraction).round(),
          my = (height * _borderFraction).round();
      void border(int x, int y, int w, int h) {
        final rect = cv.Rect(x, y, w, h);
        cv.Mat? region;
        try {
          region = excluded.region(rect);
          region.setTo(white, mask: emptyMask);
        } finally {
          region?.dispose();
          rect.dispose();
        }
      }

      border(0, 0, width, my);
      border(0, height - my, width, my);
      border(0, 0, mx, height);
      border(width - mx, 0, mx, height);
      // Exclude expected frame edges and their surrounding registration margin.
      for (final horizontal in [true, false]) {
        final absolute = keep(
          cv.convertScaleAbs(horizontal ? gradient.y : gradient.x),
        );
        final (_, binary) = cv.threshold(
          absolute,
          _frameGradientThreshold,
          255,
          cv.THRESH_BINARY,
        );
        keep(binary);
        final rect = horizontal
            ? cv.Rect(mx, 0, width - 2 * mx, height)
            : cv.Rect(0, my, width, height - 2 * my);
        cv.Mat? region;
        try {
          region = binary.region(rect);
          final coverage = keep(
            cv.reduce(
              region,
              horizontal ? 1 : 0,
              cv.REDUCE_SUM,
              dtype: cv.MatType.CV_32S,
            ),
          );
          final length = horizontal ? height : width;
          final span = horizontal ? width - 2 * mx : height - 2 * my;
          for (var i = 0; i < length; i++) {
            if (i >= length * _frameSearchFraction &&
                i < length * (1 - _frameSearchFraction)) {
              continue;
            }
            if (coverage.at<int>(horizontal ? i : 0, horizontal ? 0 : i) <
                255 * span * _frameCoverage) {
              continue;
            }
            final start = math.max(0, i - _frameGuard),
                end = math.min(length, i + _frameGuard + 1);
            if (horizontal) {
              border(0, start, width, end - start);
            } else {
              border(start, 0, end - start, height);
            }
          }
        } finally {
          region?.dispose();
          rect.dispose();
        }
      }
      return excluded;
    } finally {
      white.dispose();
    }
  }

  /// Cache the returned Dart buffer with the fixed reference, across compute isolates.
  /// Estimate residuals caused by small reference registration errors.
  static Float32List referenceNoise(Uint8List bytes) {
    final decoded = cv.imdecode(bytes, cv.IMREAD_GRAYSCALE);
    cv.Mat? reference;
    cv.Mat? baseline;
    cv.Mat magnitude(cv.Mat image) {
      final temporary = <cv.Mat>[];
      cv.Mat? result;
      try {
        result = _gradient(image, (mat) {
          temporary.add(mat);
          return mat;
        }).magnitude;
        return result;
      } finally {
        for (final mat in temporary.reversed) {
          if (!identical(mat, result)) mat.dispose();
        }
      }
    }

    try {
      if (decoded.isEmpty) throw ArgumentError('Invalid reference');
      final height = (decoded.rows * _imageWidth / decoded.cols).round();
      reference = cv.resize(decoded, (
        _imageWidth,
        height,
      ), interpolation: cv.INTER_AREA);
      baseline = magnitude(reference);
      final baseBytes = baseline.data;
      final base = baseBytes.buffer.asFloat32List(
        baseBytes.offsetInBytes,
        _imageWidth * height,
      );
      final noise = Float32List(base.length);
      for (var dy = -_noiseRadius; dy <= _noiseRadius; dy++) {
        for (var dx = -_noiseRadius; dx <= _noiseRadius; dx++) {
          if (dx * dx + dy * dy == 0 ||
              dx * dx + dy * dy > _noiseRadius * _noiseRadius) {
            continue;
          }
          final transform = cv.Mat.fromList(2, 3, cv.MatType.CV_32FC1, [
            1.0,
            0.0,
            dx.toDouble(),
            0.0,
            1.0,
            dy.toDouble(),
          ]);
          cv.Mat? shifted, gradient;
          try {
            shifted = cv.warpAffine(reference, transform, (
              _imageWidth,
              height,
            ), borderMode: cv.BORDER_REFLECT_101);
            gradient = magnitude(shifted);
            final data = gradient.data;
            final values = data.buffer.asFloat32List(
              data.offsetInBytes,
              base.length,
            );
            for (var i = 0; i < base.length; i++) {
              noise[i] = math.max(noise[i], (values[i] - base[i]).abs());
            }
          } finally {
            gradient?.dispose();
            shifted?.dispose();
            transform.dispose();
          }
        }
      }
      return noise;
    } finally {
      baseline?.dispose();
      reference?.dispose();
      decoded.dispose();
    }
  }

  /// Gaussian smoothing reduces noise; a local median removes broad background variation.
  static List<double> profileProminence(
    List<double> scores,
    List<int> validCounts, {
    required int start,
    required int end,
  }) {
    if (scores.length != validCounts.length ||
        scores.length < 2 * _smoothRadius + 1 ||
        start < 0 ||
        end > scores.length ||
        start >= end) {
      throw ArgumentError('Invalid profile dimensions/search range');
    }
    final weights = List<double>.generate(
      2 * _smoothRadius + 1,
      (i) => math.exp(
        -(i - _smoothRadius) *
            (i - _smoothRadius) /
            (2 * _smoothSigma * _smoothSigma),
      ),
    );
    int reflect(int i) => i < 0
        ? -i
        : i >= scores.length
        ? 2 * scores.length - 2 - i
        : i;
    final values = List<double>.filled(scores.length, double.nan);
    for (var i = start; i < end; i++) {
      var smooth = 0.0, weight = 0.0;
      for (var k = -_smoothRadius; k <= _smoothRadius; k++) {
        final index = reflect(i + k);
        if (validCounts[index] == 0) continue;
        smooth += weights[k + _smoothRadius] * scores[index];
        weight += weights[k + _smoothRadius];
      }
      // Fully masked rows/columns are missing data, never zero-valued evidence.
      final background = <double>[];
      for (var k = -_medianRadius; k <= _medianRadius; k++) {
        final index = (i + k).clamp(0, scores.length - 1);
        if (validCounts[index] > 0) background.add(scores[index]);
      }
      if (weight == 0 || background.isEmpty) continue;
      background.sort();
      final middle = background.length ~/ 2;
      final median = background.length.isOdd
          ? background[middle]
          : (background[middle - 1] + background[middle]) / 2;
      final prominence = smooth / weight - median;
      values[i] = prominence;
    }
    return values;
  }

  /// Rotation covers different directions; sections reduce dilution of short signals.
  static List<PossibleCrease> rotatedProfiles(
    cv.Mat difference,
    cv.Mat valid,
    int width,
    int height,
    double cutoff,
  ) {
    final mask = valid.convertTo(cv.MatType.CV_32FC1, alpha: 1 / 255);
    try {
      final proposals = <PossibleCrease>[];
      for (var angle = 0; angle < 180; angle += _angleStep) {
        final sections = _sectionPeaks(difference, mask, width, height, angle);
        proposals.addAll(_linkSections(sections, width, height));
      }
      return _groupCandidates(proposals, cutoff);
    } finally {
      mask.dispose();
    }
  }

  // Rotate the signal and validity mask together, keeping the complete card.
  static List<List<_SectionPeak>> _sectionPeaks(
    cv.Mat difference,
    cv.Mat mask,
    int width,
    int height,
    int angle,
  ) {
    final cosine = math.cos(angle * math.pi / 180),
        sine = math.sin(angle * math.pi / 180);
    final center = cv.Point2f(width / 2, height / 2);
    final transform = cv.getRotationMatrix2D(center, angle.toDouble(), 1);
    center.dispose();
    cv.Mat? weights, numerator;
    try {
      final tx = transform.at<double>(0, 2), ty = transform.at<double>(1, 2);
      final xs = [
        tx,
        cosine * width + tx,
        sine * height + tx,
        cosine * width + sine * height + tx,
      ];
      final ys = [
        ty,
        -sine * width + ty,
        cosine * height + ty,
        -sine * width + cosine * height + ty,
      ];
      final left = xs.reduce(math.min).floor(),
          top = ys.reduce(math.min).floor();
      final rotatedWidth = xs.reduce(math.max).ceil() - left,
          rotatedHeight = ys.reduce(math.max).ceil() - top;
      final offsetX = tx - left, offsetY = ty - top;
      transform.set<double>(0, 2, offsetX);
      transform.set<double>(1, 2, offsetY);
      weights = cv.warpAffine(mask, transform, (rotatedWidth, rotatedHeight));
      numerator = cv.warpAffine(difference, transform, (
        rotatedWidth,
        rotatedHeight,
      ));
      final maskBytes = weights.data, signalBytes = numerator.data;
      final maskValues = maskBytes.buffer.asFloat32List(
            maskBytes.offsetInBytes,
            rotatedWidth * rotatedHeight,
          ),
          signalValues = signalBytes.buffer.asFloat32List(
            signalBytes.offsetInBytes,
            rotatedWidth * rotatedHeight,
          );
      final counts = List.generate(
        _sectionCount,
        (_) => List<int>.filled(rotatedHeight, 0),
      );
      final scores = List.generate(
        _sectionCount,
        (_) => List<double>.filled(rotatedHeight, 0),
      );
      final meanX = List.generate(
        _sectionCount,
        (_) => List<double>.filled(rotatedHeight, 0),
      );
      for (var y = 0; y < rotatedHeight; y++) {
        var firstValid = 0, lastValid = rotatedWidth - 1;
        while (firstValid < rotatedWidth &&
            maskValues[y * rotatedWidth + firstValid] <= _validWeight) {
          firstValid++;
        }
        while (lastValid >= firstValid &&
            maskValues[y * rotatedWidth + lastValid] <= _validWeight) {
          lastValid--;
        }
        if (lastValid < firstValid) continue;
        for (var tile = 0; tile < _sectionCount; tile++) {
          final begin =
              firstValid +
              ((lastValid - firstValid + 1) * tile / _sectionCount).floor();
          final end =
              firstValid +
              ((lastValid - firstValid + 1) * (tile + 1) / _sectionCount)
                  .floor();
          var total = 0.0, sumX = 0.0, count = 0;
          for (var x = begin; x < end; x++) {
            if (maskValues[y * rotatedWidth + x] > _validWeight) {
              count++;
              total += signalValues[y * rotatedWidth + x];
              sumX += x;
            }
          }
          counts[tile][y] = count;
          if (count > 0) {
            scores[tile][y] = total / count;
            meanX[tile][y] = sumX / count;
          }
        }
      }
      final sections = <List<_SectionPeak>>[];
      for (var tile = 0; tile < _sectionCount; tile++) {
        final prominence = profileProminence(
          scores[tile],
          counts[tile],
          start: 0,
          end: rotatedHeight,
        );
        final selected = _selectPeaks(prominence, counts[tile]);
        sections.add([
          for (final y in selected)
            (
              tile: tile,
              score: prominence[y],
              rho: y - offsetY,
              x: cosine * (meanX[tile][y] - offsetX) - sine * (y - offsetY),
              y: sine * (meanX[tile][y] - offsetX) + cosine * (y - offsetY),
            ),
        ]);
      }
      return sections;
    } finally {
      numerator?.dispose();
      weights?.dispose();
      transform.dispose();
    }
  }

  static Iterable<int> _selectPeaks(List<double> prominence, List<int> counts) {
    final peaks = <int>[];
    for (var i = 1; i < prominence.length - 1;) {
      var j = i;
      while (j + 1 < prominence.length && prominence[j + 1] == prominence[i]) {
        j++;
      }
      if (j < prominence.length - 1 &&
          prominence[i] > prominence[i - 1] &&
          prominence[j] > prominence[j + 1]) {
        peaks.add((i + j) ~/ 2);
      }
      i = j + 1;
    }
    peaks.sort((a, b) {
      final order = prominence[b].compareTo(prominence[a]);
      return order != 0 ? order : b.compareTo(a);
    });
    final spaced = <int>[];
    for (final y in peaks) {
      if (spaced.every((other) => (other - y).abs() >= _peakSpacing)) {
        spaced.add(y);
      }
    }
    return spaced
        .where(
          (y) =>
              counts[y] >= _minimumSectionPixels &&
              prominence[y] >= _minimumSectionProminence,
        )
        .take(_maxSectionPeaks);
  }

  // Require section peaks to follow a common line before pruning competing tracks.
  static List<PossibleCrease> _linkSections(
    List<List<_SectionPeak>> sections,
    int width,
    int height,
  ) {
    final result = <PossibleCrease>[];
    final tracks = <({double score, double rho, PossibleCrease line})>[];
    void walk(List<_SectionPeak> path) {
      if (path.length >= _minimumSections) {
        final score = _median(path.map((p) => p.score).toList());
        final line = _fit(path, width, height, score);
        if (line != null) {
          tracks.add((
            score: score,
            rho: _median(path.map((p) => p.rho).toList()),
            line: line,
          ));
        }
      }
      for (final tile in [
        path.last.tile + 1,
        path.last.tile + _maxSectionGap,
      ]) {
        if (tile >= _sectionCount) continue;
        for (final peak in sections[tile]) {
          if ((peak.rho - path.last.rho).abs() <=
              _maxRowStep * (tile - path.last.tile)) {
            walk([...path, peak]);
          }
        }
      }
    }

    for (var tile = 0; tile <= _sectionCount - _minimumSections; tile++) {
      for (final peak in sections[tile]) {
        walk([peak]);
      }
    }
    // Keep enumeration order when scores tie.
    final ordered = tracks.indexed.toList()
      ..sort((a, b) {
        final order = b.$2.score.compareTo(a.$2.score);
        return order != 0 ? order : a.$1.compareTo(b.$1);
      });
    final selectedRhos = <double>[];
    for (final entry in ordered) {
      final track = entry.$2;
      if (selectedRhos.any((rho) => (track.rho - rho).abs() < _trackSpacing)) {
        continue;
      }
      selectedRhos.add(_roundTenth(track.rho));
      result.add(track.line);
      if (selectedRhos.length == _maxTracksPerAngle) break;
    }
    return result;
  }

  // Compare both midpoint-to-line distances, including angles near 0/180 degrees.
  static List<PossibleCrease> _groupCandidates(
    List<PossibleCrease> proposals,
    double cutoff,
  ) {
    final ordered = proposals.indexed.toList()
      ..sort((a, b) {
        final order = b.$2.prominence.compareTo(a.$2.prominence);
        return order != 0 ? order : a.$1.compareTo(b.$1);
      });
    final kept = <PossibleCrease>[];
    for (final entry in ordered) {
      final line = entry.$2;
      final duplicate = kept.any((other) {
        final delta = (line.angle - other.angle).abs();
        if (math.min(delta, 180 - delta) > _groupAngle) return false;
        double distance(PossibleCrease a, PossibleCrease b) {
          final t = b.angle * math.pi / 180;
          return (-math.sin(t) * (a.x1 + a.x2) / 2 +
                  math.cos(t) * (a.y1 + a.y2) / 2 -
                  b.rho)
              .abs();
        }

        return math.max(distance(line, other), distance(other, line)) <=
            _groupDistance;
      });
      if (line.prominence < cutoff || duplicate) continue;
      kept.add(line);
    }
    return kept;
  }

  static double _median(List<double> values) {
    values.sort();
    final m = values.length ~/ 2;
    return values.length.isOdd ? values[m] : (values[m - 1] + values[m]) / 2;
  }

  static double _roundTenth(double value) => (value * 10).roundToDouble() / 10;

  // Fit an orthogonal least-squares line through the section points.
  static PossibleCrease? _fit(
    List<_SectionPeak> path,
    int width,
    int height,
    double score,
  ) {
    final centroidX = path.fold(0.0, (sum, p) => sum + p.x) / path.length;
    final centroidY = path.fold(0.0, (sum, p) => sum + p.y) / path.length;
    var covarianceXX = 0.0, covarianceXY = 0.0, covarianceYY = 0.0;
    for (final p in path) {
      covarianceXX += (p.x - centroidX) * (p.x - centroidX);
      covarianceXY += (p.x - centroidX) * (p.y - centroidY);
      covarianceYY += (p.y - centroidY) * (p.y - centroidY);
    }
    final angle =
        (.5 *
            math.atan2(2 * covarianceXY, covarianceXX - covarianceYY) *
            180 /
            math.pi) %
        180;
    final s = math.sin(angle * math.pi / 180),
        c = math.cos(angle * math.pi / 180);
    final rho = -s * centroidX + c * centroidY;
    if (path.any((p) => (-s * p.x + c * p.y - rho).abs() > _maxFitError)) {
      return null;
    }
    final points = <(double, double)>[];
    final bx = (width * _borderFraction).round().toDouble(),
        by = (height * _borderFraction).round().toDouble();
    void add(double x, double y) {
      if (x >= bx - .001 &&
          x <= width - bx + .001 &&
          y >= by - .001 &&
          y <= height - by + .001) {
        points.add((x, y));
      }
    }

    if (c.abs() > 1e-8) {
      for (final x in [bx, width - bx]) {
        add(x, (rho + s * x) / c);
      }
    }
    if (s.abs() > 1e-8) {
      for (final y in [by, height - by]) {
        add((c * y - rho) / s, y);
      }
    }
    if (points.length < 2) return null;
    var a = points.first, b = points.last, longest = -1.0;
    for (final p in points) {
      for (final q in points) {
        final d = (p.$1 - q.$1) * (p.$1 - q.$1) + (p.$2 - q.$2) * (p.$2 - q.$2);
        if (d > longest) {
          longest = d;
          a = p;
          b = q;
        }
      }
    }
    return (
      angle: angle,
      rho: rho,
      x1: a.$1,
      y1: a.$2,
      x2: b.$1,
      y2: b.$2,
      prominence: _roundTenth(score),
    );
  }
}

typedef _SectionPeak = ({
  int tile,
  double score,
  double rho,
  double x,
  double y,
});
