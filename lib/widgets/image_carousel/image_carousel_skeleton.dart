import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

class ImageCarouselSkeleton extends StatelessWidget {
  final double height;
  final double bottomPadding;
  final bool fullscreen;

  const ImageCarouselSkeleton({super.key, this.height = 240, this.bottomPadding = 0, this.fullscreen = false});

  @override
  Widget build(BuildContext context) {
    final radius = fullscreen ? BorderRadius.zero : BorderRadius.circular(12);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Skeletonizer(
        enabled: true,
        child: Bone(width: double.infinity, height: fullscreen ? double.infinity : height, borderRadius: radius),
      ),
    );
  }
}
