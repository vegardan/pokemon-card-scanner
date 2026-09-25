import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pokemon_card_scanner/pages/scan/scan_overlay.dart';
import 'package:sensors_plus/sensors_plus.dart';

typedef CapturedCardImages = ({Uint8List front, Uint8List back});

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  CameraController? _camera;
  Future<void> _cameraWork = Future.value();
  StreamSubscription<AccelerometerEvent>? _motion;
  Timer? _sensorTimeout;

  bool _active = true;
  bool _capturing = false;
  bool _sensorAvailable = false;
  bool _sensorMissing = false;
  Uint8List? _frontPhotoBytes;
  String? _error;
  Offset _gravity = Offset.zero;
  double _z = 0;

  bool get _scanningBack => _frontPhotoBytes != null;

  ScanLevelState get _levelState {
    const levelColor = Color(0xFF69F0AE);
    const tiltColor = Color(0xFFFFDE59);

    if (_sensorMissing) {
      return const ScanLevelState(visible: false, accent: tiltColor, status: 'Level sensor unavailable');
    }

    if (!_sensorAvailable) {
      return const ScanLevelState(visible: false, accent: tiltColor, status: 'Waiting for level sensor');
    }

    final magnitude = math.sqrt(_gravity.distanceSquared + _z * _z);
    final tilt = magnitude < 0.1 ? 180.0 : math.acos((_z / magnitude).clamp(-1.0, 1.0)) * 180 / math.pi;
    final level = tilt <= 3;
    final status = level
        ? 'Level'
        : _z <= 0
        ? 'Camera facing upward'
        : '${tilt.round()}\u00b0 tilt';

    return ScanLevelState(visible: true, accent: level ? levelColor : tiltColor, status: status);
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
    _motion = accelerometerEventStream(samplingPeriod: const Duration(milliseconds: 60)).listen(
      _updateLevelSensor,
      onError: (_) {
        if (mounted) setState(() => _sensorMissing = true);
      },
    );
  }

  void _updateLevelSensor(AccelerometerEvent event) {
    if (!mounted || !_active) return;

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
    if (_active) _startMotion();
    _scheduleCamera();
  }

  void _stopMotion() {
    _sensorTimeout?.cancel();
    unawaited(_motion?.cancel());
    _motion = null;
  }

  void _scheduleCamera() {
    _cameraWork = _cameraWork.then((_) => _syncCamera());
  }

  Future<void> _syncCamera() async {
    if (!mounted || !_active) {
      await _disposeCamera();
      return;
    }
    if (_camera != null) return;

    setState(() => _error = null);
    CameraController? controller;
    try {
      controller = CameraController(await _rearCamera(), ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);

      if (!mounted || !_active) {
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

  Future<CameraDescription> _rearCamera() async {
    final cameras = await availableCameras();
    return cameras.firstWhere((camera) => camera.lensDirection == CameraLensDirection.back, orElse: () => throw CameraException('NoCamera', 'No rear camera is available.'));
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
    return 'Could not open the rear camera. Please try again.';
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || _capturing || !_active) return;

    setState(() => _capturing = true);
    try {
      final bytes = await (await camera.takePicture()).readAsBytes();
      if (!mounted || !_active) return;

      final front = _frontPhotoBytes;
      if (front == null) {
        setState(() => _frontPhotoBytes = bytes);
      } else {
        Navigator.of(context).pop((front: front, back: bytes));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not take the photo. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
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
        title: Text(_scanningBack ? 'Scan card back' : 'Scan card front'),
        actions: [if (_scanningBack) IconButton(onPressed: _capturing ? null : () => setState(() => _frontPhotoBytes = null), icon: const Icon(Icons.replay))],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (camera != null) CameraPreviewCover(camera: camera),
          ScanOverlay(camera: camera, capturing: _capturing, error: _error, gravity: _gravity, levelState: levelState, scanningBack: _scanningBack, onCapture: _capture, onRetry: _scheduleCamera),
        ],
      ),
    );
  }
}
