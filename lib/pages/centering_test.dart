import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:pokemon_card_scanner/centering/card_finder.dart';

/// Test page for the centering feature without camera: pick a card photo from
/// the gallery and run the centering steps on it.
class CenteringTestPage extends StatefulWidget {
  final Uint8List? initialPhotoBytes;

  const CenteringTestPage({super.key, this.initialPhotoBytes});

  @override
  State<CenteringTestPage> createState() => _CenteringTestPageState();
}

class _CenteringTestPageState extends State<CenteringTestPage> {
  List<_Step> _steps = [];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPhotoBytes;
    if (initial != null) _showPhoto(initial);
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    _showPhoto(await file.readAsBytes());
  }

  void _showPhoto(Uint8List bytes) {
    final steps = <_Step>[];

    void addStep(String title, cv.Mat mat) {
      final (_, jpg) = cv.imencode('.jpg', mat);
      steps.add(_Step(title, jpg));
    }

    final image = cv.imdecode(bytes, cv.IMREAD_COLOR);
    steps.add(_Step('Original: ${image.cols} × ${image.rows} px', bytes));

    final labImage = prepForLabCardFinding(image);
    addStep('Photo after prep: shrink, blur and convert to Lab. ${labImage.cols} × ${labImage.rows} px. Kernel size blur: $blurKernelSize', labImage);

    final backgroundLab = backgroundColor(labImage, backgroundStripWidth);
    final differenceImage = differenceFromBackground(labImage, backgroundLab);
    addStep('Difference from background (bg L=${backgroundLab.val1.round()} a=${backgroundLab.val2.round()} b=${backgroundLab.val3.round()}). Strip width used around the edge: $backgroundStripWidth', differenceImage);

    final mask = seperateByFixedThreshold(differenceImage, fixedCutOffThreshold);
    addStep('Fixed cut-off ${fixedCutOffThreshold.round()} on difference', mask);

    final cleanedMask = cleanMask(mask, cleanKernelSize);
    addStep('Cleaned mask, kernel size: $cleanKernelSize', cleanedMask);

    image.dispose();
    labImage.dispose();
    differenceImage.dispose();
    mask.dispose();
    cleanedMask.dispose();

    setState(() => _steps = steps);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Centering test')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickPhoto,
        icon: const Icon(Icons.photo_library_outlined),
        label: const Text('Pick from gallery'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_steps.isEmpty) const Text('Pick a photo of a card to start.'),
          for (final step in _steps) ...[
            Text(step.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Image.memory(step.image),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }
}

class _Step {
  final String title;
  final Uint8List image;
  const _Step(this.title, this.image);
}