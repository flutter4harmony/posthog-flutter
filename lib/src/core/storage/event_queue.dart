import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Event Queue Manager
/// Manages in-memory and persistent storage of analytics events
class EventQueue {
  final SharedPreferences _prefs;
  final String _queueKey;
  final int _maxQueueSize;
  final List<Map<String, dynamic>> _memoryQueue = [];

  Timer? _flushTimer;

  EventQueue({
    required SharedPreferences prefs,
    String queueKey = 'posthog_event_queue',
    int maxQueueSize = 1000,
  })  : _prefs = prefs,
        _queueKey = queueKey,
        _maxQueueSize = maxQueueSize {
    _loadFromDisk();
  }

  /// Add event to queue
  /// Returns true if the queue should be flushed immediately
  Future<bool> enqueue(Map<String, dynamic> event) async {
    _memoryQueue.add(event);

    // Save to disk
    await _saveToDisk();

    // Check if we should flush
    if (_memoryQueue.length >= _maxQueueSize) {
      return true;
    }

    return false;
  }

  /// Get and clear all events from queue
  List<Map<String, dynamic>> drain() {
    final events = List<Map<String, dynamic>>.from(_memoryQueue);
    _memoryQueue.clear();
    _saveToDisk();
    return events;
  }

  /// Get current queue size
  int get size => _memoryQueue.length;

  /// Check if queue is empty
  bool get isEmpty => _memoryQueue.isEmpty;

  /// Clear all events from queue
  Future<void> clear() async {
    _memoryQueue.clear();
    await _prefs.remove(_queueKey);
  }

  /// Load queue from disk
  void _loadFromDisk() {
    try {
      final queueJson = _prefs.getString(_queueKey);
      if (queueJson != null) {
        final List<dynamic> decoded = jsonDecode(queueJson);
        _memoryQueue.clear();
        _memoryQueue.addAll(
          decoded.cast<Map<String, dynamic>>(),
        );
      }
    } catch (e) {
      // Ignore parsing errors
    }
  }

  /// Save queue to disk
  Future<void> _saveToDisk() async {
    try {
      final queueJson = jsonEncode(_memoryQueue);
      await _prefs.setString(_queueKey, queueJson);
    } catch (e) {
      // Ignore save errors
    }
  }

  /// Start auto flush timer
  /// Flushes events at the specified interval if the flush callback is provided
  void startAutoFlush(
    Duration interval,
    Future<void> Function(List<Map<String, dynamic>>) flushCallback,
  ) {
    stopAutoFlush();

    _flushTimer = Timer.periodic(interval, (_) async {
      if (_memoryQueue.isNotEmpty) {
        final events = drain();
        try {
          await flushCallback(events);
        } catch (e) {
          // Failed to send, re-add to queue
          for (final event in events) {
            _memoryQueue.add(event);
          }
        }
      }
    });
  }

  /// Stop auto flush timer
  void stopAutoFlush() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  /// Dispose resources
  void dispose() {
    stopAutoFlush();
  }
}
