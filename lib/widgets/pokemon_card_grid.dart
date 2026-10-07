import 'package:flutter/material.dart';
import 'package:pokemon_card_scanner/models/pokemon_card.dart';
import 'package:pokemon_card_scanner/pages/card_details.dart';
import 'package:pokemon_card_scanner/widgets/pokemon_card_widget.dart';

class PokemonCardGrid extends StatelessWidget {
  final List<PokemonCard> cards;
  final ValueChanged<ScannedPokemonCard>? onCardDeleted;

  const PokemonCardGrid({super.key, required this.cards, this.onCardDeleted});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 190 / 297),
      itemCount: cards.length,
      itemBuilder: (context, index) {
        final card = cards[index];

        return PokemonCardWidget(
          key: ObjectKey(card),
          card: card,
          onTap: () async {
            final deleted = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => CardDetailsPage(card)));
            if (deleted == true && card is ScannedPokemonCard) {
              onCardDeleted?.call(card);
            }
          },
        );
      },
    );
  }
}
