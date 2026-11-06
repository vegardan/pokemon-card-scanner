import 'package:flutter/material.dart';
import 'package:pokemon_card_scanner/vision/card_constants.dart';
import 'package:pokemon_card_scanner/vision/quality/image_quality_result.dart';
import 'package:pokemon_card_scanner/widgets/image_carousel/image_carousel.dart';

class ScanQualityErrorPage extends StatelessWidget {
  final ImageQualityResult result;

  const ScanQualityErrorPage({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final items = <ImageCarouselItem>[];
    if (result.isBlurry && result.hasGlare) {
      items.add(
        ImageCarouselItem(
          imageProvider: MemoryImage(result.rawPhoto.bytes),
          semanticLabel: 'Blurry photo',
        ),
      );
      if (result.annotatedGlarePhoto != null) {
        items.add(
          ImageCarouselItem(
            imageProvider: MemoryImage(result.annotatedGlarePhoto!.bytes),
            semanticLabel: 'Glare detected',
          ),
        );
      }
    } else if (result.isBlurry) {
      items.add(
        ImageCarouselItem(
          imageProvider: MemoryImage(result.rawPhoto.bytes),
          semanticLabel: 'Blurry photo',
        ),
      );
    } else if (result.hasGlare && result.annotatedGlarePhoto != null) {
      items.add(
        ImageCarouselItem(
          imageProvider: MemoryImage(result.annotatedGlarePhoto!.bytes),
          semanticLabel: 'Glare detected',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Check photo quality')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colors.errorContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.error_outline, size: 48, color: colors.onErrorContainer),
                        const SizedBox(height: 12),
                        Text(
                          result.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: colors.onErrorContainer,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          result.description,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onErrorContainer,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (items.isNotEmpty)
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: LayoutBuilder(
                          builder: (context, constraints) => ImageCarousel(
                            items: items,
                            height: constraints.maxWidth / CardConstants.cardAspectRatio,
                            fit: BoxFit.contain,
                            showLabels: items.length > 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Retake photo'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
