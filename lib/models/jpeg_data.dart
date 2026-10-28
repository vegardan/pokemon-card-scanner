import 'dart:typed_data';

/// An image encoded as JPEG bytes
final class JpegData {
  final Uint8List bytes;

  const JpegData(this.bytes);
}
