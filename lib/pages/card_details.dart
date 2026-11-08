import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:pokemon_card_scanner/controllers/grading_profile_controller.dart';
import 'package:pokemon_card_scanner/models/pokemon_card.dart';
import 'package:pokemon_card_scanner/pages/grade_overview.dart';
import 'package:pokemon_card_scanner/repositories/scanned_card_repository.dart';
import 'package:pokemon_card_scanner/vision/card_constants.dart';
import 'package:pokemon_card_scanner/widgets/grading/grade_badge.dart';
import 'package:pokemon_card_scanner/widgets/image_carousel/image_carousel.dart';

class OwnedCardDetailsPage extends StatelessWidget {
  final ScannedPokemonCard card;

  const OwnedCardDetailsPage(this.card, {super.key});

  @override
  Widget build(BuildContext context) => CardDetailsPage(card);
}

class CatalogCardDetailsPage extends StatelessWidget {
  final CatalogPokemonCard card;

  const CatalogCardDetailsPage(this.card, {super.key});

  @override
  Widget build(BuildContext context) => CardDetailsPage(card);
}

class CardDetailsPage extends StatelessWidget {
  final PokemonCard card;

  const CardDetailsPage(this.card, {super.key});

  @override
  Widget build(BuildContext context) {
    final catalogCard = card.catalogCard;
    final scannedCard = card is ScannedPokemonCard ? card as ScannedPokemonCard : null;
    final title = catalogCard.name;

    return ListenableBuilder(
      listenable: GradingProfileController.instance,
      builder: (context, _) {
        final profile = GradingProfileController.instance.value;
        final front = scannedCard?.frontCentering;
        final back = scannedCard?.backCentering;
        final centeringGrade = front == null || back == null
            ? null
            : profile.centeringScore(frontLeftRight: front.leftRight, frontTopBottom: front.topBottom, backLeftRight: back.leftRight, backTopBottom: back.topBottom);

        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [if (scannedCard != null) IconButton(tooltip: 'Delete card', icon: const Icon(Icons.delete_outline), onPressed: () => _deleteCard(context, scannedCard))],
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(24, 16, 24, 40 + MediaQuery.paddingOf(context).bottom),
            children: [
              Center(child: _CardImageCarousel(card: card)),
              const SizedBox(height: 24),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              if (scannedCard != null)
                _DetailRow(
                  label: 'Estimated grade',
                  value: Align(
                    alignment: Alignment.centerLeft,
                    child: scannedCard.estimatedGrading != null
                        ? GradeBadge(grade: scannedCard.estimatedGrading!, profileName: profile.shortName)
                        : (centeringGrade != null ? GradeBadge(grade: centeringGrade, profileName: profile.shortName) : const Text('Not available')),
                  ),
                ),
              _DetailRow(label: 'Set', value: Text(catalogCard.setName)),
              _DetailRow(label: 'Card ID', value: Text(catalogCard.id)),
              if (scannedCard != null) ...[
                _DetailRow(
                  label: 'Scanned',
                  value: Text('${MaterialLocalizations.of(context).formatShortDate(scannedCard.createdAt.toLocal())} ${TimeOfDay.fromDateTime(scannedCard.createdAt.toLocal()).format(context)}'),
                ),
                const SizedBox(height: 16),
                if (scannedCard.gradeReport != null || scannedCard.estimatedGrading != null) ...[
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => GradeOverviewPage(card: scannedCard)));
                    },
                    icon: const Icon(Icons.analytics_outlined),
                    label: const Text('View grade overview'),
                  ),
                  const SizedBox(height: 16),
                ],
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CatalogCardDetailsPage(catalogCard))),
                  icon: const Icon(Icons.collections_bookmark_outlined),
                  label: const Text('View in catalog'),
                ),
              ],
            ],
          ),
        );
      },
    );
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

    if (confirmed == true && context.mounted) {
      await ScannedCardRepository.instance.delete(card);

      if (context.mounted) {
        Navigator.pop(context, true);
      }
    }
  }
}

class _CardImageCarousel extends StatelessWidget {
  final PokemonCard card;

  const _CardImageCarousel({required this.card});

  @override
  Widget build(BuildContext context) {
    final scannedCard = card is ScannedPokemonCard ? card as ScannedPokemonCard : null;
    final catalogCard = card.catalogCard;

    final items = <ImageCarouselItem>[];

    if (scannedCard != null) {
      items.add(ImageCarouselItem(imageProvider: scannedCard.frontImage, semanticLabel: 'Front photo of ${catalogCard.name}'));
      items.add(ImageCarouselItem(imageProvider: scannedCard.backImage, semanticLabel: 'Back photo of ${catalogCard.name}'));
    }

    if (catalogCard.imageUrl != null) {
      items.add(ImageCarouselItem(imageProvider: CachedNetworkImageProvider(catalogCard.imageUrl!), semanticLabel: 'Catalog image of ${catalogCard.name}'));
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: LayoutBuilder(
        builder: (context, constraints) => ImageCarousel(items: items, height: constraints.maxWidth / CardConstants.cardAspectRatio, fit: BoxFit.contain, showLabels: true),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final Widget value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 120, child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
          Expanded(child: value),
        ],
      ),
    );
  }
}
