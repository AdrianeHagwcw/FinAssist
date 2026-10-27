import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/price_references.dart';

/// Reads the prices the web scraper saved (see scraper/README.md).
///
/// Offline, Firestore answers from the phone's saved copy of the last read.
/// Null when they can't be read at all; the assistant then answers big
/// purchase questions from the user's own records only.
Future<PriceReferences?> loadPriceReferences({
  FirebaseFirestore? firestore,
}) async {
  try {
    final snapshot = await (firestore ?? FirebaseFirestore.instance)
        .collection('priceReferences')
        .get();
    if (snapshot.docs.isEmpty) return null;
    return PriceReferences.fromDocuments({
      for (final document in snapshot.docs) document.id: document.data(),
    });
  } on Object catch (error) {
    debugPrint('FinAssist price references unavailable: $error');
    return null;
  }
}
