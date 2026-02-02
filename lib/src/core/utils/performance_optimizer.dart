import 'dart:async';
import 'dart:convert';

/// Performance Optimizer for PostHog
/// Provides utilities to optimize performance and reduce overhead
class PostHogPerformanceOptimizer {
  /// Throttle a function to only execute once per interval
  static Timer? _throttleTimer;
  static DateTime? _lastExecution;

  static T Function(T) throttle<T>(
    T Function() callback,
    Duration interval, {
    bool trailing = false,
  }) {
    return (T result) {
      final now = DateTime.now();

      if (_lastExecution == null ||
          now.difference(_lastExecution!) >= interval) {
        _lastExecution = now;
        return callback();
      }

      if (trailing && _throttleTimer == null) {
        _throttleTimer = Timer(interval, () {
          _lastExecution = DateTime.now();
          callback();
          _throttleTimer = null;
        });
      }

      return result;
    };
  }

  /// Debounce a function to only execute after a pause
  static Timer? _debounceTimer;

  static void debounce(
    void Function() callback,
    Duration duration,
  ) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(duration, callback);
  }

  /// Batch operations to reduce execution frequency
  static void batch<T>(
    List<T> items,
    Future<void> Function(List<T>) processor, {
    Duration delay = const Duration(milliseconds: 100),
    int batchSize = 50,
  }) async {
    for (var i = 0; i < items.length; i += batchSize) {
      final end = (i + batchSize < items.length) ? i + batchSize : items.length;
      final batch = items.sublist(i, end);

      await processor(batch);

      // Add small delay between batches to avoid overwhelming the system
      if (end < items.length) {
        await Future.delayed(delay);
      }
    }
  }

  /// Memory-efficient JSON encoding with fallback
  static String? safeJsonEncode(Map<String, dynamic> data) {
    try {
      // Remove circular references
      final sanitized = _sanitizeMap(data);
      return jsonEncode(sanitized);
    } catch (e) {
      return null;
    }
  }

  /// Sanitize map to prevent circular references
  static Map<String, dynamic> _sanitizeMap(
    Map<String, dynamic> map, {
    Set<Object>? visited,
  }) {
    visited ??= {};
    final result = <String, dynamic>{};

    for (final entry in map.entries) {
      final value = entry.value;

      if (value is Map) {
        if (visited.contains(value)) {
          result[entry.key] = '[Circular]';
          continue;
        }
        visited.add(value);
        result[entry.key] = _sanitizeMap(
          value.cast<String, dynamic>(),
          visited: visited,
        );
      } else if (value is List) {
        result[entry.key] = _sanitizeList(value, visited: visited);
      } else if (value is DateTime) {
        result[entry.key] = value.toIso8601String();
      } else {
        result[entry.key] = value;
      }
    }

    return result;
  }

  /// Sanitize list to prevent circular references
  static List<dynamic> _sanitizeList(
    List list, {
    required Set<Object> visited,
  }) {
    final result = <dynamic>[];

    for (final item in list) {
      if (item is Map) {
        if (visited.contains(item)) {
          result.add('[Circular]');
          continue;
        }
        visited.add(item);
        result.add(_sanitizeMap(item.cast<String, dynamic>(), visited: visited));
      } else if (item is List) {
        result.add(_sanitizeList(item, visited: visited));
      } else if (item is DateTime) {
        result.add(item.toIso8601String());
      } else {
        result.add(item);
      }
    }

    return result;
  }
}

/// Lightweight metrics tracking
class PostHogPerformanceMetrics {
  int _eventCount = 0;
  int _apiCallCount = 0;
  final DateTime _startTime = DateTime.now();
  final Map<String, int> _methodCounts = {};

  void recordEvent(String eventName) {
    _eventCount++;
    _methodCounts[eventName] = (_methodCounts[eventName] ?? 0) + 1;
  }

  void recordApiCall() {
    _apiCallCount++;
  }

  Map<String, dynamic> getStats() {
    return {
      'totalEvents': _eventCount,
      'totalApiCalls': _apiCallCount,
      'uptimeSeconds': DateTime.now().difference(_startTime).inSeconds,
      'eventCounts': Map<String, int>.from(_methodCounts),
      'averageEventsPerSecond': _eventCount /
          (DateTime.now().difference(_startTime).inSeconds + 1),
    };
  }

  void reset() {
    _eventCount = 0;
    _apiCallCount = 0;
    _methodCounts.clear();
  }
}
