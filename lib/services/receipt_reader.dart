import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// Gets a receipt photo and reads the text on it.
///
/// The text is read on the phone itself, so it works without a connection
/// and the photo is not sent anywhere. Kept apart from the scan screen so
/// tests can stand in for the camera.
class ReceiptReader {
  final ImagePicker _picker = ImagePicker();

  // Made on first use, so a reader that never reads needs no closing.
  TextRecognizer? _recognizer;

  /// Takes a photo or picks one from the gallery. Null when the user backs
  /// out without choosing one.
  Future<String?> pickPhoto(ImageSource source) async {
    final image = await _picker.pickImage(source: source);
    return image?.path;
  }

  /// All the text found in the photo at [path], in reading order, or '' when
  /// there is none.
  Future<String> readText(String path) async {
    final recognizer = _recognizer ??= TextRecognizer();
    final result = await recognizer.processImage(
      InputImage.fromFile(File(path)),
    );
    final pieces = [
      for (final block in result.blocks)
        for (final line in block.lines) (line.text, line.boundingBox),
    ];
    return readingOrder(pieces).join('\n').trim();
  }

  void close() {
    _recognizer?.close();
  }
}

/// Puts receipt text back the way it is printed: rows from top to bottom,
/// with the pieces of one row, such as an item and its price, left to right
/// on the same line.
///
/// The reader groups text into blocks, so on its own it lists every item name
/// and then every price.
@visibleForTesting
List<String> readingOrder(List<(String, Rect)> pieces) {
  final byHeight = [...pieces]
    ..sort((a, b) => a.$2.center.dy.compareTo(b.$2.center.dy));

  final rows = <List<(String, Rect)>>[];
  for (final piece in byHeight) {
    final row = rows.isEmpty ? null : rows.last;
    // The same row when the middles are within half a line of each other,
    // which also allows for a slightly tilted photo.
    if (row != null &&
        (piece.$2.center.dy - _middle(row)).abs() <
            piece.$2.height.clamp(1, double.infinity) / 2) {
      row.add(piece);
    } else {
      rows.add([piece]);
    }
  }

  return [
    for (final row in rows)
      (row..sort((a, b) => a.$2.left.compareTo(b.$2.left)))
          .map((piece) => piece.$1.trim())
          .where((text) => text.isNotEmpty)
          .join('  '),
  ].where((line) => line.isNotEmpty).toList();
}

double _middle(List<(String, Rect)> row) =>
    row.map((piece) => piece.$2.center.dy).reduce((a, b) => a + b) / row.length;
