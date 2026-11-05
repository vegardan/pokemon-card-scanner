import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pokemon_card_scanner/models/card_side.dart';
import 'package:pokemon_card_scanner/models/jpeg_data.dart';
import 'package:pokemon_card_scanner/models/pokemon_card.dart';
import 'package:pokemon_card_scanner/pages/scan/scan_guide.dart';
import 'package:pokemon_card_scanner/pages/scan/crease_result_dialog.dart';
import 'package:pokemon_card_scanner/pages/scan/scan_overlay.dart';
import 'package:pokemon_card_scanner/pages/scan/scan_processing.dart';
import 'package:pokemon_card_scanner/vision/scan_processor.dart';
import 'package:pokemon_card_scanner/vision/crease_analyzer.dart';
import 'package:sensors_plus/sensors_plus.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  CameraController? _camera;
  CameraDescription? _cameraDescription;
  Future<void> _cameraWork = Future.value();
  StreamSubscription<AccelerometerEvent>? _motion;
  Timer? _sensorTimeout;

  bool _active = true;
  bool _capturing = false;
  bool _processing = false;
  bool _sensorAvailable = false;
  bool _sensorMissing = false;
  JpegData? _frontPhoto;
  CatalogPokemonCard? _identifiedFront;
  static Future<Float32List>? _referenceNoise;
  String? _error;
  Offset _gravity = Offset.zero;
  double _z = 0;

  CardSide get _scanningSide =>
      _frontPhoto == null ? CardSide.front : CardSide.back;

  ScanLevelState get _levelState {
    const levelColor = Color(0xFF69F0AE);
    const tiltColor = Color(0xFFFFDE59);

    if (_sensorMissing) {
      return const ScanLevelState(
        visible: false,
        accent: tiltColor,
        status: 'Level sensor unavailable',
      );
    }

    if (!_sensorAvailable) {
      return const ScanLevelState(
        visible: false,
        accent: tiltColor,
        status: 'Waiting for level sensor',
      );
    }

    final magnitude = math.sqrt(_gravity.distanceSquared + _z * _z);
    final tilt = magnitude < 0.1
        ? 180.0
        : math.acos((_z / magnitude).clamp(-1.0, 1.0)) * 180 / math.pi;
    final level = tilt <= 3;
    final status = level
        ? 'Level'
        : _z <= 0
        ? 'Camera facing upward'
        : '${tilt.round()}\u00b0 tilt';

    return ScanLevelState(
      visible: true,
      accent: level ? levelColor : tiltColor,
      status: status,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startMotion();
    _scheduleCamera();
  }

  void _startMotion() {
    _sensorAvailable = false;
    _sensorMissing = false;
    _sensorTimeout = Timer(const Duration(seconds: 3), () {
      if (mounted && !_sensorAvailable) setState(() => _sensorMissing = true);
    });
    _motion =
        accelerometerEventStream(
          samplingPeriod: const Duration(milliseconds: 60),
        ).listen(
          _updateLevelSensor,
          onError: (_) {
            if (mounted) setState(() => _sensorMissing = true);
          },
        );
  }

  void _updateLevelSensor(AccelerometerEvent event) {
    if (!mounted || !_active || _processing) return;

    _sensorTimeout?.cancel();
    setState(() {
      final weight = _sensorAvailable ? 0.18 : 1.0;
      _gravity += (Offset(event.x, event.y) - _gravity) * weight;
      _z += (event.z - _z) * weight;
      _sensorAvailable = true;
      _sensorMissing = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _stopMotion();

    if (_active && !_processing) _startMotion();

    _scheduleCamera();
  }

  void _stopMotion() {
    _sensorTimeout?.cancel();
    _motion?.cancel();
    _motion = null;
  }

  void _scheduleCamera() {
    _cameraWork = _cameraWork.then((_) => _syncCamera());
  }

  CameraDescription? _selectCamera(List<CameraDescription> cameras) {
    final rear = cameras
        .where((camera) => camera.lensDirection == CameraLensDirection.back)
        .toList();

    if (rear.isEmpty) return null;

    for (final camera in rear) {
      if (camera.lensType == CameraLensType.wide) return camera;
    }

    return rear.first;
  }

  Future<void> _configureCamera(CameraController controller) async {
    for (final setting in [
      () => controller.setFlashMode(FlashMode.off),
      () => controller.setFocusMode(FocusMode.auto),
    ]) {
      try {
        await setting();
      } on CameraException catch (error) {
        debugPrint('Optional card camera setting unavailable: $error');
      }
    }
  }

  Future<void> _syncCamera() async {
    if (!mounted || !_active || _processing) {
      await _disposeCamera();
      return;
    }

    if (_camera != null) return;

    setState(() => _error = null);
    CameraController? controller;

    try {
      if (_cameraDescription == null) {
        final cameras = await availableCameras();

        if (!mounted || !_active || _processing) return;

        _cameraDescription = _selectCamera(cameras);

        if (!mounted || !_active || _processing) return;

        if (_cameraDescription == null) {
          setState(
            () => _error = 'No back camera is available on this device.',
          );
          return;
        }
      }

      controller = CameraController(
        _cameraDescription!,
        ResolutionPreset.max,
        enableAudio: false,
      );
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await _configureCamera(controller);

      if (!mounted || !_active || _processing) {
        await controller.dispose();
        return;
      }

      setState(() => _camera = controller);
    } catch (error) {
      await controller?.dispose();

      if (!mounted) return;

      setState(() => _error = _cameraErrorMessage(error));
    }
  }

  Future<void> _disposeCamera() async {
    final previous = _camera;
    _camera = null;

    if (mounted) setState(() {});

    await previous?.dispose();
  }

  String _cameraErrorMessage(Object error) {
    if (error is CameraException && error.code.startsWith('CameraAccess')) {
      return 'Camera access is unavailable. Allow camera access in your phone settings, then try again.';
    }

    return 'Could not open the camera. Please try again.';
  }

  Future<void> _showScanError(String message, {required CardSide side}) async {
    setState(() => _processing = true);
    _stopMotion();
    _scheduleCamera();
    final retry = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ScanGuidePage(side: side, errorMessage: message),
      ),
    );

    if (!mounted) return;

    if (retry != true) Navigator.of(context).pop();
  }

  Future<void> _openGuide() async {
    setState(() => _processing = true);
    _stopMotion();
    _scheduleCamera();

    try {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => ScanGuidePage(side: _scanningSide)),
      );
    } finally {
      if (mounted) {
        setState(() => _processing = false);

        if (_active) _startMotion();

        _scheduleCamera();
      }
    }
  }

  Future<void> _capture() async {
    final camera = _camera;

    if (camera == null || _capturing || !_active) return;

    setState(() => _capturing = true);
    final side = _scanningSide;

    try {
      try {
        await camera.setFocusPoint(const Offset(0.5, 0.5));
      } on CameraException catch (error) {
        debugPrint('Capture autofocus unavailable: $error');
      }

      if (!mounted || !_active || _camera != camera) return;

      final photo = JpegData(await (await camera.takePicture()).readAsBytes());

      if (!mounted || !_active) return;

      setState(() => _processing = true);
      _stopMotion();
      _scheduleCamera();
      var stopped = false;
      final processor = ScanProcessor();
      final progress = ValueNotifier<ScanProgress>(
        const ScanProgress(stage: ScanStage.loadReferences, fraction: 0),
      );
      final cropped = await Navigator.of(context).push<ScanResult>(
        MaterialPageRoute(
          builder: (_) => ScanProcessingPage(
            side: side,
            progress: progress,
            process: () async {
              try {
                await _cameraWork;
                return await processor.process(
                  photo,
                  side: side,
                  onProgress: (value) => progress.value = value,
                );
              } finally {
                progress.dispose();
              }
            },
            onStop: () {
              stopped = true;
              processor.cancel();
            },
          ),
        ),
      );

      if (!mounted || stopped) return;

      if (cropped == null) {
        await _showScanError(
          side == CardSide.back
              ? 'Could not verify the card back. Please retake the photo.'
              : 'Could not identify the card front. Please retake the photo.',
          side: side,
        );
        return;
      }

      if (side == CardSide.front) {
        setState(() {
          _frontPhoto = cropped.image;
          _identifiedFront = cropped.catalogCard;
        });
      } else {
        final backCreases = await _reviewCreases(cropped.image);
        if (!mounted) return;
        Navigator.of(context).pop((
          front: _frontPhoto!,
          back: cropped.image,
          catalogCard: _identifiedFront!,
          backCreases: backCreases,
        ));
      }
    } catch (error, stackTrace) {
      debugPrint('Card capture failed: $error\n$stackTrace');

      if (mounted && _active) {
        await _showScanError(
          'Could not take the photo. Please try again.',
          side: side,
        );
      }
    } finally {
      if (mounted) {
        if (_processing &&
            _active &&
            ModalRoute.of(context)?.isCurrent == true) {
          _startMotion();
          _scheduleCamera();
        }

        setState(() {
          _capturing = false;
          _processing = false;
        });
      }
    }
  }

  Future<CreaseResult> _screenCreases(
    JpegData photo,
    Future<Uint8List?> reference,
  ) async {
    try {
      final bytes = await reference;
      Float32List? noise;
      if (bytes != null) {
        try {
          noise = await (_referenceNoise ??= compute(
            CreaseAnalyzer.referenceNoise,
            bytes,
          ));
        } catch (_) {
          _referenceNoise = null;
          rethrow;
        }
      }
      final result = await compute(CreaseAnalyzer.analyze, (
        photo: photo.bytes,
        reference: bytes,
        expectedNoise: noise,
        alignmentVerified: true,
        minimumProminence: CreaseAnalyzer.minimumCandidateScore,
      ));
      return result;
    } catch (error) {
      debugPrint('Crease screening unavailable: $error');
      return const CreaseResult.notEvaluated(
        'Crease analysis unavailable. Your scan can still be saved.',
      );
    }
  }

  Future<Uint8List?> _backReference() async {
    try {
      final data = await rootBundle.load('assets/pokemon_back.png');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    }
  }

  Future<CreaseAnalysis> _reviewCreases(JpegData back) async {
    // Analyze the verified back scan; stored photographs remain unchanged.
    final analysis = _screenCreases(back, _backReference());
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CreaseResultDialog(analysis: analysis),
    );
    // Continue may close the dialog early; retain the result before saving.
    return (await analysis).analysis;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _active = false;
    _stopMotion();
    _scheduleCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final levelState = _levelState;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _scanningSide == CardSide.back ? 'Scan card back' : 'Scan card front',
        ),
        actions: [
          IconButton(
            tooltip: 'Open scan guide',
            onPressed: _capturing || _processing ? null : _openGuide,
            icon: const Icon(Icons.help_outline),
          ),
          if (_scanningSide == CardSide.back)
            IconButton(
              onPressed: _capturing
                  ? null
                  : () => setState(() => _frontPhoto = null),
              icon: const Icon(Icons.replay),
            ),
        ],
      ),
      body: ScanOverlay(
        camera: camera,
        capturing: _capturing,
        error: _error,
        gravity: _gravity,
        levelState: levelState,
        side: _scanningSide,
        onCapture: _capture,
        onRetry: _scheduleCamera,
      ),
    );
  }
}
