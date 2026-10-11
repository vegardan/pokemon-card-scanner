import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:cancellation_token/cancellation_token.dart';
import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:pokemon_card_scanner/models/card_side.dart';
import 'package:pokemon_card_scanner/models/jpeg_data.dart';
import 'package:pokemon_card_scanner/models/pokemon_card.dart';
import 'package:pokemon_card_scanner/repositories/orb_references.dart';
import 'package:pokemon_card_scanner/repositories/pokemon_card_catalog.dart';

import 'card_constants.dart';
import 'card_identifier.dart';
import 'orb_index.dart';

class ScanResult {
  final JpegData image;
  final CatalogPokemonCard? catalogCard;

  const ScanResult({required this.image, this.catalogCard});
}

enum ScanStage {
  loadReferences('Preparing card references'),
  retrieveCandidates('Finding possible card matches'),
  loadCandidates('Loading possible matches'),
  identify('Identifying your card'),
  flatten('Straightening your card photo'),
  encode('Preparing your card image'),
  finalize('Finishing your scan');

  final String description;

  const ScanStage(this.description);
}

class ScanProgress {
  final ScanStage stage;
  final double fraction;

  const ScanProgress({required this.stage, required this.fraction});
}

class ScanProcessor {
  final CancellationToken _cancellationToken = CancellationToken();
  ScanProgress _progress = const ScanProgress(stage: ScanStage.loadReferences, fraction: 0);

  void cancel() => _cancellationToken.cancel();

  Future<ScanResult?> process(JpegData photo, {required CardSide side, void Function(ScanProgress)? onProgress}) async {
    _cancellationToken.throwIfCancelled();

    final stages = [
      ScanStage.loadReferences,
      if (side == CardSide.front) ...[ScanStage.retrieveCandidates, ScanStage.loadCandidates],
      ScanStage.identify,
      ScanStage.flatten,
      ScanStage.encode,
      ScanStage.finalize,
    ];

    _progress = const ScanProgress(stage: ScanStage.loadReferences, fraction: 0);
    _notifyProgress(0, ScanStage.loadReferences, onProgress);

    final updates = ReceivePort();
    final subscription = updates.listen((message) {
      if (message is ScanProgress) {
        final stageIndex = stages.indexOf(message.stage);
        if (stageIndex < 0) return;

        _notifyProgress((stageIndex + message.fraction) / stages.length, message.stage, onProgress);
      }
    });

    try {
      List<Uint8List> shards = [];
      List<String> ids = [];

      // load the shared card back reference or retrieve a list of candidates for front references
      if (side == CardSide.back) {
        shards = [await OrbReferences.loadBack()];
        _cancellationToken.throwIfCancelled();
        ids = [CardConstants.sharedBackReferenceId];
      } else {
        final store = await OrbReferences.load();
        _cancellationToken.throwIfCancelled();
        _sendStageProgress(updates.sendPort, ScanStage.loadReferences);
        final candidates = await cancellableCompute(_retrieveCapturedCard, (image: photo, indexPath: store.indexPath, progress: updates.sendPort), _cancellationToken);
        _notifyProgress(stages.indexOf(ScanStage.loadCandidates) / stages.length, ScanStage.loadCandidates, onProgress);
        shards = await store.loadCandidates(candidates);
        _cancellationToken.throwIfCancelled();

        for (final candidate in candidates) {
          ids.add(store.ids[candidate]);
        }
      }

      _sendStageProgress(updates.sendPort, side == CardSide.back ? ScanStage.loadReferences : ScanStage.loadCandidates);
      final cropped = await cancellableCompute(_cropCapturedCard, (image: photo, side: side, shards: shards, ids: ids, progress: updates.sendPort), _cancellationToken);
      _cancellationToken.throwIfCancelled();

      if (cropped == null) return null;

      _notifyProgress(stages.indexOf(ScanStage.finalize) / stages.length, ScanStage.finalize, onProgress);
      final catalogCard = side == CardSide.front && cropped.cardId != null ? await PokemonCardCatalog.findById(cropped.cardId!) : null;
      _cancellationToken.throwIfCancelled();

      if (side == CardSide.front && catalogCard == null) return null;

      _notifyProgress(1, ScanStage.finalize, onProgress);
      return ScanResult(image: cropped.image, catalogCard: catalogCard);
    } finally {
      await subscription.cancel();
      updates.close();
    }
  }

  /// notifies the UI of overall scan progress
  void _notifyProgress(double value, ScanStage stage, void Function(ScanProgress)? onProgress) {
    if (!_cancellationToken.isCancelled && value >= _progress.fraction && stage.index >= _progress.stage.index) {
      _progress = ScanProgress(stage: stage, fraction: value.clamp(0.0, 1.0));
      onProgress?.call(_progress);
    }
  }

  /// updates progress within one stage
  static void _sendStageProgress(SendPort port, ScanStage stage, {int completed = 1, int total = 1}) {
    final fraction = total == 0 ? 1.0 : (completed / total).clamp(0.0, 1.0);
    port.send(ScanProgress(stage: stage, fraction: fraction));
  }

  static List<int> _retrieveCapturedCard(({JpegData image, String indexPath, SendPort progress}) input) {
    _sendStageProgress(input.progress, ScanStage.retrieveCandidates, completed: 0);
    final image = cv.imdecode(input.image.bytes, cv.IMREAD_COLOR);

    try {
      if (image.isEmpty) return [];

      final file = File(input.indexPath);
      final index = OrbIndex(file.readAsBytesSync());
      final descriptors = CardIdentifier.retrievalDescriptors(image);
      return index.retrieve(
        descriptors,
        onProgress: (completed, total) => _sendStageProgress(input.progress, ScanStage.retrieveCandidates, completed: completed, total: total),
      );
    } finally {
      image.dispose();
    }
  }

  static ({JpegData image, String? cardId})? _cropCapturedCard(({JpegData image, CardSide side, List<Uint8List> shards, List<String> ids, SendPort progress}) input) {
    _sendStageProgress(input.progress, ScanStage.identify, completed: 0);
    final image = cv.imdecode(input.image.bytes, cv.IMREAD_COLOR);

    try {
      if (image.isEmpty) return null;

      final ids = input.ids.toSet();
      final references = <CardReference>[];

      for (final shard in input.shards) {
        for (final reference in CardReference.decode(shard)) {
          if (ids.contains(reference.id)) {
            references.add(reference);
          }
        }
      }

      final scan = CardIdentifier(references).scanForCapture(
        image,
        side: input.side,
        onProgress: (completed, total) => _sendStageProgress(input.progress, ScanStage.identify, completed: completed, total: total),
      );

      if (scan == null) return null;

      cv.Mat? flattened;
      final jpegParams = cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 98]);

      try {
        _sendStageProgress(input.progress, ScanStage.flatten, completed: 0);
        flattened = _flattenCard(image, scan.corners);
        _sendStageProgress(input.progress, ScanStage.flatten);
        _sendStageProgress(input.progress, ScanStage.encode, completed: 0);
        final (success, jpeg) = cv.imencode('.jpg', flattened, params: jpegParams);
        _sendStageProgress(input.progress, ScanStage.encode);
        final reference = scan.reference;
        return success ? (image: JpegData(jpeg), cardId: reference?.id) : null;
      } finally {
        jpegParams.dispose();
        flattened?.dispose();
        scan.dispose();
      }
    } finally {
      image.dispose();
    }
  }

  static cv.Mat _flattenCard(cv.Mat original, List<cv.Point2f> corners) {
    // rotate the corner order when needed
    final horizontal = (_distance(corners[0], corners[1]) + _distance(corners[3], corners[2])) / 2;
    final vertical = (_distance(corners[0], corners[3]) + _distance(corners[1], corners[2])) / 2;
    final warpCorners = horizontal <= vertical ? corners : [corners[3], corners[0], corners[1], corners[2]];

    // keep the physical card ratio
    final top = _distance(warpCorners[0], warpCorners[1]);
    final bottom = _distance(warpCorners[3], warpCorners[2]);
    final left = _distance(warpCorners[0], warpCorners[3]);
    final right = _distance(warpCorners[1], warpCorners[2]);
    final width = math.min(math.max(top, bottom), math.max(left, right));
    final height = width / CardConstants.cardAspectRatio;
    final size = (width: math.max(2, width.round()), height: math.max(2, height.round()));
    final source = cv.VecPoint2f.fromList(warpCorners);
    final destinationPoints = [cv.Point2f(0, 0), cv.Point2f(size.width - 1.0, 0), cv.Point2f(size.width - 1.0, size.height - 1.0), cv.Point2f(0, size.height - 1.0)];
    final destination = cv.VecPoint2f.fromList(destinationPoints);

    cv.Mat? transform;

    try {
      transform = cv.getPerspectiveTransform2f(source, destination);
      return cv.warpPerspective(original, transform, (size.width, size.height), flags: cv.INTER_LANCZOS4, borderMode: cv.BORDER_REPLICATE);
    } finally {
      transform?.dispose();
      source.dispose();
      destination.dispose();

      for (final point in destinationPoints) {
        point.dispose();
      }
    }
  }

  static double _distance(cv.Point2f a, cv.Point2f b) => math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
}
