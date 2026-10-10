import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Test page for the centering feature without camera: pick a card photo from
/// the gallery and run the centering steps on it.
class CenteringTestPage extends StatefulWidget {
  final Uint8List? initialPhotoBytes;

  const CenteringTestPage({super.key, this.initialPhotoBytes});

  @override
  State<CenteringTestPage> createState() => _CenteringTestPageState();
}

class _CenteringTestPageState extends State<CenteringTestPage> {
  Uint8List? _photoBytes;
  String _info = 'Pick a photo of a card to start.';

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
    final image = cv.imdecode(bytes, cv.IMREAD_COLOR);
    final info = 'OpenCV read the photo: ${image.cols} × ${image.rows} px, ${image.channels} channels';
    image.dispose();

    setState(() {
      _photoBytes = bytes;
      _info = info;
    });
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photoBytes;
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
          Text(_info),
          const SizedBox(height: 12),
          if (photo != null) Image.memory(photo),
        ],
      ),
    );
  }
}