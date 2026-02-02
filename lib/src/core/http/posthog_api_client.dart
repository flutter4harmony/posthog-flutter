import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// PostHog API Exception
class PosthogApiException implements Exception {
  final String message;
  final int? statusCode;

  PosthogApiException(this.message, {this.statusCode});

  @override
  String toString() => 'PosthogApiException: $message (status: $statusCode)';
}

/// PostHog HTTP API Client
/// Handles direct communication with PostHog servers via HTTP API
class PosthogApiClient {
  final String apiKey;
  final String host;
  final http.Client _client;

  PosthogApiClient({
    required this.apiKey,
    required this.host,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Batch send events to PostHog /batch/ endpoint
  ///
  /// Sends multiple events in a single batch request.
  /// See: https://posthog.com/docs/api/capture
  Future<void> batch(List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return;

    final url = Uri.parse('$host/batch/');
    final headers = {
      'Content-Type': 'application/json',
    };

    final body = jsonEncode({
      'api_key': apiKey,
      'batch': events,
    });

    try {
      final response = await _client.post(url, headers: headers, body: body).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw PosthogApiException('Request timeout');
        },
      );

      if (response.statusCode != 200) {
        throw PosthogApiException(
          'Failed to send batch: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } on PosthogApiException {
      rethrow;
    } catch (e) {
      throw PosthogApiException('Network error: $e');
    }
  }

  /// Fetch feature flags and configuration from /decide endpoint
  ///
  /// Returns the decide response containing feature flags, group config, etc.
  /// See: https://posthog.com/docs/api/feature-flags
  Future<Map<String, dynamic>> decide({
    required String distinctId,
    Map<String, dynamic>? personProperties,
  }) async {
    final url = Uri.parse('$host/decide/?v=3');
    final headers = {
      'Content-Type': 'application/json',
    };

    final payload = {
      'api_key': apiKey,
      'distinct_id': distinctId,
      if (personProperties != null) 'personProperties': personProperties,
    };

    final body = jsonEncode(payload);

    try {
      final response = await _client.post(url, headers: headers, body: body).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw PosthogApiException('Request timeout');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data;
      }

      throw PosthogApiException(
        'Failed to fetch feature flags: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    } on PosthogApiException {
      rethrow;
    } catch (e) {
      throw PosthogApiException('Network error: $e');
    }
  }

  /// Get the current SDK version
  String get sdkVersion => '5.13.0-harmonyos.1';

  /// Get the SDK name
  String get sdkName => 'posthog-flutter';

  /// Dispose the HTTP client
  void dispose() {
    _client.close();
  }
}
