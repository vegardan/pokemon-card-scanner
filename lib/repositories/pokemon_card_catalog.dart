import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import 'package:pokemon_card_scanner/models/pokemon_card.dart';

class PokemonCardCatalog {
  static const _assetPath = 'assets/data/pokemon_cards.csv';

  const PokemonCardCatalog._();

  static Future<List<CatalogPokemonCard>> load() async {
    final csvText = await rootBundle.loadString(_assetPath);
    final rows = csv.decodeWithHeaders(csvText);

    return rows
        .map((row) {
          String value(String header) => row[header]?.toString().trim() ?? '';

          return CatalogPokemonCard(id: value('id'), imageUrl: _displayImageUrl(value('image_url')), name: value('name'), setName: value('set'));
        })
        .toList(growable: false);
  }

  static List<CatalogPokemonCard> search(List<CatalogPokemonCard> cards, String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return cards;

    return cards
        .where((card) {
          return card.name.toLowerCase().contains(normalizedQuery) || card.setName.toLowerCase().contains(normalizedQuery) || card.id.toLowerCase().contains(normalizedQuery);
        })
        .toList(growable: false);
  }

  static String? _displayImageUrl(String? imageUrl) {
    final trimmedImageUrl = imageUrl?.trim();
    if (trimmedImageUrl == null || trimmedImageUrl.isEmpty) return null;
    if (trimmedImageUrl.endsWith('_hires.png')) {
      return trimmedImageUrl.replaceFirst('_hires.png', '.png');
    }
    return trimmedImageUrl;
  }
}
