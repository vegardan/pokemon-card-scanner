import 'package:flutter/material.dart';

class CarouselDots extends StatelessWidget {
  final int count;
  final int currentIndex;
  final Color? activeColor;
  final Color? inactiveColor;

  const CarouselDots({super.key, required this.count, required this.currentIndex, this.activeColor, this.inactiveColor});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final selected = index == currentIndex;

        return Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? activeColor ?? colors.primary : inactiveColor ?? colors.outlineVariant),
        );
      }),
    );
  }
}
