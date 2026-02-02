import 'package:stack_trace/stack_trace.dart' as stack_trace;

/// PostHog Exception with additional context
class PostHogException implements Exception {
  final Object source;
  final String? mechanism;
  final bool handled;

  PostHogException(
    this.source, {
    this.mechanism,
    this.handled = true,
  });

  @override
  String toString() => 'PostHogException: $source (mechanism: $mechanism, handled: $handled)';
}

/// Enhanced exception processor for HarmonyOS
/// Parses and formats exceptions for PostHog error tracking
class HarmonyOSExceptionProcessor {
  /// Process an exception into PostHog event properties
  static Map<String, dynamic> processException({
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object>? properties,
    List<String>? inAppIncludes,
    List<String>? inAppExcludes,
    bool inAppByDefault = true,
  }) {
    // Handle PostHogException wrapper
    var handled = true;
    String? mechanismType;
    Object currentError = error;

    if (error is PostHogException) {
      handled = error.handled;
      mechanismType = error.mechanism;
      currentError = error.source;
    }

    // Get effective stack trace
    StackTrace effectiveStackTrace = stackTrace ?? StackTrace.empty;
    bool isGeneratedStackTrace = false;

    if (effectiveStackTrace == StackTrace.empty) {
      effectiveStackTrace = StackTrace.current;
      isGeneratedStackTrace = true;
    }

    // Parse stack trace
    final frames = _parseStackTrace(
      effectiveStackTrace,
      inAppIncludes: inAppIncludes,
      inAppExcludes: inAppExcludes,
      inAppByDefault: inAppByDefault,
    );

    // Build exception data
    final exceptionData = <String, dynamic>{
      '\$exception_level': handled ? 'error' : 'fatal',
      '\$exception_message': _sanitizeExceptionMessage(currentError.toString()),
      '\$exception_type': currentError.runtimeType.toString(),
      '\$exception_handled': handled,
      if (mechanismType != null) '\$exception_mechanism': mechanismType,
      '\$exception_stack_trace': frames,
      if (isGeneratedStackTrace) '\$exception_stack_trace_generated': true,
    };

    // Combine with additional properties
    final result = <String, dynamic>{
      '\$exception_list': [exceptionData],
      if (properties != null) ...properties,
    };

    return result;
  }

  /// Parse stack trace into PostHog format
  static List<Map<String, dynamic>> _parseStackTrace(
    StackTrace stackTrace, {
    List<String>? inAppIncludes,
    List<String>? inAppExcludes,
    bool inAppByDefault = true,
  }) {
    final frames = <Map<String, dynamic>>[];

    try {
      final trace = stack_trace.Trace.from(stackTrace);
      final framesList = trace.frames;

      for (final frame in framesList) {
        final isInApp = _isInAppFrame(
          frame,
          inAppIncludes: inAppIncludes,
          inAppExcludes: inAppExcludes,
          inAppByDefault: inAppByDefault,
        );

        final frameData = <String, dynamic>{
          'method': frame.member,
          'line': frame.line,
          'col': frame.column,
          'file': frame.uri.toString(),
          'in_app': isInApp,
        };

        frames.add(frameData);
      }
    } catch (e) {
      // If parsing fails, return simple stack trace
      final lines = stackTrace.toString().split('\n');
      for (final line in lines) {
        if (line.isNotEmpty) {
          frames.add({
            'method': line,
            'in_app': inAppByDefault,
          });
        }
      }
    }

    return frames;
  }

  /// Determine if a stack frame is in-app
  static bool _isInAppFrame(
    stack_trace.Frame frame, {
    List<String>? inAppIncludes,
    List<String>? inAppExcludes,
    bool inAppByDefault = true,
  }) {
    final uri = frame.uri.toString();

    // Check includes first (has priority)
    if (inAppIncludes != null && inAppIncludes.isNotEmpty) {
      for (final pattern in inAppIncludes) {
        if (uri.contains(pattern)) {
          return true;
        }
      }
      return false;
    }

    // Check excludes
    if (inAppExcludes != null && inAppExcludes.isNotEmpty) {
      for (final pattern in inAppExcludes) {
        if (uri.contains(pattern)) {
          return false;
        }
      }
    }

    // Default behavior
    if (inAppByDefault) {
      // Exclude dart/flutter core libraries
      if (uri.startsWith('dart:') || uri.startsWith('package:flutter/')) {
        return false;
      }
      return true;
    } else {
      return false;
    }
  }

  /// Sanitize exception message (remove sensitive data)
  static String _sanitizeExceptionMessage(String message) {
    // Remove common sensitive patterns
    final sanitized = message
        .replaceAll(RegExp(r'password\s*[:=]\s*\S+', caseSensitive: false), 'password=***')
        .replaceAll(RegExp(r'token\s*[:=]\s*\S+', caseSensitive: false), 'token=***')
        .replaceAll(RegExp(r'api[_-]?key\s*[:=]\s*\S+', caseSensitive: false), 'apiKey=***')
        .replaceAll(RegExp(r'secret\s*[:=]\s*\S+', caseSensitive: false), 'secret=***');

    return sanitized;
  }

  /// Create PostHogException from Flutter error details
  static PostHogException fromFlutterError(
    Object error, {
    String? mechanism,
    bool handled = false,
  }) {
    return PostHogException(
      error,
      mechanism: mechanism ?? 'FlutterError',
      handled: handled,
    );
  }

  /// Create PostHogException from platform dispatcher error
  static PostHogException fromPlatformError(
    Object error, {
    String? mechanism,
    bool handled = false,
  }) {
    return PostHogException(
      error,
      mechanism: mechanism ?? 'PlatformDispatcher',
      handled: handled,
    );
  }
}
