import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:pokemon_card_scanner/models/jpeg_data.dart';
import 'package:pokemon_card_scanner/vision/card_constants.dart';
import 'package:pokemon_card_scanner/vision/quality/image_quality_result.dart';

class ImageQualityChecker {
  static const double blurThreshold = 80.0;
  static const double vThreshold = 240.0;
  static const double sMaxThreshold = 45.0;
  static const double minGlarePixels = 150.0;
  static const double maxAllowedGlarePct = 0.15;
  static const int targetWidth = 1000;

  static ImageQualityResult evaluate(JpegData photo, {bool checkBlur = true}) {
    final original = cv.imdecode(photo.bytes, cv.IMREAD_COLOR);

    if (original.isEmpty) {
      return ImageQualityResult(
        isBlurry: false,
        hasGlare: false,
        blurScore: 0,
        glarePercentage: 0,
        rawPhoto: photo,
      );
    }

    cv.Mat? scaled;
    cv.Mat? roi;
    cv.Rect? roiRect;

    try {
      final scale = targetWidth / original.cols;
      final targetHeight = (original.rows * scale).round();
      scaled = cv.resize(original, (targetWidth, targetHeight), interpolation: cv.INTER_AREA);

      // Crop card guide region of interest
      final roiWidth = (scaled.cols * 0.78).round();
      final roiHeight = (roiWidth / CardConstants.cardAspectRatio).round();
      final roiX = ((scaled.cols - roiWidth) / 2).round().clamp(0, scaled.cols - 1);
      final roiY = ((scaled.rows - roiHeight) / 2).round().clamp(0, scaled.rows - 1);
      final boundedWidth = roiWidth.clamp(1, scaled.cols - roiX);
      final boundedHeight = roiHeight.clamp(1, scaled.rows - roiY);

      roiRect = cv.Rect(roiX, roiY, boundedWidth, boundedHeight);
      roi = scaled.region(roiRect);

      final blurScore = checkBlur ? _computeLaplacianVariance(roi) : 999.0;
      final isBlurry = checkBlur && (blurScore < blurThreshold);

      final (hasGlare, glarePercentage, significantBoxes) = _detectGlare(roi);

      JpegData? annotatedGlarePhoto;
      if (hasGlare) {
        final vis = scaled.clone();
        try {
          for (final box in significantBoxes) {
            final photoBox = cv.Rect(box.x + roiRect.x, box.y + roiRect.y, box.width, box.height);
            try {
              cv.rectangle(vis, photoBox, cv.Scalar(0, 0, 255, 0), thickness: 3);
            } finally {
              photoBox.dispose();
            }
          }
          final (success, jpeg) = cv.imencode('.jpg', vis);
          if (success) {
            annotatedGlarePhoto = JpegData(jpeg);
          }
        } finally {
          vis.dispose();
        }
      }

      for (final box in significantBoxes) {
        box.dispose();
      }

      return ImageQualityResult(
        isBlurry: isBlurry,
        hasGlare: hasGlare,
        blurScore: blurScore,
        glarePercentage: glarePercentage,
        rawPhoto: photo,
        annotatedGlarePhoto: annotatedGlarePhoto,
      );
    } finally {
      roiRect?.dispose();
      roi?.dispose();
      scaled?.dispose();
      original.dispose();
    }
  }

  static double _computeLaplacianVariance(cv.Mat roi) {
    final gray = cv.cvtColor(roi, cv.COLOR_BGR2GRAY);
    cv.Mat? laplacian;

    try {
      laplacian = cv.laplacian(gray, cv.MatType.CV_64F);
      final (_, stdDev) = cv.meanStdDev(laplacian);
      return stdDev.val1 * stdDev.val1;
    } finally {
      laplacian?.dispose();
      gray.dispose();
    }
  }

  static (bool, double, List<cv.Rect>) _detectGlare(cv.Mat roi) {
    final hsv = cv.cvtColor(roi, cv.COLOR_BGR2HSV);
    final channels = cv.split(hsv);
    final s = channels[1];
    final v = channels[2];

    cv.Mat? vMask;
    cv.Mat? sMask;
    cv.Mat? rawMask;
    cv.Mat? kernel;
    cv.Mat? closed;
    cv.Mat? cleaned;
    cv.Contours? contours;
    cv.VecVec4i? hierarchy;

    final significantBoxes = <cv.Rect>[];

    try {
      final (_, vThresh) = cv.threshold(v, vThreshold, 255, cv.THRESH_BINARY);
      vMask = vThresh;

      final (_, sThresh) = cv.threshold(s, sMaxThreshold, 255, cv.THRESH_BINARY_INV);
      sMask = sThresh;

      rawMask = cv.bitwiseAND(vMask, sMask);

      kernel = cv.getStructuringElement(cv.MORPH_ELLIPSE, (5, 5));
      closed = cv.morphologyEx(rawMask, cv.MORPH_CLOSE, kernel);
      cleaned = cv.morphologyEx(closed, cv.MORPH_OPEN, kernel);

      final result = cv.findContours(cleaned, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
      contours = result.$1;
      hierarchy = result.$2;

      double significantGlarePixels = 0;
      final totalPixels = roi.cols * roi.rows;

      for (var i = 0; i < contours.length; i++) {
        final cnt = contours[i];
        final area = cv.contourArea(cnt);
        if (area >= minGlarePixels) {
          significantGlarePixels += area;
          significantBoxes.add(cv.boundingRect(cnt));
        }
      }

      final glarePercentage = totalPixels > 0 ? (significantGlarePixels / totalPixels) * 100.0 : 0.0;
      final hasGlare = glarePercentage > maxAllowedGlarePct;

      return (hasGlare, glarePercentage, significantBoxes);
    } finally {
      hierarchy?.dispose();
      contours?.dispose();
      cleaned?.dispose();
      closed?.dispose();
      kernel?.dispose();
      rawMask?.dispose();
      sMask?.dispose();
      vMask?.dispose();
      channels.dispose();
      hsv.dispose();
    }
  }
}
