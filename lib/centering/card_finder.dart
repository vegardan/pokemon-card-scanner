import 'dart:math';

import 'package:opencv_dart/opencv_dart.dart' as cv;

const shrinkWidth = 800; //less pixels is faster to work with
const blurKernelSize = 15; //chosen from testing 5/9/15/21, fewer holes while keeping some edge sharpness
const backgroundStripWidth = 20;
const cleanKernelSize = 23; //chosen from testing 11-23
const cornerToleranceFraction = 0.02;
const cardWidthMm = 63; //standard Pokémon card size: 63x88 mm
const cardHeightMm = 88;
const pixelsPerMm = 20; //straightened card = 1260x1760 px
const marginMm = 3;
const backgroundTolerance = 10.0; //how far outside the strip range (per channel) still gets counted as background

cv.Mat resize(cv.Mat image, int width) {
  final height = (image.rows * (width / image.cols)).round();
  final resized = cv.resize(image, (width, height), interpolation: cv.INTER_AREA);
  return resized;
}

cv.Mat blur(cv.Mat image, int kernelSize) {
  final smoothed = cv.gaussianBlur(image, (kernelSize, kernelSize), 0);
  return smoothed;
}

cv.Mat prepForLabCardFinding(cv.Mat image) {
  final shrunkenImage = resize(image, shrinkWidth);
  final smoothedImage = blur(shrunkenImage, blurKernelSize);
  final labColorImage = cv.cvtColor(smoothedImage, cv.COLOR_BGR2Lab);

  shrunkenImage.dispose();
  smoothedImage.dispose();
  return labColorImage;
}

/// average color of one region of the image, disposed after so it doesnt leak memory
cv.Scalar _averageOfRegion(cv.Mat image, cv.Rect rectangle) {
  final region = image.region(rectangle);
  try {
    return cv.mean(region);
  } finally {
    region.dispose();
  }
}

/// background as a range: lowest to highest strip average per channel (including a tolerance)
(cv.Scalar, cv.Scalar) backgroundRange(cv.Mat labImage, int stripWidth) {
  final strips = [
    _averageOfRegion(labImage, cv.Rect(0, 0, labImage.cols, stripWidth)), //top
    _averageOfRegion(labImage, cv.Rect(0, labImage.rows - stripWidth, labImage.cols, stripWidth)), //bottom
    _averageOfRegion(labImage, cv.Rect(0, 0, stripWidth, labImage.rows)), //left
    _averageOfRegion(labImage, cv.Rect(labImage.cols - stripWidth, 0, stripWidth, labImage.rows)), //right
  ];
  final l = strips.map((s) => s.val1);
  final a = strips.map((s) => s.val2);
  final b = strips.map((s) => s.val3);
  const tolerance = backgroundTolerance;
  return (
    cv.Scalar(l.reduce(min) - tolerance, a.reduce(min) - tolerance, b.reduce(min) - tolerance), //lowest
    cv.Scalar(l.reduce(max) + tolerance, a.reduce(max) + tolerance, b.reduce(max) + tolerance), //highest
  );
}

/// card mask: everything that is not inside the background range
cv.Mat cardMaskFromRange(cv.Mat labImage, cv.Scalar low, cv.Scalar high) {
  final backgroundMask = cv.inRangebyScalar(labImage, low, high); //white = inside the range = background
  final cardMask = cv.bitwiseNOT(backgroundMask); //flip so card = white
  backgroundMask.dispose();
  return cardMask;
}

/// cleans the mask: opening removes small specks, closing fills small holes
cv.Mat cleanMask(cv.Mat mask, int kernelSize) {
  //structuring element: a square of kernelSize x kernelSize pixels
  final cleaningKernel = cv.getStructuringElement(cv.MORPH_RECT, (kernelSize, kernelSize));
  //opening = shrink then grow (removes white specks smaller than the cleaning kernel)
  final opened = cv.morphologyEx(mask, cv.MORPH_OPEN, cleaningKernel);
  //closing = grow then shrink (fills black holes smaller than the cleaning kernel)
  final cleaned = cv.morphologyEx(opened, cv.MORPH_CLOSE, cleaningKernel);

  cleaningKernel.dispose();
  opened.dispose();
  return cleaned;
}

/// finds the outline (contour) of the biggest white shape in the mask, which should be the card
/// returns all outlines and the index of the biggest one (-1 if no shapes are found)
(cv.Contours, int) findBiggestContour(cv.Mat cleanedMask) {
  //trace the outer outline of every white shape (holes inside the card are ignored)
  final (contours, hierarchy) = cv.findContours(cleanedMask, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
  hierarchy.dispose();
  //go through every outline to find biggest one
  var biggestIndex = -1;
  var biggestArea = 0.0;
  for (var i = 0; i < contours.length; i++) {
    final area = cv.contourArea(contours[i]);
    if (area > biggestArea) {
      biggestArea = area;
      biggestIndex = i;
    }
  }
  return (contours, biggestIndex);
}

/// simplifies the card outline into a polygon with as few points as possible
/// for a card this should give 4 points (the corners)
cv.VecPoint approximateCorners(cv.VecPoint cardContour, double toleranceFraction) {
  //total length of the outline so the tolerance scales with the cards size in the photo
  final outlineLength = cv.arcLength(cardContour, true);
  //points sticking out less than this from a straight line get removed
  final tolerance = outlineLength * toleranceFraction;
  return cv.approxPolyDP(cardContour, tolerance, true);
}

/// sorts 4 corners into: top left, top right, bottom right and bottom left
List<cv.Point> sortCorners(cv.VecPoint corners) {
  var topLeft = corners[0];
  var topRight = corners[0];
  var bottomRight = corners[0];
  var bottomLeft = corners[0];

  for (var i = 0; i < corners.length; i++) {
    final p = corners[i];
    if (p.x + p.y < topLeft.x + topLeft.y) topLeft = p;
    if (p.x + p.y > bottomRight.x + bottomRight.y) bottomRight = p;
    if (p.y - p.x < topRight.y - topRight.x) topRight = p;
    if (p.y - p.x > bottomLeft.y - bottomLeft.x) bottomLeft = p;
  }
  return [topLeft, topRight, bottomRight, bottomLeft];
}

/// scales corner points found on the shrunken image back up to the full size photo
List<cv.Point> scaleCornersUp(List<cv.Point> corners, double scale) {
  return corners.map((p) => cv.Point((p.x * scale).round(), (p.y * scale).round())).toList();
}

/// straightens card so the centering measurement wont be done on an unleveled card image
cv.Mat straightenCard(cv.Mat image, List<cv.Point> corners) {
  const margin = marginMm * pixelsPerMm;
  const width = cardWidthMm * pixelsPerMm + 2 * margin;
  const height = cardHeightMm * pixelsPerMm + 2 * margin;
  final cornersPhoto = cv.VecPoint.fromList(corners);
  //margin added so background stays visible around the card and no part of the bordre is cut
  final cornersStraightImage = cv.VecPoint.fromList([
    cv.Point(margin, margin), //top left
    cv.Point(width - 1 - margin, margin), //top right
    cv.Point(width - 1 - margin, height - 1 - margin), //botom right
    cv.Point(margin, height - 1 - margin), //bottom left
  ]);
  final transform = cv.getPerspectiveTransform(cornersPhoto, cornersStraightImage);
  final straightCard = cv.warpPerspective(image, transform, (width, height), borderMode: cv.BORDER_REPLICATE);
  cornersPhoto.dispose();
  cornersStraightImage.dispose();
  transform.dispose();
  return straightCard;
}
