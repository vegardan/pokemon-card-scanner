import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:pokemon_card_scanner/models/pokemon_card.dart';
import 'package:pokemon_card_scanner/repositories/scanned_card_repository.dart';
import 'package:pokemon_card_scanner/widgets/image_carousel/image_carousel.dart';

class CardDetailsPage extends StatelessWidget {
  final PokemonCard card;

  const CardDetailsPage(this.card, {super.key});

  @override
  Widget build(BuildContext context) {
    final catalogCard = card.catalogCard;
    final scannedCard = card is ScannedPokemonCard ? card as ScannedPokemonCard : null;
    final title = catalogCard.name;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [if (scannedCard != null) IconButton(tooltip: 'Delete card', icon: const Icon(Icons.delete_outline), onPressed: () => _deleteCard(context, scannedCard))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Center(child: _CardImageCarousel(card: card)),
          const SizedBox(height: 24),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          _DetailRow(label: 'Set', value: catalogCard.setName),
          _DetailRow(label: 'Card ID', value: catalogCard.id),
          if (scannedCard != null) ...[
            _DetailRow(label: 'Estimated grade', value: scannedCard.estimatedGrading?.toString() ?? 'Not available'),
            _DetailRow(label: 'Scanned', value: _formatDate(scannedCard.createdAt)),
          ],
          if (scannedCard != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CardDetailsPage(catalogCard))),
              icon: const Icon(Icons.collections_bookmark_outlined),
              label: const Text('View in catalog'),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} ${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }

  Future<void> _deleteCard(BuildContext context, ScannedPokemonCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete card?'),
        content: const Text('This will permanently delete the scan and its captured images.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ScannedCardRepository.instance.delete(card);
      if (context.mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not delete the card. Please try again.')));
    }
  }
}

class _CardImageCarousel extends StatelessWidget {
  final PokemonCard card;

  const _CardImageCarousel({required this.card});

  @override
  Widget build(BuildContext context) {
    final imageUrl = card.catalogCard.imageUrl;
    final scannedCard = card is ScannedPokemonCard ? card as ScannedPokemonCard : null;
    final items = <ImageCarouselItem>[
      if (scannedCard != null) ...[ImageCarouselItem(imageProvider: scannedCard.frontImage, semanticLabel: 'Front'), ImageCarouselItem(imageProvider: scannedCard.backImage, semanticLabel: 'Back')],
    ];
    if (items.isEmpty) {
      items.add(
        ImageCarouselItem(
          imageProvider: imageUrl != null && imageUrl.isNotEmpty ? CachedNetworkImageProvider(imageUrl) : const AssetImage('assets/pokemon_back_monochrome.png'),
          semanticLabel: card.catalogCard.name,
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: LayoutBuilder(
        builder: (context, constraints) => ImageCarousel(items: items, height: constraints.maxWidth * 3.5 / 2.5, fit: BoxFit.contain, showLabels: scannedCard != null),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
