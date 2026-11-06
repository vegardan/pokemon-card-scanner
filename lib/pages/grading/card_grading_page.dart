import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:pokemon_card_scanner/centering/centering_check.dart';
import 'package:pokemon_card_scanner/grading/grading_pipeline.dart';
import 'package:pokemon_card_scanner/models/analysis/analysis_input.dart';
import 'package:pokemon_card_scanner/models/analysis/analysis_result.dart';
import 'package:pokemon_card_scanner/models/crease_analysis.dart';
import 'package:pokemon_card_scanner/models/jpeg_data.dart';
import 'package:pokemon_card_scanner/models/pokemon_card.dart';
import 'package:pokemon_card_scanner/repositories/scanned_card_repository.dart';

class CardGradingPage extends StatefulWidget {
  final JpegData frontPhoto;
  final JpegData backPhoto;
  final CatalogPokemonCard catalogCard;
  final CenteringResult? frontCentering;
  final CenteringResult? backCentering;
  final CreaseAnalysis backCreases;

  const CardGradingPage({
    super.key,
    required this.frontPhoto,
    required this.backPhoto,
    required this.catalogCard,
    this.frontCentering,
    this.backCentering,
    this.backCreases = CreaseAnalysis.unavailable,
  });

  @override
  State<CardGradingPage> createState() => _CardGradingPageState();
}

class _CardGradingPageState extends State<CardGradingPage> {
  double _fraction = 0.0;
  String _status = 'Preparing card images...';
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startGrading());
  }

  Future<void> _startGrading() async {
    if (!mounted || _finished) return;

    final frontMat = cv.imdecode(widget.frontPhoto.bytes, cv.IMREAD_COLOR);
    final backMat = cv.imdecode(widget.backPhoto.bytes, cv.IMREAD_COLOR);

    try {
      final input = AnalysisInput(
        frontImage: frontMat,
        backImage: backMat,
        catalogCard: widget.catalogCard,
        frontPhoto: widget.frontPhoto,
        backPhoto: widget.backPhoto,
        backCreases: widget.backCreases,
        frontCentering: widget.frontCentering,
        backCentering: widget.backCentering,
      );

      final pipeline = GradingPipeline();
      final totalSteps = pipeline.analyzers.length + 1;
      var currentStep = 0;

      final runResult = await pipeline.run(
        input,
        onProgress: (stepDescription) {
          if (!mounted || _finished) return;
          currentStep++;
          setState(() {
            _fraction = (currentStep / totalSteps).clamp(0.0, 1.0);
            _status = stepDescription;
          });
        },
      );

      if (!mounted || _finished) return;

      final cornerResult = runResult.results
          .whereType<CornerAnalysisResult>()
          .firstOrNull;

      final savedCard = await ScannedCardRepository.instance.save(
        widget.frontPhoto,
        widget.backPhoto,
        widget.catalogCard,
        frontCentering: widget.frontCentering,
        backCentering: widget.backCentering,
        backCreases: widget.backCreases,
        estimatedGrade: runResult.grade,
        annotatedFrontCorners: cornerResult?.annotatedFrontPhoto,
        annotatedBackCorners: cornerResult?.annotatedBackPhoto,
      );

      if (mounted && !_finished) {
        _finished = true;
        Navigator.of(context).pop(savedCard);
      }
    } catch (error, stack) {
      debugPrint('Card grading failed: $error\n$stack');

      if (!mounted || _finished) return;

      final savedCard = await ScannedCardRepository.instance.save(
        widget.frontPhoto,
        widget.backPhoto,
        widget.catalogCard,
        frontCentering: widget.frontCentering,
        backCentering: widget.backCentering,
        backCreases: widget.backCreases,
      );

      if (mounted && !_finished) {
        _finished = true;
        Navigator.of(context).pop(savedCard);
      }
    } finally {
      frontMat.dispose();
      backMat.dispose();
    }
  }

  void _stop() {
    if (_finished) return;
    _finished = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Estimating grade'),
          leading: BackButton(onPressed: _stop),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox.square(
                      dimension: 80,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: CircularProgressIndicator(
                              value: _fraction > 0 ? _fraction : null,
                              strokeWidth: 3,
                            ),
                          ),
                          Icon(
                            Icons.auto_awesome,
                            size: 36,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Estimating grade',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Analyzing centering, edges, corners, and surface condition.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _status,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    OutlinedButton.icon(
                      onPressed: _stop,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
