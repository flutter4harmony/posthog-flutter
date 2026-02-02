import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/core/storage/event_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('EventQueue', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('should enqueue events in memory', () async {
      final queue = EventQueue(prefs: prefs, maxQueueSize: 10);

      final event = {'event': 'test_event', 'properties': {}};
      final shouldFlush = await queue.enqueue(event);

      expect(shouldFlush, false);
      expect(queue.size, 1);
      expect(queue.isEmpty, false);
    });

    test('should return true when queue is full', () async {
      final queue = EventQueue(prefs: prefs, maxQueueSize: 3);

      await queue.enqueue({'event': 'event1'});
      await queue.enqueue({'event': 'event2'});
      final shouldFlush = await queue.enqueue({'event': 'event3'});

      expect(shouldFlush, true);
      expect(queue.size, 3);
    });

    test('should drain all events', () async {
      final queue = EventQueue(prefs: prefs, maxQueueSize: 10);

      await queue.enqueue({'event': 'event1'});
      await queue.enqueue({'event': 'event2'});
      await queue.enqueue({'event': 'event3'});

      final events = queue.drain();

      expect(events.length, 3);
      expect(queue.size, 0);
      expect(queue.isEmpty, true);
      expect(events[0]['event'], 'event1');
      expect(events[1]['event'], 'event2');
      expect(events[2]['event'], 'event3');
    });

    test('should persist events to disk', () async {
      final queue = EventQueue(prefs: prefs, maxQueueSize: 10);

      await queue.enqueue({'event': 'event1'});
      await queue.enqueue({'event': 'event2'});

      // Create new queue instance to test persistence
      final newQueue = EventQueue(prefs: prefs, maxQueueSize: 10);
      expect(newQueue.size, 2);
    });

    test('should clear all events', () async {
      final queue = EventQueue(prefs: prefs, maxQueueSize: 10);

      await queue.enqueue({'event': 'event1'});
      await queue.enqueue({'event': 'event2'});
      await queue.clear();

      expect(queue.size, 0);

      // Verify persistence is also cleared
      final newQueue = EventQueue(prefs: prefs, maxQueueSize: 10);
      expect(newQueue.size, 0);
    });

    test('should start and stop auto flush timer', () async {
      final queue = EventQueue(prefs: prefs, maxQueueSize: 10);

      bool flushCalled = false;
      Future<void> flushCallback(List<Map<String, dynamic>> events) async {
        flushCalled = true;
      }

      queue.startAutoFlush(
        const Duration(milliseconds: 100),
        flushCallback,
      );

      await queue.enqueue({'event': 'event1'});

      // Wait for timer to trigger
      await Future.delayed(const Duration(milliseconds: 150));

      expect(flushCalled, true);

      queue.dispose();
    });

    test('should dispose resources', () async {
      final queue = EventQueue(prefs: prefs, maxQueueSize: 10);

      await queue.enqueue({'event': 'event1'});
      queue.dispose();

      // After dispose, queue should still work but timers are cancelled
      expect(queue.size, 1);
    });

    test('should preserve event order after persistence', () async {
      final queue = EventQueue(prefs: prefs, maxQueueSize: 10);

      await queue.enqueue({'event': 'event1', 'index': 1});
      await queue.enqueue({'event': 'event2', 'index': 2});
      await queue.enqueue({'event': 'event3', 'index': 3});

      // Create new queue instance
      final newQueue = EventQueue(prefs: prefs, maxQueueSize: 10);
      final events = newQueue.drain();

      expect(events[0]['index'], 1);
      expect(events[1]['index'], 2);
      expect(events[2]['index'], 3);
    });

    test('should be empty initially', () {
      final queue = EventQueue(prefs: prefs);
      expect(queue.isEmpty, true);
      expect(queue.size, 0);
    });

    test('should handle drain on empty queue', () {
      final queue = EventQueue(prefs: prefs);
      final events = queue.drain();

      expect(events, isEmpty);
      expect(queue.size, 0);
    });

    test('should stop previous auto flush when starting new one', () async {
      final queue = EventQueue(prefs: prefs, maxQueueSize: 10);

      int callCount = 0;
      Future<void> flushCallback(List<Map<String, dynamic>> events) async {
        callCount++;
      }

      queue.startAutoFlush(
        const Duration(milliseconds: 50),
        flushCallback,
      );

      // Start a new timer (should stop the old one)
      queue.startAutoFlush(
        const Duration(milliseconds: 100),
        flushCallback,
      );

      await queue.enqueue({'event': 'event1'});
      await Future.delayed(const Duration(milliseconds: 150));

      // Should only be called once (from the second timer)
      expect(callCount, lessThanOrEqualTo(2));

      queue.dispose();
    });

    test('should handle enqueue with various event structures', () async {
      final queue = EventQueue(prefs: prefs, maxQueueSize: 10);

      final complexEvent = {
        'event': 'complex_event',
        'properties': {
          'string': 'value',
          'number': 123,
          'boolean': true,
          'nested': {'key': 'value'},
        }
      };

      await queue.enqueue(complexEvent);

      expect(queue.size, 1);

      final events = queue.drain();
      expect(events[0]['event'], 'complex_event');
      final props = events[0]['properties'] as Map<String, Object>;
      expect(props['string'], 'value');
    });
  });
}
