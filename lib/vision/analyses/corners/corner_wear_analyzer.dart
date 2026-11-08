import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:pokemon_card_scanner/models/analysis/analysis_input.dart';
import 'package:pokemon_card_scanner/models/analysis/analysis_result.dart';
import 'package:pokemon_card_scanner/models/analysis/corner_wear_data.dart';
import 'package:pokemon_card_scanner/models/jpeg_data.dart';
import 'package:pokemon_card_scanner/vision/analyses/card_analyzer.dart';

class CornerWearAnalyzer implements CardAnalyzer {
  const CornerWearAnalyzer();

  static const double minDefectArea = 12.0;
  static const int minThicknessPx = 10;
  static const double minBoxFill = 0.28;
  static const double whiteLMin = 82.0;
  static const double whiteChromaMax = 18.0;
  static const int safetyBufferPx = 3;

  @override
  String get id => 'corner_wear';

  @override
  String get displayName => 'Corner Wear';

  @override
  AnalysisCategory get category => AnalysisCategory.corners;

  @override
  bool get isEnabled => false;

  @override
  Future<AnalysisResult> analyze(AnalysisInput input) async {
    final Uint8List bytes;
    if (input.backPhoto != null && input.backPhoto!.bytes.isNotEmpty) {
      bytes = input.backPhoto!.bytes;
    } else {
      final (ok, encoded) = cv.imencode('.jpg', input.backImage);
      if (!ok || encoded.isEmpty) {
        return const CornerAnalysisResult(analyzerId: 'corner_wear', confidence: 0.50, averageCornerWear: 0.0, maxCornerWear: 0.0);
      }
      bytes = encoded;
    }

    final backResult = await compute(_isolateAnalyzeStrictWhiteCorners, bytes);

    final backCorners = backResult?.corners ?? const [];

    double avgWear = 0.0;
    double maxWear = 0.0;

    if (backCorners.isNotEmpty) {
      final wearScores = backCorners.map((c) {
        if (c.isDamaged) return 1.0;
        return (c.blobArea / 100.0).clamp(0.0, 1.0);
      }).toList();

      avgWear = wearScores.reduce((a, b) => a + b) / wearScores.length;
      maxWear = wearScores.reduce(math.max);
    }

    return CornerAnalysisResult(
      analyzerId: id,
      confidence: 0.95,
      averageCornerWear: avgWear,
      maxCornerWear: maxWear,
      frontCorners: const [],
      backCorners: backCorners,
      annotatedFrontPhoto: null,
      annotatedBackPhoto: backResult?.annotatedPhoto,
    );
  }

  static ({List<CornerInspectionData> corners, JpegData annotatedPhoto})? _isolateAnalyzeStrictWhiteCorners(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    final img = cv.imdecode(bytes, cv.IMREAD_COLOR);
    try {
      return _analyzeStrictWhiteCorners(img);
    } finally {
      img.dispose();
    }
  }

  static ({List<CornerInspectionData> corners, JpegData annotatedPhoto})? _analyzeStrictWhiteCorners(cv.Mat img) {
    if (img.isEmpty || img.cols < 100 || img.rows < 100) return null;

    cv.Mat? gray;
    cv.Mat? activeScreen;
    cv.Mat? crop;
    cv.Mat? hsv;
    cv.Mat? blueMask;
    cv.Mat? kClose;
    cv.Mat? closed;
    cv.Mat? cardMask;
    cv.Mat? kErode;
    cv.Mat? safeCardMask;
    cv.Mat? tightCrop;
    cv.Mat? tightSafeMask;
    cv.Mat? isolatedCard;
    cv.Mat? lab;
    cv.Mat? kBridge;
    cv.Mat? strictWhiteMask;
    cv.Mat? annotatedCanvas;
    final jpegParams = cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 92]);

    try {
      // 1. Strip mobile black bars
      gray = cv.cvtColor(img, cv.COLOR_BGR2GRAY);
      final (_, actScreen) = cv.threshold(gray, 25, 255, cv.THRESH_BINARY);
      activeScreen = actScreen;

      int minX = img.cols, maxX = -1, minY = img.rows, maxY = -1;
      for (var y = 0; y < img.rows; y++) {
        for (var x = 0; x < img.cols; x++) {
          if (activeScreen.at<int>(y, x) > 0) {
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }

      if (maxX <= minX || maxY <= minY) return null;

      final cropRect = cv.Rect(minX, minY, maxX - minX + 1, maxY - minY + 1);
      crop = img.region(cropRect).clone();
      cropRect.dispose();

      final ch = crop.rows;
      final cw = crop.cols;

      // 2. Extract silhouette and tight crop
      hsv = cv.cvtColor(crop, cv.COLOR_BGR2HSV);
      final lowerBlue = cv.Scalar(95, 40, 30, 0);
      final upperBlue = cv.Scalar(130, 255, 255, 0);
      blueMask = cv.inRangebyScalar(hsv, lowerBlue, upperBlue);

      kClose = cv.getStructuringElement(cv.MORPH_RECT, (15, 15));
      closed = cv.morphologyEx(blueMask, cv.MORPH_CLOSE, kClose);

      final (contours, _) = cv.findContours(closed, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
      final minCardArea = ch * cw * 0.3;
      int bestIdx = -1;
      double maxArea = 0.0;

      for (var i = 0; i < contours.length; i++) {
        final area = cv.contourArea(contours[i]);
        if (area > minCardArea && area > maxArea) {
          maxArea = area;
          bestIdx = i;
        }
      }

      cardMask = cv.Mat.zeros(ch, cw, cv.MatType.CV_8UC1);
      if (bestIdx >= 0) {
        cv.drawContours(cardMask, contours, bestIdx, cv.Scalar(255, 0, 0, 0), thickness: cv.FILLED);
      } else {
        cardMask.setTo(cv.Scalar(255, 0, 0, 0));
      }
      contours.dispose();

      kErode = cv.getStructuringElement(cv.MORPH_ELLIPSE, (5, 5));
      final eroded1 = cv.erode(cardMask, kErode);
      safeCardMask = cv.erode(eroded1, kErode);
      eroded1.dispose();

      int cMinX = cw, cMaxX = -1, cMinY = ch, cMaxY = -1;
      for (var y = 0; y < ch; y++) {
        for (var x = 0; x < cw; x++) {
          if (safeCardMask.at<int>(y, x) == 255) {
            if (x < cMinX) cMinX = x;
            if (x > cMaxX) cMaxX = x;
            if (y < cMinY) cMinY = y;
            if (y > cMaxY) cMaxY = y;
          }
        }
      }

      if (cMaxX <= cMinX || cMaxY <= cMinY) return null;

      final tightRect = cv.Rect(cMinX, cMinY, cMaxX - cMinX + 1, cMaxY - cMinY + 1);
      tightCrop = crop.region(tightRect).clone();
      tightSafeMask = safeCardMask.region(tightRect).clone();
      tightRect.dispose();

      final th = tightCrop.rows;
      final tw = tightCrop.cols;

      isolatedCard = cv.bitwiseAND(tightCrop, tightCrop, mask: tightSafeMask);

      // 3. Lock all 4 corners to smallest detected border thickness
      final lockedBorder = _findUniformSmallestBorder(isolatedCard, tightSafeMask);
      final artX1 = lockedBorder;
      final artY1 = lockedBorder;
      final artX2 = tw - lockedBorder;
      final artY2 = th - lockedBorder;

      final cSpan = math.max(lockedBorder + 6, (math.min(tw, th) * 0.065).round());

      // 4. Strict Pure-White CIELAB Evaluation
      lab = cv.cvtColor(isolatedCard, cv.COLOR_BGR2Lab);

      strictWhiteMask = cv.Mat.zeros(th, tw, cv.MatType.CV_8UC1);

      for (var y = 0; y < th; y++) {
        final inYTop = y < cSpan;
        final inYBottom = y >= th - cSpan;
        if (!inYTop && !inYBottom) continue;

        for (var x = 0; x < tw; x++) {
          final inXLeft = x < cSpan;
          final inXRight = x >= tw - cSpan;
          if (!inXLeft && !inXRight) continue;

          // Inside artwork blocker?
          if (x >= artX1 && x < artX2 && y >= artY1 && y < artY2) continue;

          // Safe mask valid?
          if (tightSafeMask.at<int>(y, x) != 255) continue;

          final vec = lab.at<cv.Vec3b>(y, x);
          final lVal = vec.val1.toDouble();
          final aVal = vec.val2.toDouble();
          final bVal = vec.val3.toDouble();
          final chroma = math.sqrt((aVal - 128.0) * (aVal - 128.0) + (bVal - 128.0) * (bVal - 128.0));

          if (lVal >= whiteLMin && chroma <= whiteChromaMax) {
            strictWhiteMask.set<int>(y, x, 255);
          }
        }
      }

      kBridge = cv.getStructuringElement(cv.MORPH_ELLIPSE, (3, 3));
      final closedWhite = cv.morphologyEx(strictWhiteMask, cv.MORPH_CLOSE, kBridge);
      strictWhiteMask.dispose();
      strictWhiteMask = closedWhite;

      // 5. Connected Components & 2D Patch Filtering
      annotatedCanvas = img.clone();

      final cornersStats = {
        'Top-Left': (rect: cv.Rect(0, 0, cSpan, cSpan), defects: 0, totalArea: 0.0),
        'Top-Right': (rect: cv.Rect(img.cols - cSpan, 0, cSpan, cSpan), defects: 0, totalArea: 0.0),
        'Bottom-Left': (rect: cv.Rect(0, img.rows - cSpan, cSpan, cSpan), defects: 0, totalArea: 0.0),
        'Bottom-Right': (rect: cv.Rect(img.cols - cSpan, img.rows - cSpan, cSpan, cSpan), defects: 0, totalArea: 0.0),
      };

      final cornerResults = <String, ({int defects, double maxArea})>{
        'Top-Left': (defects: 0, maxArea: 0.0),
        'Top-Right': (defects: 0, maxArea: 0.0),
        'Bottom-Left': (defects: 0, maxArea: 0.0),
        'Bottom-Right': (defects: 0, maxArea: 0.0),
      };

      final (defectContours, _) = cv.findContours(strictWhiteMask, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);

      // Offset from tightCrop back to img canvas
      final offX = minX + cMinX;
      final offY = minY + cMinY;

      for (var i = 0; i < defectContours.length; i++) {
        final c = defectContours[i];
        final area = cv.contourArea(c);
        final bRect = cv.boundingRect(c);
        final bw = bRect.width;
        final bh = bRect.height;
        final cX = (bRect.x + bRect.width / 2).round();
        final cY = (bRect.y + bRect.height / 2).round();
        bRect.dispose();

        if (area < minDefectArea) continue;
        if (bw < minThicknessPx || bh < minThicknessPx) continue;

        final boxFill = area / (bw * bh);
        if (boxFill < minBoxFill) continue;

        // Draw defect contour on annotatedCanvas with global offset
        final globalContourPoints = <cv.Point>[];
        for (var p = 0; p < c.length; p++) {
          final pt = c[p];
          globalContourPoints.add(cv.Point(pt.x + offX, pt.y + offY));
        }
        final globalContours = cv.Contours.fromList([globalContourPoints]);
        cv.drawContours(annotatedCanvas, globalContours, 0, cv.Scalar(0, 0, 255, 0), thickness: cv.FILLED);
        globalContours.dispose();

        final cornerKey = cY < th / 2 ? (cX < tw / 2 ? 'Top-Left' : 'Top-Right') : (cX < tw / 2 ? 'Bottom-Left' : 'Bottom-Right');

        final prev = cornerResults[cornerKey]!;
        cornerResults[cornerKey] = (defects: prev.defects + 1, maxArea: math.max(prev.maxArea, area));
      }
      defectContours.dispose();

      final detected = <CornerInspectionData>[];
      final imgW = img.cols;
      final imgH = img.rows;

      for (final entry in cornersStats.entries) {
        final name = entry.key;
        final res = cornerResults[name]!;
        final isDamaged = res.defects > 0;

        final r = entry.value.rect;
        cv.rectangle(annotatedCanvas, r, isDamaged ? cv.Scalar(0, 0, 255, 0) : cv.Scalar(0, 230, 230, 0), thickness: isDamaged ? 2 : 1);

        if (isDamaged) {
          final badgeX = r.x < (imgW / 2) ? r.x + 10 : r.x - 180;
          final badgeY = r.y < (imgH / 2) ? r.y + r.height + 25 : r.y - 10;

          cv.putText(annotatedCanvas, 'CORNER WEAR', cv.Point(badgeX.clamp(5, imgW - 190), badgeY.clamp(20, imgH - 10)), cv.FONT_HERSHEY_SIMPLEX, 0.7, cv.Scalar(0, 0, 255, 0), thickness: 2);
        }

        detected.add(CornerInspectionData(name: name, blobArea: res.maxArea, isDamaged: isDamaged));

        r.dispose();
      }

      final (okAnnotated, annotatedJpeg) = cv.imencode('.jpg', annotatedCanvas, params: jpegParams);
      if (!okAnnotated) return null;

      return (corners: detected, annotatedPhoto: JpegData(annotatedJpeg));
    } finally {
      jpegParams.dispose();
      gray?.dispose();
      activeScreen?.dispose();
      crop?.dispose();
      hsv?.dispose();
      blueMask?.dispose();
      kClose?.dispose();
      closed?.dispose();
      cardMask?.dispose();
      kErode?.dispose();
      safeCardMask?.dispose();
      tightCrop?.dispose();
      tightSafeMask?.dispose();
      isolatedCard?.dispose();
      lab?.dispose();
      kBridge?.dispose();
      strictWhiteMask?.dispose();
      annotatedCanvas?.dispose();
    }
  }

  static int _findUniformSmallestBorder(cv.Mat isolatedCard, cv.Mat safeCardMask) {
    final ch = safeCardMask.rows;
    final cw = safeCardMask.cols;
    final defaultBorder = math.max(4, (math.min(cw, ch) * 0.045).round());

    cv.Mat? grayCard;
    cv.Mat? kIn;
    cv.Mat? innerSafe;
    cv.Mat? brightArt;

    try {
      grayCard = cv.cvtColor(isolatedCard, cv.COLOR_BGR2GRAY);

      final margin = math.max(4, (math.min(ch, cw) * 0.01).round());
      kIn = cv.getStructuringElement(cv.MORPH_RECT, (margin * 2 + 1, margin * 2 + 1));
      innerSafe = cv.erode(safeCardMask, kIn);

      final validPixels = <int>[];
      for (var y = 0; y < ch; y++) {
        for (var x = 0; x < cw; x++) {
          if (innerSafe.at<int>(y, x) == 255) {
            validPixels.add(grayCard.at<int>(y, x));
          }
        }
      }

      if (validPixels.isEmpty) return defaultBorder;

      final validMat = cv.Mat.fromList(validPixels.length, 1, cv.MatType.CV_8UC1, validPixels);
      final (otsuVal, _) = cv.threshold(validMat, 0, 255, cv.THRESH_BINARY | cv.THRESH_OTSU);
      validMat.dispose();

      brightArt = cv.Mat.zeros(ch, cw, cv.MatType.CV_8UC1);
      for (var y = 0; y < ch; y++) {
        for (var x = 0; x < cw; x++) {
          if (innerSafe.at<int>(y, x) == 255 && grayCard.at<int>(y, x) > otsuVal) {
            brightArt.set<int>(y, x, 1);
          }
        }
      }

      // Middle 60% ranges
      final midColStart = (cw * 0.20).round();
      final midColEnd = (cw * 0.80).round();
      final midRowStart = (ch * 0.20).round();
      final midRowEnd = (ch * 0.80).round();

      // Top & Bottom border scan
      final topStart = (ch * 0.025).round();
      final topEnd = (ch * 0.10).round();
      int topH = (ch * 0.045).round();

      for (var y = topStart; y < topEnd; y++) {
        var sum = 0;
        final count = midColEnd - midColStart;
        for (var x = midColStart; x < midColEnd; x++) {
          sum += brightArt.at<int>(y, x);
        }
        if (count > 0 && (sum / count) > 0.20) {
          topH = y;
          break;
        }
      }

      final botStart = (ch * 0.90).round();
      final botEnd = (ch * 0.975).round();
      int botH = ch - (ch * 0.955).round();

      for (var y = botEnd - 1; y >= botStart; y--) {
        var sum = 0;
        final count = midColEnd - midColStart;
        for (var x = midColStart; x < midColEnd; x++) {
          sum += brightArt.at<int>(y, x);
        }
        if (count > 0 && (sum / count) > 0.20) {
          botH = ch - y;
          break;
        }
      }

      // Left & Right border scan
      final leftStart = (cw * 0.025).round();
      final leftEnd = (cw * 0.11).round();
      int leftW = (cw * 0.045).round();

      for (var x = leftStart; x < leftEnd; x++) {
        var sum = 0;
        final count = midRowEnd - midRowStart;
        for (var y = midRowStart; y < midRowEnd; y++) {
          sum += brightArt.at<int>(y, x);
        }
        if (count > 0 && (sum / count) > 0.18) {
          leftW = x;
          break;
        }
      }

      final rightStart = (cw * 0.89).round();
      final rightEnd = (cw * 0.975).round();
      int rightW = cw - (cw * 0.955).round();

      for (var x = rightEnd - 1; x >= rightStart; x--) {
        var sum = 0;
        final count = midRowEnd - midRowStart;
        for (var y = midRowStart; y < midRowEnd; y++) {
          sum += brightArt.at<int>(y, x);
        }
        if (count > 0 && (sum / count) > 0.18) {
          rightW = cw - x;
          break;
        }
      }

      final smallestBorder = [leftW, rightW, topH, botH].reduce(math.min);
      return math.max(4, smallestBorder - safetyBufferPx);
    } finally {
      grayCard?.dispose();
      kIn?.dispose();
      innerSafe?.dispose();
      brightArt?.dispose();
    }
  }
}
