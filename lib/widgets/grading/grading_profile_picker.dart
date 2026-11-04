import 'package:flutter/material.dart';
import 'package:pokemon_card_scanner/models/grading_profile.dart';
import 'package:pokemon_card_scanner/controllers/grading_profile_controller.dart';

class GradingProfileChip extends StatelessWidget {
  const GradingProfileChip({super.key});

  @override
  Widget build(BuildContext context) {
    final selection = GradingProfileController.instance;
    return ListenableBuilder(
      listenable: selection,
      builder: (context, _) => PopupMenuButton<GradingProfile>(
        tooltip: 'Choose grading profile',
        initialValue: selection.value,
        position: PopupMenuPosition.under,
        onSelected: (profile) => selection.value = profile,
        itemBuilder: (_) => [for (final profile in GradingProfile.values) CheckedPopupMenuItem(value: profile, checked: profile == selection.value, child: Text(profile.name))],
        child: Chip(
          label: Row(mainAxisSize: MainAxisSize.min, children: [Text(selection.value.shortName), const SizedBox(width: 4), const Icon(Icons.expand_more, size: 18)]),
        ),
      ),
    );
  }
}
