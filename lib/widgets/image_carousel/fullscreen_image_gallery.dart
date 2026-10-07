import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:pokemon_card_scanner/widgets/image_carousel/carousel_dots.dart';
import 'package:pokemon_card_scanner/widgets/image_carousel/image_carousel_skeleton.dart';

class FullscreenImageGallery extends StatefulWidget {
  final List<ImageProvider> images;
  final int initialIndex;

  const FullscreenImageGallery({super.key, required this.images, this.initialIndex = 0});

  @override
  State<FullscreenImageGallery> createState() => _FullscreenImageGalleryState();
}

class _FullscreenImageGalleryState extends State<FullscreenImageGallery> {
  late int _index = widget.initialIndex;
  late final _initialPage = widget.images.length == 1 ? 0 : widget.images.length * 1000 + widget.initialIndex;
  late final _itemCount = widget.images.length == 1 ? 1 : widget.images.length * 2001;
  late final _controller = PageController(initialPage: _initialPage);

  int _imageIndex(int pageIndex) => pageIndex % widget.images.length;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _controller.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PhotoViewGallery.builder(
            pageController: _controller,
            itemCount: _itemCount,
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            loadingBuilder: (_, _) => const ImageCarouselSkeleton(fullscreen: true),
            onPageChanged: (page) => setState(() => _index = _imageIndex(page)),
            builder: (context, page) {
              return PhotoViewGalleryPageOptions(
                imageProvider: widget.images[_imageIndex(page)],
                initialScale: PhotoViewComputedScale.contained,
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 4,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, _, _) {
                  return const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white70, size: 48));
                },
              );
            },
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ),
          if (widget.images.length > 1)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: CarouselDots(count: widget.images.length, currentIndex: _index, activeColor: Colors.white, inactiveColor: Colors.white38),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
