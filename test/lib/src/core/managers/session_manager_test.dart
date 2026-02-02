import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/core/managers/session_manager.dart';

void main() {
  group('PostHogSessionManager', () {
    late PostHogSessionManager manager;
    late String? lastStartedSession;
    late String? lastEndedSession;

    setUp(() {
      lastStartedSession = null;
      lastEndedSession = null;

      manager = PostHogSessionManager(
        sessionTimeout: const Duration(milliseconds: 500),
        onSessionStart: (sessionId) {
          lastStartedSession = sessionId;
        },
        onSessionEnd: (sessionId) {
          lastEndedSession = sessionId;
        },
      );
    });

    tearDown(() {
      manager.dispose();
    });

    test('should create new session on first access', () {
      final sessionId = manager.getOrCreateSessionId();

      expect(sessionId, isNotEmpty);
      expect(lastStartedSession, sessionId);
    });

    test('should return same session within timeout', () {
      final sessionId1 = manager.getOrCreateSessionId();
      final sessionId2 = manager.getOrCreateSessionId();

      expect(sessionId1, equals(sessionId2));
      expect(lastStartedSession, sessionId1);
    });

    test('should create new session after timeout', () async {
      final sessionId1 = manager.getOrCreateSessionId();
      expect(lastStartedSession, sessionId1);

      // Wait for session to expire
      await Future.delayed(const Duration(milliseconds: 600));

      final sessionId2 = manager.getOrCreateSessionId();
      expect(sessionId2, isNot(equals(sessionId1)));
      expect(lastEndedSession, sessionId1);
      expect(lastStartedSession, sessionId2);
    });

    test('should update activity on recordActivity', () async {
      final sessionId1 = manager.getOrCreateSessionId();

      // Record activity before timeout
      await Future.delayed(const Duration(milliseconds: 300));
      manager.recordActivity();

      // Wait for original timeout
      await Future.delayed(const Duration(milliseconds: 300));

      // Should still be same session due to activity
      final sessionId2 = manager.getOrCreateSessionId();
      expect(sessionId1, equals(sessionId2));
      expect(lastEndedSession, isNull);
    });

    test('should provide sessionId property', () {
      expect(manager.sessionId, isNull);

      final sessionId = manager.getOrCreateSessionId();
      expect(manager.sessionId, sessionId);
    });

    test('should reset session', () {
      final sessionId1 = manager.getOrCreateSessionId();

      manager.reset();

      final sessionId2 = manager.getOrCreateSessionId();
      expect(sessionId2, isNot(equals(sessionId1)));
      expect(lastEndedSession, sessionId1);
      expect(lastStartedSession, sessionId2);
    });

    test('should handle multiple activity updates', () async {
      final sessionId = manager.getOrCreateSessionId();

      for (int i = 0; i < 3; i++) {
        await Future.delayed(const Duration(milliseconds: 200));
        manager.recordActivity();
      }

      // Session should still be active
      final currentSessionId = manager.getOrCreateSessionId();
      expect(currentSessionId, equals(sessionId));
    });

    test('should generate unique session IDs', () {
      manager.reset();

      final sessionId1 = manager.getOrCreateSessionId();
      manager.reset();
      final sessionId2 = manager.getOrCreateSessionId();
      manager.reset();
      final sessionId3 = manager.getOrCreateSessionId();

      expect(sessionId1, isNot(equals(sessionId2)));
      expect(sessionId2, isNot(equals(sessionId3)));
      expect(sessionId3, isNot(equals(sessionId1)));
    });

    test('should use default timeout when not specified', () {
      final defaultManager = PostHogSessionManager(
        onSessionStart: (_) {},
        onSessionEnd: (_) {},
      );

      // Can't directly check sessionTimeout, but we can verify it was created
      expect(defaultManager.sessionId, isNull);

      defaultManager.dispose();
    });

    test('should accept custom timeout', () {
      final customManager = PostHogSessionManager(
        sessionTimeout: const Duration(seconds: 10),
        onSessionStart: (_) {},
        onSessionEnd: (_) {},
      );

      // Verify manager was created successfully
      expect(customManager.sessionId, isNull);

      customManager.dispose();
    });

    test('should work without onSessionEnd callback', () {
      final noEndCallbackManager = PostHogSessionManager(
        sessionTimeout: const Duration(milliseconds: 100),
        onSessionStart: (sessionId) {
          lastStartedSession = sessionId;
        },
      );

      final sessionId = noEndCallbackManager.getOrCreateSessionId();
      expect(sessionId, isNotEmpty);
      expect(lastStartedSession, sessionId);

      noEndCallbackManager.dispose();
    });

    test('should call onSessionEnd when session expires', () async {
      final sessionId = manager.getOrCreateSessionId();
      expect(lastStartedSession, sessionId);

      await Future.delayed(const Duration(milliseconds: 600));

      manager.getOrCreateSessionId();

      expect(lastEndedSession, sessionId);
    });

    test('should handle rapid activity updates', () {
      final sessionId = manager.getOrCreateSessionId();

      for (int i = 0; i < 100; i++) {
        manager.recordActivity();
      }

      // Session should still be the same
      expect(manager.sessionId, equals(sessionId));
    });

    test('should cleanup on dispose', () {
      manager.getOrCreateSessionId();
      expect(manager.sessionId, isNotNull);

      manager.dispose();
      // After dispose, manager should be in a clean state
      // No specific assertions, just ensure no errors
    });

    test('should end session explicitly', () {
      final sessionId = manager.getOrCreateSessionId();
      expect(manager.sessionId, sessionId);

      manager.endSession();

      expect(manager.sessionId, isNull);
      expect(lastEndedSession, sessionId);
    });

    test('should set session timeout', () {
      manager.setSessionTimeout(const Duration(seconds: 5));
      // Can't directly check the timeout, but ensure no errors
      expect(manager.sessionId, isNull);
    });

    test('should generate valid session IDs', () {
      final sessionId = manager.getOrCreateSessionId();

      expect(sessionId, contains('-'));
      expect(sessionId.length, greaterThan(10));
    });
  });
}
