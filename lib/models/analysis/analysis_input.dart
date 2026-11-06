import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:pokemon_card_scanner/centering/centering_check.dart';
import 'package:pokemon_card_scanner/models/crease_analysis.dart';
import 'package:pokemon_card_scanner/models/jpeg_data.dart';
import 'package:pokemon_card_scanner/models/pokemon_card.dart';

class AnalysisInput {
  final cv.Mat frontImage;
  final cv.Mat backImage;
  final CatalogPokemonCard catalogCard;
  final JpegData? frontPhoto;
  final JpegData? backPhoto;
  final CreaseAnalysis? backCreases;
  final CenteringResult? frontCentering;
  final CenteringResult? backCentering;

  const AnalysisInput({
    required this.frontImage,
    required this.backImage,
    required this.catalogCard,
    this.frontPhoto,
    this.backPhoto,
    this.backCreases,
    this.frontCentering,
    this.backCentering,
  });
}
