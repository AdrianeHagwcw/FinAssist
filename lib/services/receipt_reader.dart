import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../models/expense_guess.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';

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

/// A long receipt photographed in parts, as one text: the parts top to
/// bottom, leaving out lines repeated where one photo overlaps the next.
String joinReceiptParts(List<String> parts) {
  final lines = <String>[];
  for (final part in parts) {
    final next = _linesOf(part);
    lines.addAll(next.skip(_overlap(lines, next)));
  }
  return lines.join('\n');
}

/// Where a newly read [part] belongs among the [parts] read so far, so
/// photos taken out of order still read top to bottom.
///
/// Photos that overlap settle it: the part goes after the one it continues,
/// or before the one that continues it. Otherwise a part starting like the
/// top of a receipt goes first, and one without a total goes before a last
/// part that has it. With nothing to go on, it goes last.
int placeForPart(List<String> parts, String part) {
  final lines = _linesOf(part);
  for (var i = parts.length - 1; i >= 0; i--) {
    if (_overlap(_linesOf(parts[i]), lines) > 0) return i + 1;
  }
  for (var i = 0; i < parts.length; i++) {
    if (_overlap(lines, _linesOf(parts[i])) > 0) return i;
  }

  if (parts.isEmpty) return 0;
  if (startsLikeReceiptTop(part) && !startsLikeReceiptTop(parts.first)) {
    return 0;
  }
  if (!hasReceiptTotal(part) && hasReceiptTotal(parts.last)) {
    return parts.length - 1;
  }
  return parts.length;
}

/// Why [part] looks like it is from a different receipt than the [parts]
/// read so far, or null when it may well belong.
///
/// A part that overlaps another always belongs. Otherwise a different
/// receipt shows in a store name of its own on a whole receipt, a different
/// total, a different date, or a second "Official Receipt" heading.
String? anotherReceiptReason(List<String> parts, String part, {DateTime? now}) {
  if (parts.isEmpty) return null;
  final lines = _linesOf(part);
  for (final other in parts) {
    final otherLines = _linesOf(other);
    if (_overlap(otherLines, lines) > 0 || _overlap(lines, otherLines) > 0) {
      return null;
    }
  }

  final mine = guessFromReceipt(part, categories: const [], now: now);
  final theirs = guessFromReceipt(
    joinReceiptParts(parts),
    categories: const [],
    now: now,
  );

  final store = storeAtTop(part);
  final theirStore = storeAtTop(parts.first);
  if (store != null &&
      theirStore != null &&
      mine.amount != null &&
      store.toLowerCase() != theirStore.toLowerCase()) {
    return 'It is from $store, not $theirStore.';
  }
  if (mine.amount != null &&
      theirs.amount != null &&
      (mine.amount! - theirs.amount!).abs() >= 0.01) {
    return 'Its total is ${formatPeso(mine.amount!)}, not '
        '${formatPeso(theirs.amount!)}.';
  }
  if (mine.date != null && theirs.date != null && mine.date != theirs.date) {
    return 'It is dated ${formatShortDate(mine.date!)}, not '
        '${formatShortDate(theirs.date!)}.';
  }
  if (startsLikeReceiptTop(part) && parts.any(startsLikeReceiptTop)) {
    return 'It starts like a new receipt.';
  }
  return null;
}

List<String> _linesOf(String part) => [
  for (final line in part.split('\n'))
    if (line.trim().isNotEmpty) line.trim(),
];

/// How many lines at the start of [next] repeat the end of [before]. At
/// least two must agree, so an item bought twice isn't taken for overlap.
int _overlap(List<String> before, List<String> next) {
  final most = before.length < next.length ? before.length : next.length;
  for (var size = most; size >= 2; size--) {
    var same = true;
    for (var i = 0; i < size && same; i++) {
      same = _sameLine(before[before.length - size + i], next[i]);
    }
    if (same) return size;
  }
  return 0;
}

/// Whether two lines read from different photos are the same printed line.
/// The reader can misread a character between photos ("x10" as "x1e"), so
/// one difference in every ten characters is allowed; short lines must
/// match exactly.
bool _sameLine(String a, String b) {
  String plain(String line) =>
      line.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final x = plain(a), y = plain(b);
  if (x == y) return true;

  final allowed = (x.length > y.length ? x.length : y.length) ~/ 10;
  if (allowed == 0 || (x.length - y.length).abs() > allowed) return false;

  // Edits needed to turn one into the other, row by row.
  var previous = List<int>.generate(y.length + 1, (i) => i);
  for (var i = 1; i <= x.length; i++) {
    final current = List<int>.filled(y.length + 1, i);
    for (var j = 1; j <= y.length; j++) {
      final replace = previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1);
      final remove = previous[j] + 1;
      final insert = current[j - 1] + 1;
      current[j] = replace < remove
          ? (replace < insert ? replace : insert)
          : (remove < insert ? remove : insert);
    }
    previous = current;
  }
  return previous[y.length] <= allowed;
}
