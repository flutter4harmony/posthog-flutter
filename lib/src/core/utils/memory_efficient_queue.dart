import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Memory-efficient event queue
/// Uses disk overflow to prevent memory issues with large queues
class MemoryEfficientQueue<T> {
  final int _memoryLimit;
  final String _diskKey;
  final SharedPreferences _prefs;

  final List<T> _memoryQueue = [];
  int _diskQueueSize = 0;

  MemoryEfficientQueue({
    required SharedPreferences prefs,
    String diskKey = 'posthog_overflow_queue',
    int memoryLimit = 100,
  })  : _prefs = prefs,
        _diskKey = diskKey,
        _memoryLimit = memoryLimit {
    _loadDiskQueueSize();
  }

  /// Add item to queue
  Future<void> add(T item) async {
    if (_memoryQueue.length >= _memoryLimit) {
      // Move oldest items to disk
      await _overflowToDisk();
    }
    _memoryQueue.add(item);
  }

  /// Get and remove all items
  List<T> drain() {
    final items = List<T>.from(_memoryQueue);
    _memoryQueue.clear();

    // Also drain from disk
    final diskItems = _drainDisk();
    items.addAll(diskItems);

    return items;
  }

  /// Get queue size (memory + disk)
  int get size => _memoryQueue.length + _diskQueueSize;

  /// Check if queue is empty
  bool get isEmpty => _memoryQueue.isEmpty && _diskQueueSize == 0;

  /// Clear all items
  Future<void> clear() async {
    _memoryQueue.clear();
    await _prefs.remove(_diskKey);
    _diskQueueSize = 0;
  }

  /// Overflow items to disk
  Future<void> _overflowToDisk() async {
    if (_memoryQueue.isEmpty) return;

    // Take half of memory queue and move to disk
    final overflowCount = _memoryLimit ~/ 2;
    final overflowItems = _memoryQueue.sublist(0, overflowCount);
    _memoryQueue.removeRange(0, overflowCount);

    // Encode and save to disk
    try {
      final encoded = jsonEncode(overflowItems);
      await _prefs.setString(_diskKey, encoded);
      _diskQueueSize += overflowItems.length;
    } catch (e) {
      // If disk save fails, just keep in memory
      _memoryQueue.insertAll(0, overflowItems);
    }
  }

  /// Drain items from disk
  List<T> _drainDisk() {
    try {
      final data = _prefs.getString(_diskKey);
      if (data != null) {
        final List<dynamic> decoded = jsonDecode(data);
        _prefs.remove(_diskKey);
        _diskQueueSize = 0;
        return decoded.cast<T>();
      }
    } catch (e) {
      // Ignore errors
    }
    return [];
  }

  /// Load disk queue size
  void _loadDiskQueueSize() {
    try {
      final data = _prefs.getString(_diskKey);
      if (data != null) {
        final List<dynamic> decoded = jsonDecode(data);
        _diskQueueSize = decoded.length;
      }
    } catch (e) {
      // Ignore errors
    }
  }
}
