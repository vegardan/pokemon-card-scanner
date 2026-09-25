import 'package:flutter/material.dart';
import 'package:pokemon_card_scanner/models/pokemon_card.dart';
import 'package:pokemon_card_scanner/widgets/pokemon_card_widget.dart';

class PokemonCardGrid extends StatelessWidget {
  const PokemonCardGrid({super.key, required this.cards});

  final List<PokemonCard> cards;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 190 / 297),
      itemCount: cards.length,
      itemBuilder: (context, index) {
        final card = cards[index];
        return PokemonCardWidget(key: ObjectKey(card), slotNumber: index + 1, card: card);
      },
    );
  }
}
