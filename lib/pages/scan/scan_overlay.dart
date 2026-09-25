import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pokemon_card_scanner/pages/scan/level_painter.dart';

class ScanLevelState {
  final bool visible;
  final Color accent;
  final String status;

  const ScanLevelState({required this.visible, required this.accent, required this.status});
}

class CameraPreviewCover extends StatelessWidget {
  final CameraController camera;

  const CameraPreviewCover({required this.camera, super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraValue>(
      valueListenable: camera,
      builder: (context, value, child) {
        final preview = value.previewSize!;
        final portrait = value.deviceOrientation == DeviceOrientation.portraitUp || value.deviceOrientation == DeviceOrientation.portraitDown;
        final size = portrait ? Size(preview.height, preview.width) : Size(preview.width, preview.height);

        return ClipRect(
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.fitWidth,
              alignment: Alignment.topCenter,
              child: SizedBox.fromSize(size: size, child: CameraPreview(camera)),
            ),
          ),
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
  final bool scanningBack;
  final VoidCallback onCapture;
  final VoidCallback onRetry;

  const ScanOverlay({
    required this.camera,
    required this.capturing,
    required this.error,
    required this.gravity,
    required this.levelState,
    required this.scanningBack,
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
            child: camera == null
                ? _CameraStatus(error: error, onRetry: onRetry)
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      _CardGuide(color: levelState.accent),
                      _LevelBubble(camera: camera!, gravity: gravity, levelState: levelState),
                    ],
                  ),
          ),
          _ScanStatus(scanningBack: scanningBack, levelState: levelState),
          _CaptureButton(cameraReady: camera != null, capturing: capturing, scanningBack: scanningBack, onCapture: onCapture),
        ],
      ),
    );
  }
}

class _CardGuide extends StatelessWidget {
  static const _cardAspectRatio = 63 / 88;
  final Color color;

  const _CardGuide({required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth - 32;
          final availableHeight = constraints.maxHeight - 32;
          final widthFromHeight = availableHeight * _cardAspectRatio;
          final width = availableWidth < widthFromHeight ? availableWidth : widthFromHeight;

          return Center(
            child: SizedBox(
              width: width,
              height: width / _cardAspectRatio,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: color, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          );
        },
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
  final CameraController camera;
  final Offset gravity;
  final ScanLevelState levelState;

  const _LevelBubble({required this.camera, required this.gravity, required this.levelState});

  @override
  Widget build(BuildContext context) {
    if (!levelState.visible) return const SizedBox.shrink();

    return IgnorePointer(
      child: Center(
        child: ValueListenableBuilder<CameraValue>(
          valueListenable: camera,
          builder: (context, value, child) {
            return SizedBox.square(dimension: 100, child: CustomPaint(painter: LevelPainter(_gravityForOrientation(value.deviceOrientation), levelState.accent)));
          },
        ),
      ),
    );
  }

  Offset _gravityForOrientation(DeviceOrientation orientation) {
    return switch (orientation) {
      DeviceOrientation.portraitUp => Offset(gravity.dx, -gravity.dy),
      DeviceOrientation.portraitDown => Offset(-gravity.dx, gravity.dy),
      DeviceOrientation.landscapeLeft => Offset(gravity.dy, gravity.dx),
      DeviceOrientation.landscapeRight => Offset(-gravity.dy, -gravity.dx),
    };
  }
}

class _ScanStatus extends StatelessWidget {
  final bool scanningBack;
  final ScanLevelState levelState;

  const _ScanStatus({required this.scanningBack, required this.levelState});

  @override
  Widget build(BuildContext context) {
    final side = scanningBack ? 'Back' : 'Front';
    final step = scanningBack ? '2' : '1';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            '$side side - $step of 2\n${levelState.status}',
            textAlign: TextAlign.center,
            style: TextStyle(color: levelState.accent),
          ),
        ),
      ),
    );
  }
}

class _CaptureButton extends StatelessWidget {
  final bool cameraReady;
  final bool capturing;
  final bool scanningBack;
  final VoidCallback onCapture;

  const _CaptureButton({required this.cameraReady, required this.capturing, required this.scanningBack, required this.onCapture});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20, top: 4),
      child: SizedBox.square(
        dimension: 72,
        child: IconButton.filled(
          onPressed: !cameraReady || capturing ? null : onCapture,
          style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, disabledBackgroundColor: Colors.white24),
          icon: capturing ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.camera_alt, size: 32),
        ),
      ),
    );
  }
}
