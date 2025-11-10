import 'dart:async';

import 'package:firedart/firedart.dart';

/// A client-side listener that displays real-time updates from Firestore.
class RealtimeStatusDisplay {
  final CollectionReference _collection;
  StreamSubscription<List<Document>>? _subscription;

  RealtimeStatusDisplay({required CollectionReference collection})
    : _collection = collection {
    _listenForUpdates();
  }

  void _listenForUpdates() {
    print("📡 (Client) Listening for real-time updates...");
    _subscription = _collection.stream.listen(
      (documents) {
        if (documents.isEmpty) {
          print("ℹ️ (Client) No active entries in collection yet.");
          return;
        }

        for (final document in documents) {
          final data = document.map;
          final phoneId = data['uniqueIdentfier'] ?? document.id;
          final status = data['status'] ?? data['syncStatus'];
          final caller = data['callerID'] ?? 'unknown';

          print(
            "🔄 (Client) call $phoneId => status: $status, caller: $caller",
          );
        }
      },
      onError: (error, stack) {
        print("❌ Error listening to client stream: $error");
        if (stack != null) {
          print(stack);
        }
      },
    );
  }

  void dispose() {
    _subscription?.cancel();
  }
}
