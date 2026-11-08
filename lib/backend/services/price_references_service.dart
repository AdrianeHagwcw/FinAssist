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
  bool forceServer = false,
}) async {
  final collection = (firestore ?? FirebaseFirestore.instance).collection(
    'priceReferences',
  );
  try {
    final snapshot = await collection.get(
      forceServer
          ? const GetOptions(source: Source.server)
          : const GetOptions(),
    );
    return _priceReferencesFromSnapshot(snapshot);
  } on Object catch (error) {
    if (forceServer) {
      debugPrint(
        'FinAssist live price refresh failed; trying Firestore cache: $error',
      );
      try {
        return _priceReferencesFromSnapshot(
          await collection.get(const GetOptions(source: Source.cache)),
        );
      } on Object catch (cacheError) {
        debugPrint(
          'FinAssist cached price references unavailable: $cacheError',
        );
      }
    }
    debugPrint('FinAssist price references unavailable: $error');
    return null;
  }
}

PriceReferences? _priceReferencesFromSnapshot(
  QuerySnapshot<Map<String, dynamic>> snapshot,
) {
  if (snapshot.docs.isEmpty) return null;
  return PriceReferences.fromDocuments({
    for (final document in snapshot.docs)
      document.id: {
        for (final entry in document.data().entries)
          entry.key: entry.value is Timestamp
              ? (entry.value as Timestamp).toDate().toIso8601String()
              : entry.value,
      },
  });
}
