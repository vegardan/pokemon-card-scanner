import 'dart:typed_data';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:pokemon_card_scanner/centering/card_finder.dart';
import 'package:pokemon_card_scanner/centering/centering_measure.dart';

/// centering result for one photo (front or back of the card)
class CenteringResult {
  final double leftMm, rightMm, topMm, bottomMm; //border widths
  final double leftRight; //bigger side's share in %, for example 56 means 56/44
  final double topBottom;
  final int? grade; //best PSA grade the centering allows, null if worse than all limits
  final Uint8List analysisImage; //straightened card with the measured border lines drawn

  const CenteringResult(this.leftMm, this.rightMm, this.topMm, this.bottomMm, this.leftRight, this.topBottom, this.grade, this.analysisImage);
}

/// finds the card in the photo, straightens it and measures the borders
/// returns null if the card cant be measured reliably (the user should retake with a better background or light)
CenteringResult? checkCentering(cv.Mat photo, {required bool front}) {
  //find the card on a shrunken copy of the photo
  final labImage = prepForLabCardFinding(photo);
  final (backgroundLow, backgroundHigh) = backgroundRange(labImage, backgroundStripWidth);
  final mask = cardMaskFromRange(labImage, backgroundLow, backgroundHigh);
  final cleanedMask = cleanMask(mask, cleanKernelSize);
  final (contours, cardIndex) = findBiggestContour(cleanedMask);
  labImage.dispose();
  mask.dispose();
  cleanedMask.dispose();

  //no card shape found
  if (cardIndex < 0) {
    contours.dispose();
    return null;
  }

  //not exactly 4 corners means the outline isn't a clean card shape
  final polygon = approximateCorners(contours[cardIndex], cornerToleranceFraction);
  if (polygon.length != 4) {
    polygon.dispose();
    contours.dispose();
    return null;
  }

  //straighten the full size photo using the corners scaled back up
  final corners = sortCorners(polygon);
  final scale = photo.cols / shrinkWidth;
  final straightCard = straightenCard(photo, scaleCornersUp(corners, scale));
  polygon.dispose();
  contours.dispose();

  //measure the borders, null if a side couldnt be measured
  final measurement = measureBorders(straightCard);
  if (measurement == null) {
    straightCard.dispose();
    return null;
  }

  drawBorderLines(straightCard, measurement);
  final (encoded, analysisImage) = cv.imencode('.jpg', straightCard);
  straightCard.dispose();
  if (!encoded) return null;

  return CenteringResult(
    measurement.left.widthMm,
    measurement.right.widthMm,
    measurement.top.widthMm,
    measurement.bottom.widthMm,
    biggerSide(measurement.left.widthMm, measurement.right.widthMm),
    biggerSide(measurement.top.widthMm, measurement.bottom.widthMm),
    centeringCeiling(measurement, front: front),
    analysisImage,
  );
}