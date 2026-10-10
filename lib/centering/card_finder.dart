import 'package:opencv_dart/opencv_dart.dart' as cv;

const shrinkWidth = 800; //less pixels is faster to work with
const blurKernelSize = 15; //chosen from testing 5/9/15/21, fewer holes while keeping some edge sharpness
const double fixedCutOffThreshold = 25; //chosen after testing 25/35/45 in different lightings
const backgroundStripWidth = 20;
const cleanKernelSize = 23; //chosen from testing 11-23

cv.Mat resize(cv.Mat image, int width) {
  final height = (image.rows * (width/image.cols)).round();
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
  return labColorImage;
}

/// The background color = the average Lab color of a thin strip
/// around the photo's edge (assuming the card lies in the middle of a plain background not touching edges)
cv.Scalar backgroundColor(cv.Mat labImage, int stripWidth) {
  //averge color of each rectangle strip around photo edge
  final top = cv.mean(labImage.region(cv.Rect(0, 0, labImage.cols, stripWidth)));
  final bottom = cv.mean(labImage.region(cv.Rect(0, labImage.rows - stripWidth, labImage.cols, stripWidth)));
  final left = cv.mean(labImage.region(cv.Rect(0, 0, stripWidth, labImage.rows)));
  final right = cv.mean(labImage.region(cv.Rect(labImage.cols - stripWidth, 0, stripWidth, labImage.rows)));

  //val1, val2, val3 = L, a, b channels. Average the four strips per channel
  final l = (top.val1 + bottom.val1 + left.val1 + right.val1)/4;
  final a = (top.val2 + bottom.val2 + left.val2 + right.val2)/4;
  final b = (top.val3 + bottom.val3 + left.val3 + right.val3)/4;
  return cv.Scalar(l, a, b);
}

/// How different each pixel is from the background color
/// Bright = different from the background (the card), dark = background
cv.Mat differenceFromBackground(cv.Mat labImage, cv.Scalar backgroundLab) {
  //an image the same size as lab filled with the background color
  final backgroundImage = cv.Mat.fromScalar(labImage.rows, labImage.cols, labImage.type, backgroundLab);
  //per pixel and per channel: how far from the background
  final channelDifferences = cv.absDiff(labImage, backgroundImage);
  //split into L, a, b differences and add them into one gray image. values capped at 255
  final channels = cv.split(channelDifferences);
  final totalDifferences = cv.add(cv.add(channels[0], channels[1]), channels[2]);

  backgroundImage.dispose();
  channelDifferences.dispose();
  return totalDifferences;
}

/// Mask = every pixel that differs from the background by more than the cutoff
cv.Mat seperateByFixedThreshold(cv.Mat differenceImage, double cutoff) {
  final (_, mask) = cv.threshold(differenceImage, cutoff, 255, cv.THRESH_BINARY);
  return mask;
}

/// Cleans the mask: opening removes small specks, closing fills small holes
cv.Mat cleanMask(cv.Mat mask, int kernelSize) {
  //structuring element: a square of kernelSize x kernelSize pixels
  final cleaningKernel = cv.getStructuringElement(cv.MORPH_RECT, (kernelSize, kernelSize));
  //opening = erode then dilate (removes white specks smaller than the cleaning kernel)
  final opened = cv.morphologyEx(mask, cv.MORPH_OPEN, cleaningKernel);
  //closing = dilate then erode (fills black holes smaller than the cleaning kernel)
  final cleaned = cv.morphologyEx(opened, cv.MORPH_CLOSE, cleaningKernel);

  cleaningKernel.dispose();
  opened.dispose();
  return cleaned;
}