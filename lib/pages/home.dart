import 'package:flutter/material.dart';
import 'package:pokemon_card_scanner/models/pokemon_card.dart';
import 'package:pokemon_card_scanner/pages/catalog.dart';
import 'package:pokemon_card_scanner/pages/scan/scan.dart';
import 'package:pokemon_card_scanner/repositories/scanned_card_repository.dart';
import 'package:pokemon_card_scanner/widgets/pokemon_card_grid.dart';
import 'package:pokemon_card_scanner/repositories/pokemon_card_catalog.dart';
import 'package:pokemon_card_scanner/pages/centering_test.dart';
import 'package:image_picker/image_picker.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<ScannedPokemonCard>> _cards;

  @override
  void initState() {
    super.initState();
    _cards = ScannedCardRepository.instance.loadAll();
  }

  Future<void> _scanCard() async {
    final photos = await Navigator.of(context).push<CapturedCardImages>(MaterialPageRoute(builder: (_) => const ScanPage()));
    if (!mounted || photos == null) return;

    //final scannedCard = await ScannedCardRepository.instance.save(photos.front, photos.back, photos.catalogCard);
    // TEMP (Karen): placeholder until Vegard pushes card recognition. Remove before merging.
    final placeholderCard = (await PokemonCardCatalog.load()).first;
    final scannedCard = await ScannedCardRepository.instance.save(photos.front, photos.back, placeholderCard);
    if (!mounted) return;

    setState(() {
      _cards = _cards.then((cards) {
        cards.insert(0, scannedCard);
        return cards;
      });
    });
  }

  Future<void> _pickFromGallery() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CenteringTestPage(initialPhotoBytes: bytes)));
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
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FloatingActionButton.extended(heroTag: 'gallery', onPressed: _pickFromGallery, icon: const Icon(Icons.photo_library_outlined), label: const Text('From gallery'),),
            FloatingActionButton.extended(heroTag: 'scan', onPressed: _scanCard, icon: const Icon(Icons.document_scanner_outlined), label: const Text('Scan card'),),
          ],
        ),
      ),
      body: FutureBuilder<List<ScannedPokemonCard>>(
        future: _cards,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Could not load scanned cards'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final cards = snapshot.data!;

          if (cards.isEmpty) {
            return const Center(child: Text('No cards scanned yet'));
          }

          return PokemonCardGrid(cards: cards, onCardDeleted: _removeCard);
        },
      ),
    );
  }
}
