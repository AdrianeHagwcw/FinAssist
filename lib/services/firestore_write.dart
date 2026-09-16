import 'package:flutter/foundation.dart';

/// Starts a Firestore write without waiting for the server to confirm it.
///
/// Firestore applies the change to its local cache immediately (so streams
/// update right away) and queues it for the server. Awaiting the returned
/// future would hang while offline, so callers should not wait on it.
void commitFirestoreWrite(Future<void> write, String description) {
  write.catchError((Object error) {
    debugPrint('Firestore write failed ($description): $error');
  });
}
