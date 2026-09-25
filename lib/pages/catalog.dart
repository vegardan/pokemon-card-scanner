import 'package:flutter/material.dart';
import 'package:pokemon_card_scanner/models/pokemon_card.dart';
import 'package:pokemon_card_scanner/repositories/pokemon_card_catalog.dart';
import 'package:pokemon_card_scanner/widgets/pokemon_card_grid.dart';

class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  late final Future<List<CatalogPokemonCard>> _catalog;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _catalog = PokemonCardCatalog.load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Card catalog')),
      body: FutureBuilder<List<CatalogPokemonCard>>(
        future: _catalog,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Could not load the card catalog.',
                  style: TextStyle(color: colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final catalogCards = snapshot.data;
          if (catalogCards == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final cards = PokemonCardCatalog.search(catalogCards, _searchController.text);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(border: const OutlineInputBorder(), hintText: 'Search through ${catalogCards.length} cards', prefixIcon: const Icon(Icons.search)),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Expanded(child: PokemonCardGrid(cards: cards)),
            ],
          );
        },
      ),
    );
  }
}
