import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:pokemon_card_scanner/models/card_side.dart';

import 'card_constants.dart';

/// ORB features prepared by the dataset tools in tool/dataset
class CardReference {
  /// catalog ID or shared back ID
  final String id;

  /// reference coordinate width
  final int width = 1000;

  /// reference coordinate height
  final int height = 1000;

  /// side of the card
  CardSide get side => id == CardConstants.sharedBackReferenceId ? CardSide.back : CardSide.front;

  /// ORB points in reference coordinates
  final List<({double x, double y})> points;

  /// ORB descriptors: 32 bytes per point
  final List<int> descriptors;

  CardReference({required this.id, required this.points, required this.descriptors});

  factory CardReference.fromJson(Map<String, dynamic> json) {
    final points = <({double x, double y})>[];

    for (final point in json['points'] as List) {
      points.add((x: (point[0] as num).toDouble(), y: (point[1] as num).toDouble()));
    }

    final descriptors = base64Decode(json['descriptors'] as String);
    return CardReference(id: json['id'] as String, points: points, descriptors: descriptors);
  }

  static List<CardReference> decode(List<int> compressed) {
    final json = jsonDecode(utf8.decode(gzip.decode(compressed))) as Map<String, dynamic>;
    final references = <CardReference>[];

    for (final reference in json['cards'] as List) {
      references.add(CardReference.fromJson(reference as Map<String, dynamic>));
    }

    return references;
  }
}

class IdentifiedCard {
  /// the closest front reference match, or null for a shared card back
  final CardReference? reference;

  /// corners in top-left, top-right, bottom-right, bottom-left order
  final List<cv.Point2f> corners;

  IdentifiedCard(this.reference, this.corners);

  void dispose() {
    for (final corner in corners) {
      corner.dispose();
    }
  }
}

class CardIdentifier {
  final List<CardReference> references;

  const CardIdentifier(this.references);

  /// match ORB features in a resized photo and return the closest verified card
  IdentifiedCard? scanForCapture(cv.Mat image, {CardSide side = CardSide.front, void Function(int completed, int total)? onProgress}) {
    if (references.isEmpty || image.isEmpty) {
      return null;
    }

    final scale = math.min(1.0, 1400 / math.max(image.cols, image.rows));
    final query = cv.resize(image, ((image.cols * scale).round(), (image.rows * scale).round()), interpolation: cv.INTER_AREA);
    _Features? features;
    cv.BFMatcher? matcher;
    ({CardReference reference, List<({double x, double y})> corners, int inliers})? best;

    try {
      features = _features(query);
      matcher = cv.BFMatcher.create(type: cv.NORM_HAMMING);

      if (features.descriptors.isEmpty) return null;

      // Verify the whole retrieval shortlist to find the strongest match.
      final candidates = references.where((r) => r.side == side).toList();
      onProgress?.call(0, candidates.length);

      for (var i = 0; i < candidates.length; i++) {
        final reference = candidates[i];
        final result = _match(reference, features, matcher, query.cols, query.rows);
        onProgress?.call(i + 1, candidates.length);

        if (result == null) continue;

        if (best == null || result.inliers > best.inliers) {
          best = result;
        }
      }

      if (best == null) return null;

      final corners = <cv.Point2f>[];

      for (final point in best.corners) {
        corners.add(cv.Point2f(point.x * image.cols / query.cols, point.y * image.rows / query.rows));
      }

      return IdentifiedCard(side == CardSide.back ? null : best.reference, corners);
    } finally {
      matcher?.dispose();
      features?.dispose();
      query.dispose();
    }
  }

  ({CardReference reference, List<({double x, double y})> corners, int inliers})? _match(CardReference reference, _Features query, cv.BFMatcher matcher, int width, int height) {
    final descriptors = cv.Mat.fromList(reference.points.length, CardConstants.descriptorSize, cv.MatType.CV_8UC1, reference.descriptors);
    cv.VecVecDMatch? pairs;

    try {
      pairs = matcher.knnMatch(descriptors, query.descriptors, 2);

      final source = <double>[];
      final destination = <double>[];
      final used = <int>{};

      for (var i = 0; i < pairs.length; i++) {
        final pair = pairs[i];

        if (pair.length < 2) continue;

        final best = pair[0], second = pair[1];

        try {
          if (best.distance >= 64 || best.distance >= second.distance * 0.75 || !used.add(best.trainIdx)) {
            continue;
          }

          final p = reference.points[best.queryIdx], q = query.points[best.trainIdx];
          source.addAll([p.x, p.y]);
          destination.addAll([q.x, q.y]);
        } finally {
          best.dispose();
          second.dispose();
        }
      }

      if (source.length < 24) return null;

      return _verifyGeometry(reference, source, destination, width, height);
    } finally {
      pairs?.dispose();
      descriptors.dispose();
    }
  }

  ({CardReference reference, List<({double x, double y})> corners, int inliers})? _verifyGeometry(CardReference reference, List<double> src, List<double> dst, int width, int height) {
    final source = cv.Mat.fromList((src.length / 2).toInt(), 1, cv.MatType.CV_32FC2, src);
    final destination = cv.Mat.fromList((dst.length / 2).toInt(), 1, cv.MatType.CV_32FC2, dst);
    final mask = cv.Mat.empty();
    cv.Mat? homography;

    try {
      // uses RANSAC to reject matches with reprojection errors above 3 pixels
      homography = cv.findHomography(source, destination, method: cv.RANSAC, ransacReprojThreshold: 3, mask: mask);

      if (homography.isEmpty || mask.isEmpty) return null;

      final inlierMask = mask.data;
      final inlierPoints = <({double x, double y})>[];

      for (var i = 0; i < inlierMask.length; i++) {
        if (inlierMask[i] != 0) {
          inlierPoints.add((x: src[2 * i], y: src[2 * i + 1]));
        }
      }

      final inliers = inlierPoints.length, matches = (src.length / 2).toInt();

      if (inliers < 12 || inliers / matches < 0.45) return null;

      // ensure inlier points span enough of the reference card
      final xCoordinates = inlierPoints.map((p) => p.x), ys = inlierPoints.map((p) => p.y);

      if (xCoordinates.reduce(math.max) - xCoordinates.reduce(math.min) < reference.width * 0.35 || ys.reduce(math.max) - ys.reduce(math.min) < reference.height * 0.45) {
        return null;
      }

      final corners = _projectCorners(reference, homography);

      if (!_validCardProjection(corners, width, height)) return null;

      return (reference: reference, corners: corners, inliers: inliers);
    } finally {
      homography?.dispose();
      mask.dispose();
      source.dispose();
      destination.dispose();
    }
  }

  /// transform the reference rectangle into photo coordinates
  List<({double x, double y})> _projectCorners(CardReference reference, cv.Mat homography) {
    final right = reference.width - 1.0, bottom = reference.height - 1.0;
    final rectangle = cv.Mat.fromList(4, 1, cv.MatType.CV_32FC2, [0.0, 0.0, right, 0.0, right, bottom, 0.0, bottom]);
    cv.Mat? projected;

    try {
      projected = cv.perspectiveTransform(rectangle, homography);
      final corners = <({double x, double y})>[];

      for (var i = 0; i < 4; i++) {
        final point = projected.at<cv.Vec2f>(i, 0);

        try {
          corners.add((x: point.val1, y: point.val2));
        } finally {
          point.dispose();
        }
      }

      return corners;
    } finally {
      projected?.dispose();
      rectangle.dispose();
    }
  }

  /// checks that the projected corners are usable
  bool _validCardProjection(List<({double x, double y})> corners, int imageWidth, int imageHeight) {
    // require every card corner to be completely inside the photo
    for (final corner in corners) {
      if (!corner.x.isFinite || !corner.y.isFinite) return false;

      if (corner.x < 0 || corner.x >= imageWidth || corner.y < 0 || corner.y >= imageHeight) {
        return false;
      }
    }

    final contour = cv.Contour2f.generate(4, (i) => cv.Point2f(corners[i].x, corners[i].y));

    try {
      if (!cv.isContourConvex2f(contour)) return false;

      final cardArea = cv.contourArea2f(contour);
      final imageArea = imageWidth * imageHeight;
      // require the card to fill at least 50% of the image which is close to filling the card guide overlay
      return cardArea >= imageArea * 0.50;
    } finally {
      contour.dispose();
    }
  }

  static _Features _features(cv.Mat image) {
    // grayscale ORB detection with up to 2500 features, FAST threshold 12 and no mask
    final gray = image.channels == 1 ? image.clone() : cv.cvtColor(image, image.channels == 4 ? cv.COLOR_BGRA2GRAY : cv.COLOR_BGR2GRAY);
    final orb = cv.ORB.create(nFeatures: 2500, fastThreshold: 12);
    final mask = cv.Mat.empty();

    try {
      final (keypoints, descriptors) = orb.detectAndCompute(gray, mask);

      try {
        final points = <({double x, double y})>[];

        for (var i = 0; i < keypoints.length; i++) {
          final p = keypoints[i];
          points.add((x: p.x, y: p.y));
          p.dispose();
        }

        return _Features(points, descriptors);
      } finally {
        keypoints.dispose();
      }
    } finally {
      gray.dispose();
      mask.dispose();
      orb.dispose();
    }
  }

  /// retrieves descriptors for image
  static Uint8List retrievalDescriptors(cv.Mat image) {
    final scale = math.min(1.0, 1400 / math.max(image.cols, image.rows));
    final resized = cv.resize(image, ((image.cols * scale).round(), (image.rows * scale).round()));
    _Features? features;

    try {
      features = _features(resized);
      return Uint8List.fromList(features.descriptors.data);
    } finally {
      features?.dispose();
      resized.dispose();
    }
  }
}

class _Features {
  final List<({double x, double y})> points;
  final cv.Mat descriptors;

  _Features(this.points, this.descriptors);

  void dispose() => descriptors.dispose();
}
