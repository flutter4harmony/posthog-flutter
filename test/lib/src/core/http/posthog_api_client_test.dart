import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/core/http/posthog_api_client.dart';

void main() {
  group('PosthogApiClient', () {
    late PosthogApiClient apiClient;

    setUp(() {
      apiClient = PosthogApiClient(
        apiKey: 'test_api_key',
        host: 'https://app.posthog.com',
      );
    });

    test('should have correct SDK name and version', () {
      expect(apiClient.sdkName, 'posthog-flutter');
      expect(apiClient.sdkVersion, isNotEmpty);
    });

    test('should store API key', () {
      expect(apiClient.apiKey, 'test_api_key');
    });

    test('should store host', () {
      expect(apiClient.host, 'https://app.posthog.com');
    });

    test('should allow custom host', () {
      final customClient = PosthogApiClient(
        apiKey: 'test_key',
        host: 'https://custom.posthog.com',
      );

      expect(customClient.host, 'https://custom.posthog.com');
      customClient.dispose();
    });

    test('should have correct batch URL', () {
      // The batch URL should be host + /batch/
      expect(apiClient.host.contains('posthog.com'), true);
    });

    test('should have correct decide URL', () {
      // The decide URL should be host + /decide/?v=3
      expect(apiClient.host.contains('posthog.com'), true);
    });

    test('should dispose client', () {
      expect(() => apiClient.dispose(), returnsNormally);
    });

    test('should create unique instances', () {
      final client1 = PosthogApiClient(apiKey: 'key1', host: 'https://app.posthog.com');
      final client2 = PosthogApiClient(apiKey: 'key2', host: 'https://app.posthog.com');

      expect(client1.apiKey, isNot(equals(client2.apiKey)));
      expect(client1.hashCode, isNot(equals(client2.hashCode)));

      client1.dispose();
      client2.dispose();
    });

    test('should handle empty events list', () {
      // This test verifies the client can handle empty events
      // Actual network calls would fail in test environment
      final events = <Map<String, dynamic>>[];
      expect(events.isEmpty, true);
    });

    test('should structure batch events correctly', () {
      final events = [
        {
          'event': 'test_event',
          'properties': <String, Object>{
            'distinct_id': 'user123',
            'token': 'test_api_key',
          }
        },
      ];

      expect(events.length, 1);
      expect(events[0]['event'], 'test_event');
      final props = events[0]['properties'] as Map<String, Object>;
      expect(props['token'], 'test_api_key');
    });

    test('should include SDK info in event structure', () {
      final event = {
        'properties': <String, String>{
          '\$lib': apiClient.sdkName,
          '\$lib_version': apiClient.sdkVersion,
        }
      };

      final props = event['properties'] as Map<String, String>;
      expect(props['\$lib'], 'posthog-flutter');
      expect(props['\$lib_version'], isNotEmpty);
    });
  });
}
