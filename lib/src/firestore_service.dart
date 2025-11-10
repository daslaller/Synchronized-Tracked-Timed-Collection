import 'dart:async';

import 'package:synchronized_tracked_time_list/synchronized_tracked_time_list.dart';

typedef FirestoreWriteFn =
    Future<void> Function(String docId, Map<String, dynamic> payload);

class FirestoreCollectionWriter {
  final FirestoreWriteFn setDocument;
  final FirestoreWriteFn updateDocument;

  const FirestoreCollectionWriter({
    required this.setDocument,
    required this.updateDocument,
  });
}

class FirebaseSyncService<T> {
  final SynchronizedTimedSet<T> _timedSet;
  final FirestoreCollectionWriter _collection;
  final String Function(T item) _idProvider;
  final Map<String, dynamic> Function(T item) _serializer;
  StreamSubscription? _subscription;

  FirebaseSyncService({
    required SynchronizedTimedSet<T> timedSet,
    required FirestoreCollectionWriter collection,
    required String Function(T item) idProvider,
    required Map<String, dynamic> Function(T item) serializer,
  }) : _timedSet = timedSet,
       _collection = collection,
       _idProvider = idProvider,
       _serializer = serializer {
    _listenToChanges();
  }

  void _listenToChanges() {
    _subscription = _timedSet.events.listen((event) {
      switch (event.type) {
        case ChangeType.added:
          _handleItemAdded(event.value, event.entry!);
          break;
        case ChangeType.modified:
          _handleItemModified(event.value);
          break;
        case ChangeType.removed:
          _handleItemRemovedOrExpired(event.value, 'removed');
          break;
        case ChangeType.expired:
          _handleItemRemovedOrExpired(event.value, 'expired');
          break;
      }
    });
  }

  Future<void> _handleItemAdded(T item, TimedEntry<T> entry) async {
    final docId = _idProvider(item);
    final payload = {
      ..._serializer(item),
      'syncStatus': 'active',
      'addedAt': entry.addedAt, // Passed directly as DateTime
      'expiresAt': entry.expiresAt, // Passed directly as DateTime
      'lastModifiedAt': DateTime.now(),
    };
    print("🔥 Firebase SET: doc('$docId') -> status: active");
    await _collection.setDocument(docId, payload);
  }

  Future<void> _handleItemModified(T item) async {
    final docId = _idProvider(item);
    final payload = {..._serializer(item), 'lastModifiedAt': DateTime.now()};
    print("🔥 Firebase UPDATE: doc('$docId') -> modified content");
    await _collection.updateDocument(docId, payload);
  }

  Future<void> _handleItemRemovedOrExpired(T item, String status) async {
    final docId = _idProvider(item);
    final payload = {
      'syncStatus': status, // 'removed' or 'expired'
      'endedAt': DateTime.now(),
    };
    print("🔥 Firebase UPDATE: doc('$docId') -> status: $status");
    await _collection.updateDocument(docId, payload);
  }

  void dispose() {
    _subscription?.cancel();
    print("FirebaseSyncService disposed.");
  }
}
