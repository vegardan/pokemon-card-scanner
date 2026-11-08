import 'package:pokemon_card_scanner/models/jpeg_data.dart';

class ImageQualityResult {
  final bool isBlurry;
  final bool hasGlare;
  final double blurScore;
  final double glarePercentage;
  final JpegData rawPhoto;
  final JpegData? annotatedGlarePhoto;

  const ImageQualityResult({required this.isBlurry, required this.hasGlare, required this.blurScore, required this.glarePercentage, required this.rawPhoto, this.annotatedGlarePhoto});

  bool get isValid => !isBlurry && !hasGlare;

  String get title {
    if (isBlurry && hasGlare) return 'Photo is blurry and contains glare';
    if (isBlurry) return 'Photo is blurry';
    if (hasGlare) return 'Glare detected on card';
    return 'Good quality';
  }

  String get description {
    if (isBlurry && hasGlare) {
      return 'Hold your phone steady so the camera can focus, and retake the photo without glare.';
    }
    if (isBlurry) {
      return 'Hold your phone steady and allow the camera a moment to focus on the card details.';
    }
    if (hasGlare) {
      return 'Bright reflections are covering card details. Please retake the photo without glare.';
    }
    return '';
  }
}
