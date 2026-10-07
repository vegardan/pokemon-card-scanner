import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:pokemon_card_scanner/widgets/image_carousel/carousel_dots.dart';
import 'package:pokemon_card_scanner/widgets/image_carousel/fullscreen_image_gallery.dart';
import 'package:pokemon_card_scanner/widgets/image_carousel/image_carousel_skeleton.dart';

class ImageCarouselItem {
  final ImageProvider imageProvider;
  final String? semanticLabel;

  const ImageCarouselItem({required this.imageProvider, this.semanticLabel});
}

class ImageCarousel extends StatefulWidget {
  final List<ImageCarouselItem> items;
  final double height;
  final BorderRadius borderRadius;
  final BoxFit fit;
  final bool openFullscreenOnTap;
  final bool showLabels;

  const ImageCarousel({
    super.key,
    required this.items,
    this.height = 240,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.fit = BoxFit.cover,
    this.openFullscreenOnTap = true,
    this.showLabels = false,
  });

  @override
  State<ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<ImageCarousel> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        CarouselSlider.builder(
          itemCount: widget.items.length,
          itemBuilder: (context, index, _) {
            return _CarouselImage(
              item: widget.items[index],
              height: widget.height,
              borderRadius: widget.borderRadius,
              fit: widget.fit,
              onTap: widget.openFullscreenOnTap ? () => _openFullscreen(index) : null,
            );
          },
          options: CarouselOptions(height: widget.height, viewportFraction: 1, enableInfiniteScroll: widget.items.length > 1, onPageChanged: (index, _) => setState(() => _index = index)),
        ),
        if (widget.showLabels && widget.items[_index].semanticLabel != null) ...[const SizedBox(height: 8), Text(widget.items[_index].semanticLabel!, style: Theme.of(context).textTheme.labelLarge)],
        if (widget.items.length > 1) ...[const SizedBox(height: 10), CarouselDots(count: widget.items.length, currentIndex: _index)],
      ],
    );
  }

  void _openFullscreen(int index) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FullscreenImageGallery(images: [for (final item in widget.items) item.imageProvider], initialIndex: index),
      ),
    );
  }
}

class _CarouselImage extends StatelessWidget {
  final ImageCarouselItem item;
  final double height;
  final BorderRadius borderRadius;
  final BoxFit fit;
  final VoidCallback? onTap;

  const _CarouselImage({required this.item, required this.height, required this.borderRadius, required this.fit, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: borderRadius,
      child: Material(
        color: colors.surfaceContainerHighest,
        child: InkWell(
          onTap: onTap,
          child: Image(
            image: item.imageProvider,
            width: double.infinity,
            height: height,
            fit: fit,
            semanticLabel: item.semanticLabel,
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return ImageCarouselSkeleton(height: height);
            },
            errorBuilder: (_, _, _) {
              return SizedBox(
                width: double.infinity,
                height: height,
                child: Icon(Icons.broken_image_outlined, color: colors.onSurfaceVariant, size: 36),
              );
            },
          ),
        ),
      ),
    );
  }
}
