import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'card_constants.dart';

class OrbIndex {
  final Uint8List _descriptors;

  OrbIndex(this._descriptors);

  int get cardCount => (_descriptors.length / (CardConstants.featuresPerCard * CardConstants.descriptorSize)).toInt();

  /// returns catalog indices ranked by ORB match count
  List<int> retrieve(Uint8List descriptors, {void Function(int completed, int total)? onProgress}) {
    if (descriptors.isEmpty) return [];

    final query = cv.Mat.fromList((descriptors.length / CardConstants.descriptorSize).toInt(), CardConstants.descriptorSize, cv.MatType.CV_8UC1, descriptors);
    final scores = List.filled(cardCount, 0);

    try {
      // search manageable groups instead of building a large native index
      const cardsPerGroup = 256;

      for (var firstCard = 0; firstCard < cardCount; firstCard += cardsPerGroup) {
        final endCard = (firstCard + cardsPerGroup).clamp(0, cardCount);
        _scoreGroup(query, firstCard, endCard, scores);
        onProgress?.call(endCard, cardCount);
      }

      // rank cards by match count
      final cards = List.generate(cardCount, (card) => card).where((card) => scores[card] > 0).toList();
      cards.sort((a, b) {
        final byScore = scores[b].compareTo(scores[a]);
        return byScore == 0 ? a.compareTo(b) : byScore;
      });

      return cards.take(CardConstants.candidateLimit).toList();
    } finally {
      query.dispose();
    }
  }

  void _scoreGroup(cv.Mat query, int firstCard, int endCard, List<int> scores) {
    final bytesPerCard = CardConstants.featuresPerCard * CardConstants.descriptorSize;
    final descriptors = Uint8List.sublistView(_descriptors, firstCard * bytesPerCard, endCard * bytesPerCard);
    final catalog = cv.Mat.fromList((descriptors.length / CardConstants.descriptorSize).toInt(), CardConstants.descriptorSize, cv.MatType.CV_8UC1, descriptors);
    final settings = cv.FlannIndexParams.empty()
      // search algorithm for binary descriptors
      ..setAlgorithm(cv.FlannAlgorithm.FLANN_INDEX_LSH)
      // number of hash tables
      ..setInt('table_number', 2)
      // bits per hash key
      ..setInt('key_size', 14)
      // extra bucket probing level
      ..setInt('multi_probe_level', 1);
    final matcher = cv.FlannBasedMatcher.create(indexParams: settings);
    cv.VecVecDMatch? matches;

    try {
      matches = matcher.knnMatch(query, catalog, 2);
      // count matches
      final countedFeatures = <int>{};

      for (var i = 0; i < matches.length; i++) {
        final pair = matches[i];

        if (pair.length < 2) continue;

        final best = pair[0];
        final second = pair[1];

        try {
          final card = (best.trainIdx / CardConstants.featuresPerCard).toInt();
          final secondCard = (second.trainIdx / CardConstants.featuresPerCard).toInt();
          final distinctive = card == secondCard || best.distance < second.distance * 0.8;

          if (best.distance < 64 && distinctive && countedFeatures.add(best.trainIdx)) {
            scores[firstCard + card]++;
          }
        } finally {
          best.dispose();
          second.dispose();
        }
      }
    } finally {
      matches?.dispose();
      matcher.dispose();
      catalog.dispose();
    }
  }
}
