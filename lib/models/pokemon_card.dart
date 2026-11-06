import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:pokemon_card_scanner/centering/centering_check.dart';
import 'package:pokemon_card_scanner/models/analysis/estimated_grade.dart';
import 'package:pokemon_card_scanner/models/crease_analysis.dart';

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
  final CenteringResult? frontCentering;
  final CenteringResult? backCentering;
  final int? estimatedGrading;
  final EstimatedGrade? gradeReport;
  final String frontImagePath;
  final String backImagePath;
  final DateTime createdAt;
  final CreaseAnalysis backCreases;

  const ScannedPokemonCard({
    required this.catalogCard,
    required this.scanId,
    this.frontCentering,
    this.backCentering,
    required this.estimatedGrading,
    this.gradeReport,
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
