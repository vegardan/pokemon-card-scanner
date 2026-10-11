import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Shows a photo picked from the gallery
/// Placeholder until the analysis features (centering, corners/edges/whitening etc) are connected here
class PhotoPreviewPage extends StatelessWidget {
  final Uint8List photoBytes;

  const PhotoPreviewPage({super.key, required this.photoBytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Photo from gallery')),
      body: Center(child: InteractiveViewer(child: Image.memory(photoBytes))),
    );
  }
}