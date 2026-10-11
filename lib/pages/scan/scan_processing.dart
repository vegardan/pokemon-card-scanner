import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pokemon_card_scanner/models/card_side.dart';
import 'package:pokemon_card_scanner/vision/scan_processor.dart';

class ScanProcessingPage extends StatefulWidget {
  final CardSide side;
  final Future<ScanResult?> Function() process;
  final VoidCallback? onStop;
  final ValueListenable<ScanProgress>? progress;

  const ScanProcessingPage({super.key, required this.side, required this.process, this.onStop, this.progress});

  @override
  State<ScanProcessingPage> createState() => _ScanProcessingPageState();
}

class _ScanProcessingPageState extends State<ScanProcessingPage> {
  bool _finished = false;

  void _cancel() {
    if (_finished) return;

    _finished = true;
    widget.onStop?.call();
  }

  void _stop() {
    if (_finished) return;

    _cancel();
    Navigator.of(context).pop();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _process());
  }

  Future<void> _process() async {
    if (!mounted || _finished) return;

    ScanResult? result;

    try {
      result = await widget.process();
    } catch (error, stackTrace) {
      if (!_finished) debugPrint('Card processing failed: $error\n$stackTrace');
    }

    if (mounted && !_finished) {
      _finished = true;
      Navigator.of(context).pop(result);
    }
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.side == CardSide.back ? 'Processing card back' : 'Processing card front'),
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
                            child: widget.progress == null
                                ? const CircularProgressIndicator(strokeWidth: 3)
                                : ValueListenableBuilder<ScanProgress>(
                                    valueListenable: widget.progress!,
                                    builder: (_, value, _) => CircularProgressIndicator(value: value.fraction, strokeWidth: 3),
                                  ),
                          ),
                          Icon(widget.side == CardSide.back ? Icons.check_outlined : Icons.flip_camera_android_outlined, size: 36, color: Theme.of(context).colorScheme.primary),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(widget.side == CardSide.back ? 'Finishing your scan' : 'Flip your card', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    Text(
                      widget.side == CardSide.back ? 'Checking the back. Your scan will be ready shortly.' : 'We\'re identifying the front. Turn your card over and get ready to photograph the back.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    if (widget.progress != null) ...[
                      const SizedBox(height: 16),
                      ValueListenableBuilder<ScanProgress>(
                        valueListenable: widget.progress!,
                        builder: (_, value, _) => Text(
                          value.stage.description,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    OutlinedButton.icon(onPressed: _stop, icon: const Icon(Icons.stop), label: const Text('Stop')),
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
