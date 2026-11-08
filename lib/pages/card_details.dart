import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:pokemon_card_scanner/models/grading_profile.dart';
import 'package:pokemon_card_scanner/models/pokemon_card.dart';
import 'package:pokemon_card_scanner/pages/grade_overview.dart';
import 'package:pokemon_card_scanner/repositories/scanned_card_repository.dart';
import 'package:pokemon_card_scanner/vision/card_constants.dart';
import 'package:pokemon_card_scanner/widgets/grading/centering_details.dart';
import 'package:pokemon_card_scanner/widgets/grading/grade_badge.dart';
import 'package:pokemon_card_scanner/widgets/grading/grading_section.dart';
import 'package:pokemon_card_scanner/widgets/image_carousel/image_carousel.dart';

class OwnedCardDetailsPage extends StatelessWidget {
  final ScannedPokemonCard card;

  const OwnedCardDetailsPage(this.card, {super.key});

  @override
  Widget build(BuildContext context) => _CardDetailsPage(card);
}

class CatalogCardDetailsPage extends StatelessWidget {
  final CatalogPokemonCard card;

  const CatalogCardDetailsPage(this.card, {super.key});

  @override
  Widget build(BuildContext context) => _CardDetailsPage(card);
}

class _CardDetailsPage extends StatelessWidget {
  final PokemonCard card;

  const _CardDetailsPage(this.card);

  @override
  Widget build(BuildContext context) {
    final catalogCard = card.catalogCard;
    final scannedCard = card is ScannedPokemonCard ? card as ScannedPokemonCard : null;
    final title = catalogCard.name;
    final front = scannedCard?.frontCentering;
    final back = scannedCard?.backCentering;
    final overallGrade = scannedCard?.estimatedGrading ?? scannedCard?.gradeReport?.overallScore;
    final centeringGrade = front == null || back == null
        ? null
        : GradingProfile.psa.centeringScore(frontLeftRight: front.leftRight, frontTopBottom: front.topBottom, backLeftRight: back.leftRight, backTopBottom: back.topBottom);
    final grade = overallGrade ?? centeringGrade;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 40 + MediaQuery.paddingOf(context).bottom),
        children: [
          Center(child: _CardImageCarousel(card: card)),
          const SizedBox(height: 24),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          if (scannedCard != null)
            _DetailRow(
              label: overallGrade == null && centeringGrade != null ? 'Centering estimate' : 'Estimated grade',
              value: grade == null
                  ? const Text('Unavailable')
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: GradeBadge(grade: grade, showPsaLabel: true),
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
            if (overallGrade != null) ...[
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GradeOverviewPage(card: scannedCard))),
                icon: const Icon(Icons.analytics_outlined),
                label: const Text('View grade overview'),
              ),
              const SizedBox(height: 16),
            ],
            if (scannedCard.gradeReport == null && (front != null || back != null)) ...[
              _GradingBreakdown(card: scannedCard),
              const SizedBox(height: 24),
            ],
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CatalogCardDetailsPage(catalogCard))),
              icon: const Icon(Icons.collections_bookmark_outlined),
              label: const Text('View in catalog'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _deleteCard(context, scannedCard),
              style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete card'),
            ),
          ],
        ],
      ),
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
        builder: (context, constraints) => ImageCarousel(items: items, height: constraints.maxWidth / CardConstants.cardAspectRatio, fit: BoxFit.contain, showLabels: scannedCard != null),
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

class _GradingBreakdown extends StatelessWidget {
  final ScannedPokemonCard card;

  const _GradingBreakdown({required this.card});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Grading breakdown', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        GradingSection(
          title: 'Centering',
          subtitle: 'Front and back border balance',
          icon: Icons.center_focus_strong_outlined,
          child: CenteringDetails(front: card.frontCentering, back: card.backCentering),
        ),
      ],
    );
  }
}
