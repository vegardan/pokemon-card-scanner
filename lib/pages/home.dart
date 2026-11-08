import 'package:flutter/material.dart';
import 'package:pokemon_card_scanner/centering/centering_check.dart';
import 'package:pokemon_card_scanner/models/crease_analysis.dart';
import 'package:pokemon_card_scanner/models/jpeg_data.dart';
import 'package:pokemon_card_scanner/models/pokemon_card.dart';
import 'package:pokemon_card_scanner/pages/card_details.dart';
import 'package:pokemon_card_scanner/pages/catalog.dart';
import 'package:pokemon_card_scanner/pages/grading/card_grading_page.dart';
import 'package:pokemon_card_scanner/pages/scan/scan.dart';
import 'package:pokemon_card_scanner/pages/scan/scan_guide.dart';
import 'package:pokemon_card_scanner/repositories/app_preferences.dart';
import 'package:pokemon_card_scanner/repositories/pokemon_card_catalog.dart';
import 'package:pokemon_card_scanner/repositories/scanned_card_repository.dart';
import 'package:pokemon_card_scanner/widgets/pokemon_card_grid.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<ScannedPokemonCard>> _cards;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cards = ScannedCardRepository.instance.loadAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _scanCard() async {
    final skipGuide = await AppPreferences.skipScanGuide();

    if (!mounted) return;

    if (!skipGuide) {
      final ready = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const ScanGuidePage(showSkipOption: true)));

      if (!mounted || ready != true) return;
    }

    final scanResult = await Navigator.of(context)
        .push<({JpegData front, JpegData back, CatalogPokemonCard catalogCard, CenteringResult? frontCentering, CenteringResult? backCentering, CreaseAnalysis backCreases})>(
          MaterialPageRoute(builder: (_) => const ScanPage()),
        );

    if (!mounted || scanResult == null) return;

    final scannedCard = await Navigator.of(context).push<ScannedPokemonCard>(
      MaterialPageRoute(
        builder: (_) => CardGradingPage(
          frontPhoto: scanResult.front,
          backPhoto: scanResult.back,
          catalogCard: scanResult.catalogCard,
          frontCentering: scanResult.frontCentering,
          backCentering: scanResult.backCentering,
          backCreases: scanResult.backCreases,
        ),
      ),
    );

    if (!mounted || scannedCard == null) return;

    setState(() {
      _cards = _cards.then((cards) {
        cards.insert(0, scannedCard);
        return cards;
      });
    });

    final deleted = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => OwnedCardDetailsPage(scannedCard)));
    if (mounted && deleted == true) _removeCard(scannedCard);
  }

  void _removeCard(ScannedPokemonCard deletedCard) {
    setState(() {
      _cards = _cards.then((cards) {
        cards.removeWhere((card) => card.scanId == deletedCard.scanId);
        return cards;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [Icon(Icons.catching_pokemon_outlined), SizedBox(width: 6), Text('Pokémon Card Scanner')]),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_outlined),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CatalogPage()));
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(heroTag: 'scan_card', onPressed: _scanCard, icon: const Icon(Icons.document_scanner_outlined), label: const Text('Scan card')),
      body: FutureBuilder<List<ScannedPokemonCard>>(
        future: _cards,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Could not load scanned cards'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allCards = snapshot.data!;
          final cards = PokemonCardCatalog.search(allCards, _searchController.text);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(border: const OutlineInputBorder(), hintText: 'Search through ${allCards.length} cards', prefixIcon: const Icon(Icons.search)),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Expanded(
                child: allCards.isEmpty
                    ? const Center(child: Text('No cards scanned yet'))
                    : cards.isEmpty
                    ? const Center(child: Text('No cards match your search'))
                    : PokemonCardGrid(cards: cards, onCardDeleted: _removeCard),
              ),
            ],
          );
        },
      ),
    );
  }
}
