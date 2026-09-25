import 'package:flutter/widgets.dart';

abstract interface class PokemonCard {
  CatalogPokemonCard? get catalogCard;
}

final class CatalogPokemonCard implements PokemonCard {
  final String id;
  final String? imageUrl;
  final String name;
  final String setName;

  const CatalogPokemonCard({required this.id, required this.name, required this.setName, this.imageUrl});

  @override
  CatalogPokemonCard get catalogCard => this;
}

final class ScannedPokemonCard implements PokemonCard {
  @override
  final CatalogPokemonCard? catalogCard;
  final int scanId;
  final int? estimatedGrading;
  final List<ImageProvider> capturedImages;
  final List<String> capturedImagePaths;
  final DateTime createdAt;

  const ScannedPokemonCard({required this.catalogCard, required this.scanId, required this.estimatedGrading, required this.capturedImages, required this.capturedImagePaths, required this.createdAt})
    : assert(estimatedGrading == null || (estimatedGrading >= 1 && estimatedGrading <= 10), 'estimatedGrading must be between 1 and 10'),
      assert(capturedImages.length > 0, 'capturedImages must contain at least one image'),
      assert(capturedImages.length == capturedImagePaths.length, 'capturedImages and capturedImagePaths must match');
}
