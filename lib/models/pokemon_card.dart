import 'dart:io';

import 'package:pokemon_card_scanner/models/crease_analysis.dart';
import 'package:pokemon_card_scanner/models/jpeg_data.dart';

import 'package:flutter/widgets.dart';

/// Complete front/back scan, including the analysis of this exact back image.
typedef CompletedCardScan = ({
  JpegData front,
  JpegData back,
  CatalogPokemonCard catalogCard,
  CreaseAnalysis backCreases,
});

abstract interface class PokemonCard {
  CatalogPokemonCard get catalogCard;
}

final class CatalogPokemonCard implements PokemonCard {
  final String id;
  final String? imageUrl;
  final String name;
  final String setName;

  const CatalogPokemonCard({
    required this.id,
    required this.name,
    required this.setName,
    this.imageUrl,
  });

  @override
  CatalogPokemonCard get catalogCard => this;
}

final class ScannedPokemonCard implements PokemonCard {
  @override
  final CatalogPokemonCard catalogCard;
  final int scanId;
  final int? estimatedGrading;
  final String frontImagePath;
  final String backImagePath;
  final DateTime createdAt;
  final CreaseAnalysis backCreases;

  const ScannedPokemonCard({
    required this.catalogCard,
    required this.scanId,
    required this.estimatedGrading,
    required this.frontImagePath,
    required this.backImagePath,
    required this.createdAt,
    this.backCreases = CreaseAnalysis.unavailable,
  }) : assert(
         estimatedGrading == null ||
             (estimatedGrading >= 1 && estimatedGrading <= 10),
         'estimatedGrading must be between 1 and 10',
       );

  FileImage get frontImage => FileImage(File(frontImagePath));

  FileImage get backImage => FileImage(File(backImagePath));
}
