import 'dart:async';
import 'dart:developer';

enum ChangeType { added, removed, modified, expired }

class TimedEntry<T> {
  final T value;
  final DateTime addedAt;
  final Duration maxLifetime;

  TimedEntry(this.value, this.addedAt, this.maxLifetime);

  Duration get elapsed => DateTime.now().difference(addedAt);
  DateTime get expiresAt => addedAt.add(maxLifetime);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
  Duration get timeUntilExpiry => expiresAt.difference(DateTime.now());

  @override
  String toString() =>
      '$value (elapsed: ${elapsed.inMilliseconds}ms, expires in: ${timeUntilExpiry.inMilliseconds}ms)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TimedEntry<T> && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;
}

class ChangeEvent<T> {
  final ChangeType type;
  final T value;
  final TimedEntry<T>? entry;
  final Duration? previousElapsed;

  ChangeEvent(this.type, this.value, {this.entry, this.previousElapsed});

  @override
  String toString() {
    return switch (type) {
      ChangeType.added =>
        'ADDED: $value (max lifetime: ${entry?.maxLifetime.inMilliseconds}ms)',
      ChangeType.removed =>
        'REMOVED: $value (was present for ${previousElapsed?.inMilliseconds}ms)',
      ChangeType.modified => 'MODIFIED: $value',
      ChangeType.expired =>
        'EXPIRED: $value (lived for ${previousElapsed?.inMilliseconds}ms)',
    };
  }
}

class SynchronizedTimedSet<T> {
  final Map<T, TimedEntry<T>> _entries = {};
  final StreamController<ChangeEvent<T>> _changeController =
      StreamController.broadcast();
  late Timer? _cleanupTimer;
  final Duration _cleanupInterval;
  bool _isCleaningUp = false;
  final int _maxBatchSize;
  final Object? Function(T item)? _identityProvider;

  SynchronizedTimedSet({
    Duration cleanupInterval = const Duration(milliseconds: 100),
    int maxBatchSize = 1000, // Limit processing batch size
    Object? Function(T item)? identityProvider,
  }) : _cleanupInterval = cleanupInterval,
       _maxBatchSize = maxBatchSize,
       _identityProvider = identityProvider {
    _startCleanupTimer();
  }

  /// Stream of change events (added, removed, modified, expired)
  Stream<ChangeEvent<T>> get events => _changeController.stream;

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(
      _cleanupInterval,
      (_) => _removeExpiredEntriesAsync(),
    );
  }

  /// Asynchronous cleanup that yields control periodically
  Future<void> _removeExpiredEntriesAsync() async {
    // Prevent concurrent execution
    if (_isCleaningUp) return;

    _isCleaningUp = true;
    try {
      await _performAsyncCleanup();
    } finally {
      _isCleaningUp = false;
    }
  }

  /// Synchronous cleanup for immediate needs (non-blocking for small sets)
  void _removeExpiredEntries() {
    // For small datasets, use synchronous cleanup
    if (_entries.length <= _maxBatchSize ~/ 4) {
      _performSyncCleanup();
      return;
    }

    // For large datasets, schedule async cleanup if not already running
    if (!_isCleaningUp) {
      _removeExpiredEntriesAsync();
    }
  }

  void _performSyncCleanup() {
    if (_isCleaningUp) return;

    _isCleaningUp = true;
    final now = DateTime.now();
    try {
      final expired = <MapEntry<T, TimedEntry<T>>>[];

      // Single-pass collection with early termination for performance
      for (final entry in _entries.entries) {
        if (entry.value.isExpired) {
          expired.add(entry);
          // Limit batch size to prevent blocking
          if (expired.length >= _maxBatchSize) break;
        }
      }

      // Remove and dispatch events
      for (final entry in expired) {
        _entries.remove(entry.key);
        // Use addSync for immediate dispatch (non-blocking)
        if (!_changeController.isClosed) {
          _changeController.add(
            ChangeEvent(
              ChangeType.expired,
              entry.key,
              previousElapsed: entry.value.elapsed,
            ),
          );
        }
      }
    } finally {
      log('cleanup took: ${DateTime.now().difference(now).inMilliseconds}ms');
      _isCleaningUp = false;
    }
  }

  Future<void> _performAsyncCleanup() async {
    final now = DateTime.now();
    final allEntries = _entries.entries.toList();
    var processedCount = 0;

    for (int i = 0; i < allEntries.length; i += _maxBatchSize) {
      if (_changeController.isClosed) break;

      final batchEnd = (i + _maxBatchSize).clamp(0, allEntries.length);
      final batch = allEntries.sublist(i, batchEnd);
      final expired = <MapEntry<T, TimedEntry<T>>>[];

      // Process batch
      for (final entry in batch) {
        if (entry.value.isExpired) {
          expired.add(entry);
        }
      }

      // Remove expired entries from this batch
      for (final entry in expired) {
        _entries.remove(entry.key);
        if (!_changeController.isClosed) {
          _changeController.add(
            ChangeEvent(
              ChangeType.expired,
              entry.key,
              previousElapsed: entry.value.elapsed,
            ),
          );
        }
      }

      processedCount += batch.length;

      // Yield control every batch to prevent blocking
      if (processedCount < allEntries.length) {
        await Future.delayed(Duration.zero); // Yield to event loop
      }
    }
    log(
      'batched cleanup took: ${DateTime.now().difference(now).inMilliseconds}ms',
    );
  }

  /// Synchronize with a new set of items, each with their max lifetime
  void synchronize(Map<T, Duration> newItems) {
    if (newItems.isEmpty) {
      _clearAll();
      return;
    }

    // First remove expired entries
    _removeExpiredEntries();

    final now = DateTime.now();
    final processedItems = <T>{};

    // Process each new item
    for (final MapEntry(:key, :value) in newItems.entries) {
      final newItem = key;
      final maxLifetime = value;

      // Check if we already have this item by comparing keys (identity)
      TimedEntry<T>? existingEntry;
      T? existingKey;

      for (final entry in _entries.entries) {
        if (entry.key.runtimeType == newItem.runtimeType &&
            _getIdentityKey(entry.key) == _getIdentityKey(newItem)) {
          existingEntry = entry.value;
          existingKey = entry.key;
          break;
        }
      }

      if (existingEntry == null) {
        // New item - add it
        final entry = TimedEntry(newItem, now, maxLifetime);
        _entries[newItem] = entry;
        _changeController.add(
          ChangeEvent(ChangeType.added, newItem, entry: entry),
        );
      } else {
        // Item exists - check if it's modified
        final wasModified =
            existingKey !=
            newItem; // Dart's == operator will detect content changes

        // Remove old entry and add new one (to handle potential key changes)
        _entries.remove(existingKey);
        final newEntry = TimedEntry(
          newItem,
          existingEntry.addedAt,
          maxLifetime,
        );
        _entries[newItem] = newEntry;

        if (wasModified) {
          _changeController.add(
            ChangeEvent(ChangeType.modified, newItem, entry: newEntry),
          );
        }
      }

      processedItems.add(newItem);
    }

    // Find items to remove (in current but not in new)
    final currentItems = _entries.keys.toList();
    for (final currentItem in currentItems) {
      bool found = false;
      for (final newItem in processedItems) {
        if (currentItem.runtimeType == newItem.runtimeType &&
            _getIdentityKey(currentItem) == _getIdentityKey(newItem)) {
          found = true;
          break;
        }
      }

      if (!found) {
        final entry = _entries[currentItem]!;
        _entries.remove(currentItem);
        _changeController.add(
          ChangeEvent(
            ChangeType.removed,
            currentItem,
            previousElapsed: entry.elapsed,
          ),
        );
      }
    }
  }

  /// Override this method to define how to identify items of type T
  /// Default implementation uses toString(), but you can override for custom identity
  dynamic _getIdentityKey(T item) {
    final customIdentity = _identityProvider;
    if (customIdentity != null) return customIdentity(item);

    // For data classes, you might want to use a specific ID field
    // This is a simple default that works for many cases
    if (item is Map) return item['id'] ?? item.toString();
    if (item.toString().contains('Instance of')) return item.hashCode;
    return item.toString();
  }

  /// Convenience method for synchronizing with items having the same lifetime
  void synchronizeSet(Iterable<T> newItems, Duration maxLifetime) {
    final itemMap = <T, Duration>{};
    for (final item in newItems) {
      itemMap[item] = maxLifetime;
    }
    synchronize(itemMap);
  }

  void _clearAll() {
    final toRemove = _entries.keys.toList();
    for (final item in toRemove) {
      final entry = _entries[item]!;
      _changeController.add(
        ChangeEvent(ChangeType.removed, item, previousElapsed: entry.elapsed),
      );
    }
    _entries.clear();
  }

  /// Get all current entries with timing info (excludes expired)
  List<TimedEntry<T>> get entries {
    _removeExpiredEntries();
    return _entries.values.toList();
  }

  /// Get just the values (excludes expired)
  Set<T> get values {
    _removeExpiredEntries();
    return _entries.keys.toSet();
  }

  /// Get entry for specific value
  TimedEntry<T>? getEntry(T value) {
    final entry = _entries[value];
    if (entry != null && entry.isExpired) {
      _entries.remove(value);
      _changeController.add(
        ChangeEvent(ChangeType.expired, value, previousElapsed: entry.elapsed),
      );
      return null;
    }
    return entry;
  }

  /// Get entries that will expire within the specified duration
  List<TimedEntry<T>> getEntriesExpiringWithin(Duration duration) {
    _removeExpiredEntries();
    final cutoff = DateTime.now().add(duration);
    return _entries.values
        .where((entry) => entry.expiresAt.isBefore(cutoff))
        .toList();
  }

  /// Get entries older than specified duration
  List<TimedEntry<T>> getEntriesOlderThan(Duration duration) {
    _removeExpiredEntries();
    final cutoff = DateTime.now().subtract(duration);
    return _entries.values
        .where((entry) => entry.addedAt.isBefore(cutoff))
        .toList();
  }

  /// Get entries newer than specified duration
  List<TimedEntry<T>> getEntriesNewerThan(Duration duration) {
    _removeExpiredEntries();
    final cutoff = DateTime.now().subtract(duration);
    return _entries.values
        .where((entry) => entry.addedAt.isAfter(cutoff))
        .toList();
  }

  /// Clear all entries
  void clear() => synchronize({});

  /// Check if empty (excludes expired)
  bool get isEmpty {
    _removeExpiredEntries();
    return _entries.isEmpty;
  }

  /// Get count of entries (excludes expired)
  int get length {
    _removeExpiredEntries();
    return _entries.length;
  }

  /// Contains check (excludes expired)
  bool contains(T value) {
    final entry = _entries[value];
    if (entry != null && entry.isExpired) {
      _entries.remove(value);
      _changeController.add(
        ChangeEvent(ChangeType.expired, value, previousElapsed: entry.elapsed),
      );
      return false;
    }
    return entry != null;
  }

  /// Force immediate cleanup of expired entries
  void forceCleanup() {
    _removeExpiredEntries();
  }

  /// Dispose resources
  void dispose() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;

    // Final cleanup before closing
    if (!_isCleaningUp) {
      _removeExpiredEntries();
    }

    _changeController.close();
  }

  @override
  String toString() {
    _removeExpiredEntries();
    if (_entries.isEmpty) return 'SynchronizedTimedSet: {}';
    return 'SynchronizedTimedSet: {${entries.join(', ')}}';
  }
}

/* // Custom TimedSet for User that uses ID for identity
class UserTimedSet extends SynchronizedTimedSet<Call> {
  UserTimedSet({super.cleanupInterval, super.maxBatchSize});
  
  @override
  dynamic _getIdentityKey(Call item) => item.uniqueIdentfier;
}
 */
// Example usage
