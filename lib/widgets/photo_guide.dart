import 'package:flutter/material.dart';


void showPhotoGuide(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('How to photograph a card'),
      content: const SingleChildScrollView(
        child: Text(
          '- Use a plain, black, matte background. No patterns, no wood.\n\n'
              '- Place the card in the middle, with background visible on all four sides. The card must not touch the edges of the photo.\n\n'
              '- Use the provided frame as a guide for lining up the card when taking a photo.\n\n'
              '- Nothing else in the photo: no fingers, other cards or objects.\n\n'
              '- Even, bright light. Avoid strong shadows, glare and flash.\n\n'
              '- Hold the phone flat and straight above the card.\n\n'
              '- Take the card out of any sleeves and toploaders or similar.\n\n'
              '- Make sure the photo is sharp (tap to focus).\n\n'
              '- One side per photo: front and back separately.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}