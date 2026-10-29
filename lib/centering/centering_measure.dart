import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'dart:math';
import 'dart:typed_data';
import 'package:pokemon_card_scanner/centering/card_finder.dart';

const outerEdgeThreshold = 40.0; //color difference: background to card (outer border edge)
const innerEdgeThreshold = 30.0; //color difference: border to artwork (inner border egde)
const maxBorderMm = 8.0; //never search deeper than this into the card (a real border is only a few mms)
const lineStep = 4; //use every 4th row/column (faster than checking every single pixel row)
const changeMustLastPixels = 10; //a change must last aprox 0.5 mm, longer than printed text strokes in the border
const borderMatchThreshold = 60.0; //how close a color must be to the card's border color to count as border
const maxShadowMm = 2.0; //never skip more than this mms between background and border (want to ignore shadwos)
const backgroundSamplePixels = 20; //first 1mm of a line is background (inside the margin of 3mm)
const skipPastEdgePixels = 6; //edge itself is blurry/not clean color so it is skipped
const borderSampleLengthPixels = 10; //0.5 mm of border is averaged to get border color


//a straight line along one edge: edge position = tilt * position along the side + edgeAtStart (y = ax + b)
class EdgeLine {
  final double tilt; //how much the edge moves per pixel along the side (0 = perfectly straight)
  final double edgeAtStart; //where the edge is at position 0
  const EdgeLine(this.tilt, this.edgeAtStart);
  //where the edge is at a given position along the side
  double edgeAt(double position) => tilt * position + edgeAtStart;
}

//one side of the card: border width in mm + the outer and inner edge lines for drawing
class SideEdges {
  final double widthMm;
  final EdgeLine outer;
  final EdgeLine inner;
  const SideEdges(this.widthMm, this.outer, this.inner);
}

//the result for all four sides
class BorderMeasurement {
  final SideEdges left, right, top, bottom;
  const BorderMeasurement(this.left, this.right, this.top, this.bottom);
}

//how different one pixel is from a color: the differences in l, a and b added together
double _difference(Uint8List pixels, int pixelStart, List<double> color) =>
    (pixels[pixelStart] - color[0]).abs() + (pixels[pixelStart + 1] - color[1]).abs() + (pixels[pixelStart + 2] - color[2]).abs();

//find average color of the pixels (lab) from one point to another along a line
List<double> _averageColor(Uint8List pixels, List<int> line, int from, int to) {
  var l = 0.0, a = 0.0, b = 0.0;
  for (var i = from; i < to; i++) {
    l += pixels[line[i]];
    a += pixels[line[i] + 1];
    b += pixels[line[i] + 2];
  }
  final n = to - from;
  return [l / n, a / n, b / n];
}

//finds where the color first stops being like the given color and stays different for changeMustLastPixels in a row
int? _firstLastingChange(Uint8List pixels, List<int> line, int start, List<double> color, double threshold) {
  var pixelsInARow = 0;
  for (var i = start; i < line.length; i++) {
    if (_difference(pixels, line[i], color) > threshold) {
      pixelsInARow++;
      if (pixelsInARow == changeMustLastPixels) return i - changeMustLastPixels + 1;
    } else {
      pixelsInARow = 0;
    }
  }
  return null;
}

//opposite of _firstLastingChange: finds where the color first becomes like the given color, and stays that way for changeMustLastPixels in a row
int? _firstLastingMatch(Uint8List pixels, List<int> line, int start, List<double> color, double threshold) {
  var pixelsInARow = 0;
  for (var i = start; i < line.length; i++) {
    if (_difference(pixels, line[i], color) < threshold) {
      pixelsInARow++;
      if (pixelsInARow == changeMustLastPixels) return i - changeMustLastPixels + 1;
    } else {
      pixelsInARow = 0;
    }
  }
  return null;
}

//finds the border color on one line (null if no card edge is found)
List<double>? _borderColorOnLine(Uint8List pixels, List<int> line) {
  final background = _averageColor(pixels, line, 0, backgroundSamplePixels);
  final outerEdge = _firstLastingChange(pixels, line, backgroundSamplePixels, background, outerEdgeThreshold);
  //no edge found or the line ends before the border can be sampled
  if (outerEdge == null || outerEdge + skipPastEdgePixels + borderSampleLengthPixels >= line.length) return null;
  return _averageColor(pixels, line, outerEdge + skipPastEdgePixels, outerEdge + skipPastEdgePixels + borderSampleLengthPixels);
}

//finds the outer and inner border edge on one line
//outer edge is where the card border color starts so something like a shadow in between is skipped
(int, int)? _edgesOnLine(Uint8List pixels, List<int> line, List<double> cardBorderColor) {
  final maxBorder = (maxBorderMm * pixelsPerMm).round();
  final maxSkip = (maxShadowMm * pixelsPerMm).round();
  final background = _averageColor(pixels, line, 0, backgroundSamplePixels);
  final backgroundEnds = _firstLastingChange(pixels, line, backgroundSamplePixels, background, outerEdgeThreshold);
  if (backgroundEnds == null) return null;

  final outerEdge = _firstLastingMatch(pixels, line, backgroundEnds, cardBorderColor, borderMatchThreshold);
  //no border color found or skipped too far (more than a shadow) or the line ends too soon
  if (outerEdge == null || outerEdge - backgroundEnds > maxSkip || outerEdge + skipPastEdgePixels + borderSampleLengthPixels >= line.length) return null;

  final borderColor = _averageColor(pixels, line, outerEdge + skipPastEdgePixels, outerEdge + skipPastEdgePixels + borderSampleLengthPixels);
  final innerEdge = _firstLastingChange(pixels, line, outerEdge + skipPastEdgePixels + borderSampleLengthPixels, borderColor, innerEdgeThreshold);
  //no inner edge found or the border is unrealistically wide
  if (innerEdge == null || innerEdge - outerEdge > maxBorder) return null;

  return (outerEdge, innerEdge);
}

//median of list, so a few wrong values dont affect it
double _median(List<double> values) {
  final sorted = List<double>.from(values);
  sorted.sort();
  return sorted[sorted.length ~/ 2];
}

//list of pixel positions along one line, starting at (startX, startY) and moving one step in the given direction each time
List<int> _lineInward(int startX, int startY, int stepX, int stepY, int length, int imageWidth) {
  final line = <int>[];
  for (var i = 0; i < length; i++) {
    final x = startX + i * stepX;
    final y = startY + i * stepY;
    line.add((y * imageWidth + x) * 3); //skip y rows, x pixels, 3 numbers (l, a, b) per pixel
  }
  return line;
}

//finds the outer and inner border edge on all four sides of the straightened card
BorderMeasurement? measureBorders(cv.Mat straightCard) {
  final smoothCard = blur(straightCard, 5); //light blur for noise, full size image is sharp
  final labCard = cv.cvtColor(smoothCard, cv.COLOR_BGR2Lab);
  final pixels = labCard.data;
  final width = labCard.cols;
  final height = labCard.rows;
  final lineLength = ((marginMm + maxBorderMm + 1) * pixelsPerMm).round(); //background margin + widest border + 1 mm extra

  //every line: which side theyre on, which row/column and their pixels from the outside in
  //only the middle 60% of each side, away from the rounded corners
  final lines = <(String, int, List<int>)>[];
  for (var y = (height * 0.2).round(); y < height * 0.8; y += lineStep) {
    lines.add(('L', y, _lineInward(0, y, 1, 0, lineLength, width))); //from left edge going right
    lines.add(('R', y, _lineInward(width - 1, y, -1, 0, lineLength, width))); //from right edge going left
  }
  for (var x = (width * 0.2).round(); x < width * 0.8; x += lineStep) {
    lines.add(('T', x, _lineInward(x, 0, 0, 1, lineLength, width))); //from top edge going down
    lines.add(('B', x, _lineInward(x, height - 1, 0, -1, lineLength, width))); //from bottom edge going up
  }

  //card border color = median of the border color found on every line (so a few lines with a shadow dont matter)
  final lValues = <double>[];
  final aValues = <double>[];
  final bValues = <double>[];
  for (final (_, _, line) in lines) {
    final color = _borderColorOnLine(pixels, line);
    if (color == null) continue;
    lValues.add(color[0]);
    aValues.add(color[1]);
    bValues.add(color[2]);
  }
  if (lValues.isEmpty) {
    smoothCard.dispose();
    labCard.dispose();
    return null;
  }
  final cardBorderColor = [_median(lValues), _median(aValues), _median(bValues)];

  //find the edges on every line sorted by side
  final positions = {'L': <double>[], 'R': <double>[], 'T': <double>[], 'B': <double>[]};
  final outerEdges = {'L': <double>[], 'R': <double>[], 'T': <double>[], 'B': <double>[]};
  final innerEdges = {'L': <double>[], 'R': <double>[], 'T': <double>[], 'B': <double>[]};
  for (final (side, position, line) in lines) {
    final edges = _edgesOnLine(pixels, line, cardBorderColor);
    if (edges == null) continue;
    final (outerEdge, innerEdge) = edges;
    positions[side]!.add(position.toDouble());
    outerEdges[side]!.add(outerEdge.toDouble());
    innerEdges[side]!.add(innerEdge.toDouble());
  }

  smoothCard.dispose();
  labCard.dispose();

  //a side without any usable lines cant be measured
  for (final side in ['L', 'R', 'T', 'B']) {
    if (outerEdges[side]!.isEmpty) return null;
  }

  return BorderMeasurement(
    _measureSide(positions['L']!, outerEdges['L']!, innerEdges['L']!),
    _measureSide(positions['R']!, outerEdges['R']!, innerEdges['R']!),
    _measureSide(positions['T']!, outerEdges['T']!, innerEdges['T']!),
    _measureSide(positions['B']!, outerEdges['B']!, innerEdges['B']!),
  );
}

//turns all lines on one side into one border width (the median) + straight lines to draw
SideEdges _measureSide(List<double> positions, List<double> outerEdges, List<double> innerEdges) {
  //border width per line, works even if the card is tilted cause both edges shift equally
  final widthsMm = <double>[];
  for (var i = 0; i < outerEdges.length; i++) {
    widthsMm.add((innerEdges[i] - outerEdges[i]) / pixelsPerMm);
  }
  final medianWidth = _median(widthsMm);

  //lines far from the median hit something wrong (shadow etc) so theyre left out of the drawn lines
  final keptPositions = <double>[];
  final keptOuter = <double>[];
  final keptInner = <double>[];
  for (var i = 0; i < widthsMm.length; i++) {
    if ((widthsMm[i] - medianWidth).abs() < 0.5) {
      keptPositions.add(positions[i]);
      keptOuter.add(outerEdges[i]);
      keptInner.add(innerEdges[i]);
    }
  }
  return SideEdges(medianWidth, _fitLine(keptPositions, keptOuter), _fitLine(keptPositions, keptInner));
}

//best fitting straight line through the points
EdgeLine _fitLine(List<double> positions, List<double> edges) {
  final n = positions.length;
  final averagePosition = positions.reduce((a, b) => a + b) / n;
  final averageEdge = edges.reduce((a, b) => a + b) / n;
  var covarianceSum = 0.0;
  var varianceSum = 0.0;
  for (var i = 0; i < n; i++) {
    covarianceSum += (positions[i] - averagePosition) * (edges[i] - averageEdge);
    varianceSum += (positions[i] - averagePosition) * (positions[i] - averagePosition);
  }
  final covariance = covarianceSum / n; //how much edges and positions vary together
  final variance = varianceSum / n; //how spread out the positions are
  final tilt = varianceSum == 0 ? 0.0 : covariance / variance; //in y = ax + b, a = cov(x,y)/var(x)
  return EdgeLine(tilt, averageEdge - tilt * averagePosition);
}

//draws the outer edges green and inner edges red on the straightened card
void drawBorderLines(cv.Mat card, BorderMeasurement measurement) {
  final width = card.cols;
  final height = card.rows;
  cv.Point point(double x, double y) => cv.Point(x.round(), y.round());
  void draw(String side, EdgeLine line, cv.Scalar color) {
    switch (side) {
      case 'L':
        cv.line(card, point(line.edgeAt(0), 0), point(line.edgeAt(height - 1.0), height - 1.0), color, thickness: 3);
      case 'R':
        cv.line(card, point(width - 1 - line.edgeAt(0), 0), point(width - 1 - line.edgeAt(height - 1.0), height - 1.0), color, thickness: 3);
      case 'T':
        cv.line(card, point(0, line.edgeAt(0)), point(width - 1.0, line.edgeAt(width - 1.0)), color, thickness: 3);
      case 'B':
        cv.line(card, point(0, height - 1 - line.edgeAt(0)), point(width - 1.0, height - 1 - line.edgeAt(width - 1.0)), color, thickness: 3);
    }
  }
  for (final (side, edges) in [('L', measurement.left), ('R', measurement.right), ('T', measurement.top), ('B', measurement.bottom)]) {
    final green = cv.Scalar(0, 255, 0);
    final red = cv.Scalar(0, 0, 255);
    draw(side, edges.outer, green);
    draw(side, edges.inner, red);
  }
}

//the bigger sides share in %, so for example 2 mm and 3 mm is 60 (= 60/40)
double biggerSide(double a, double b) => max(a, b) / (a + b) * 100;

//PSA centering limits = max share of the bigger side per grade.
const psaFrontLimits = {10: 55.0, 9: 60.0, 8: 65.0, 7: 70.0, 6: 80.0, 5: 85.0, 3: 90.0}; //exculded 4, 2 and 1 since 4 = 5 and 2,1 = 3
const psaBackLimits = {10: 75.0, 9: 90.0}; //excluded 8-1 since 8-1 = 9

//Best PSA grade the centering allows (a ceiling, not a grade) or null if worse than all limits
int? centeringCeiling(BorderMeasurement measurement, {required bool front}) {
  final worst = max(biggerSide(measurement.left.widthMm, measurement.right.widthMm), biggerSide(measurement.top.widthMm, measurement.bottom.widthMm));
  for (final limit in (front ? psaFrontLimits : psaBackLimits).entries) {
    if (worst < limit.value) return limit.key;
  }
  return null;
}

//combined centering grade for the whole card: the worst of the front and back grade
int? combinedCeiling(int? frontGrade, int? backGrade) {
  if (frontGrade == null || backGrade == null) return null; //one side is worse than all limits
  return min(frontGrade, backGrade);
}