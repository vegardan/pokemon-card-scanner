import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:pokemon_card_scanner/models/grading_profile.dart';
import 'package:pokemon_card_scanner/models/pokemon_card.dart';
import 'package:pokemon_card_scanner/widgets/grading/grade_badge.dart';
import 'package:skeletonizer/skeletonizer.dart';

class PokemonCardWidget extends StatelessWidget {
  final PokemonCard card;
  final VoidCallback? onTap;

  const PokemonCardWidget({super.key, required this.card, this.onTap});

  static const _emptyCardImage = AssetImage('assets/pokemon_back_monochrome.png');

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final catalogCard = card.catalogCard;
    final scannedCard = card is ScannedPokemonCard ? card as ScannedPokemonCard : null;
    final front = scannedCard?.frontCentering;
    final back = scannedCard?.backCentering;
    final estimatedGrade = front == null || back == null
        ? null
        : GradingProfile.psa.centeringScore(frontLeftRight: front.leftRight, frontTopBottom: front.topBottom, backLeftRight: back.leftRight, backTopBottom: back.topBottom);
    final cardTitle = catalogCard.name;
    final setText = catalogCard.setName;

    return Semantics(
      button: onTap != null,
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        color: colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: colorScheme.surface,
                      padding: const EdgeInsets.all(8),
                      child: _CardImage(card: catalogCard, capturedImage: scannedCard?.frontImage, emptyCardImage: _emptyCardImage),
                    ),
                    if (estimatedGrade != null) Positioned(top: 8, right: 8, child: GradeBadge(grade: estimatedGrade)),
                  ],
                ),
              ),
              _CardDetails(title: cardTitle, setText: setText),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardImage extends StatelessWidget {
  final CatalogPokemonCard card;
  final ImageProvider? capturedImage;
  final ImageProvider emptyCardImage;

  const _CardImage({required this.card, required this.capturedImage, required this.emptyCardImage});

  @override
  Widget build(BuildContext context) {
    final imageUrl = card.imageUrl;

    if (capturedImage == null && (imageUrl == null || imageUrl.isEmpty)) {
      return Image(image: emptyCardImage, fit: BoxFit.contain, excludeFromSemantics: true);
    }

    final image = capturedImage ?? CachedNetworkImageProvider(imageUrl!);
    return Image(
      key: ValueKey(image),
      image: image,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;

        final loaded = frame != null;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: loaded ? 1 : 0),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          builder: (context, opacity, _) {
            return Stack(
              fit: StackFit.expand,
              children: [
                if (opacity < 1) _CardBackSkeleton(emptyCardImage: emptyCardImage, opacity: 0.5 * (1 - opacity)),
                Opacity(opacity: opacity, child: child),
              ],
            );
          },
        );
      },
      errorBuilder: (context, error, stackTrace) => Icon(Icons.broken_image_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

class _CardBackSkeleton extends StatelessWidget {
  final ImageProvider emptyCardImage;
  final double opacity;

  const _CardBackSkeleton({required this.emptyCardImage, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Opacity(
              opacity: opacity,
              child: Image(image: emptyCardImage, fit: BoxFit.contain, excludeFromSemantics: true),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Skeletonizer(
                  enabled: true,
                  effect: const ShimmerEffect(baseColor: Color(0x22FFFFFF), highlightColor: Color(0xCCFFFFFF), duration: Duration(milliseconds: 1100)),
                  child: Skeleton.leaf(
                    child: const SizedBox.expand(child: ColoredBox(color: Colors.white)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardDetails extends StatelessWidget {
  final String title;
  final String setText;

  const _CardDetails({required this.title, required this.setText});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 2),
          Text(
            setText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
