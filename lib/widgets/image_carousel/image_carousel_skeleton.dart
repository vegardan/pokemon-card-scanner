import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

class ImageCarouselSkeleton extends StatelessWidget {
  final double height;
  final bool fullscreen;

  const ImageCarouselSkeleton({super.key, this.height = 240, this.fullscreen = false});

  @override
  Widget build(BuildContext context) {
    final radius = fullscreen ? BorderRadius.zero : BorderRadius.circular(12);

    return Skeletonizer(
      child: Bone(width: double.infinity, height: fullscreen ? double.infinity : height, borderRadius: radius),
    );
  }
}
