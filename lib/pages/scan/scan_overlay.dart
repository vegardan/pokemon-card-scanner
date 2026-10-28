import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:pokemon_card_scanner/models/card_side.dart';
import 'package:pokemon_card_scanner/pages/scan/level_painter.dart';
import 'package:pokemon_card_scanner/vision/card_constants.dart';

class ScanLevelState {
  final bool visible;
  final Color accent;
  final String status;

  const ScanLevelState({required this.visible, required this.accent, required this.status});
}

class ScanCameraPreview extends StatelessWidget {
  final CameraController camera;
  final Offset gravity;
  final ScanLevelState levelState;

  const ScanCameraPreview({required this.camera, required this.gravity, required this.levelState, super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraValue>(
      valueListenable: camera,
      builder: (context, value, child) {
        final preview = value.previewSize;

        if (!value.isInitialized || preview == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final portraitSize = Size(preview.height, preview.width);
            final height = (constraints.maxWidth / portraitSize.aspectRatio).clamp(0.0, constraints.maxHeight).toDouble();
            return Center(
              child: SizedBox(
                width: constraints.maxWidth,
                height: height,
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox.fromSize(size: portraitSize, child: CameraPreview(camera)),
                      ),
                      _CardGuide(color: levelState.accent),
                      _LevelBubble(gravity: gravity, levelState: levelState),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class ScanOverlay extends StatelessWidget {
  final CameraController? camera;
  final bool capturing;
  final String? error;
  final Offset gravity;
  final ScanLevelState levelState;
  final CardSide side;
  final VoidCallback onCapture;
  final VoidCallback onRetry;

  const ScanOverlay({
    required this.camera,
    required this.capturing,
    required this.error,
    required this.gravity,
    required this.levelState,
    required this.side,
    required this.onCapture,
    required this.onRetry,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: camera == null ? _CameraStatus(error: error, onRetry: onRetry) : ScanCameraPreview(camera: camera!, gravity: gravity, levelState: levelState),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ScanStatus(side: side, levelState: levelState),
                const SizedBox(height: 16),
                _CaptureButton(cameraReady: camera != null, capturing: capturing, onCapture: onCapture),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardGuide extends StatelessWidget {
  const _CardGuide({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: AspectRatio(
            aspectRatio: CardConstants.cardAspectRatio,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color, width: 3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraStatus extends StatelessWidget {
  final String? error;
  final VoidCallback onRetry;

  const _CameraStatus({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (error == null) return const Center(child: CircularProgressIndicator());

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _LevelBubble extends StatelessWidget {
  final Offset gravity;
  final ScanLevelState levelState;

  const _LevelBubble({required this.gravity, required this.levelState});

  @override
  Widget build(BuildContext context) {
    if (!levelState.visible) return const SizedBox.shrink();

    return IgnorePointer(
      child: Center(
        child: SizedBox.square(dimension: 100, child: CustomPaint(painter: LevelPainter(Offset(gravity.dx, -gravity.dy), levelState.accent))),
      ),
    );
  }
}

class _ScanStatus extends StatelessWidget {
  final CardSide side;
  final ScanLevelState levelState;

  const _ScanStatus({required this.side, required this.levelState});

  @override
  Widget build(BuildContext context) {
    final label = side == CardSide.back ? 'Back' : 'Front';
    final step = side == CardSide.back ? '2' : '1';

    final theme = Theme.of(context);
    final statusColor = theme.brightness == Brightness.dark ? levelState.accent : Color.lerp(levelState.accent, Colors.black, 0.6);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label side · $step of 2', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          levelState.status,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: statusColor),
        ),
      ],
    );
  }
}

class _CaptureButton extends StatelessWidget {
  final bool cameraReady;
  final bool capturing;
  final VoidCallback onCapture;

  const _CaptureButton({required this.cameraReady, required this.capturing, required this.onCapture});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 72,
      child: IconButton.filled(
        onPressed: !cameraReady || capturing ? null : onCapture,
        style: IconButton.styleFrom(backgroundColor: colors.onSurface, foregroundColor: colors.surface, disabledBackgroundColor: colors.onSurface.withValues(alpha: 0.2)),
        icon: capturing ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.camera_alt, size: 32),
      ),
    );
  }
}
