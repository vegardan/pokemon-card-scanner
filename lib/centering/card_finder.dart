import 'package:opencv_dart/opencv_dart.dart' as cv;

const blurKernelSize = 15;

cv.Mat grayscale(cv.Mat image) {
  final gray = cv.cvtColor(image, cv.COLOR_BGR2GRAY);
  return gray;
}

cv.Mat resize(cv.Mat image, int width) {
  final height = (image.rows * (width/image.cols)).round();
  final resized = cv.resize(image, (width, height), interpolation: cv.INTER_AREA);
  return resized;
}

cv.Mat blur(cv.Mat image, int kernelSize) {
  final smoothed = cv.gaussianBlur(image, (kernelSize, kernelSize), 0);
  return smoothed;
}

cv.Mat prepForCardFinding(cv.Mat image) {
  final shrunkenImage = resize(image, 800);
  final grayImage = grayscale(shrunkenImage);
  final smoothedImage = blur(grayImage, blurKernelSize);
  return smoothedImage;
}

(double, cv.Mat) seperateCard(cv. Mat prepared) {
  final (otsuValue, mask) = cv.threshold(prepared, 0, 255, cv.THRESH_BINARY | cv.THRESH_OTSU);
  return (otsuValue, mask);
}