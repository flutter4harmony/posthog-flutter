import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:posthog_flutter/src/posthog_config.dart';
import 'package:posthog_flutter/src/posthog_event.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/util/platform_io_real.dart';
import 'package:posthog_flutter/src/core/http/posthog_api_client.dart';
import 'package:posthog_flutter/src/core/storage/event_queue.dart';
import 'package:posthog_flutter/src/core/storage/super_properties_manager.dart';
import 'package:posthog_flutter/src/core/managers/session_manager.dart';
import 'package:posthog_flutter/src/error_tracking/harmonyos_exception_processor.dart';
import 'package:posthog_flutter/src/surveys/survey_service.dart';
import 'package:posthog_flutter/src/surveys/models/posthog_display_survey.dart' as models;
import 'package:posthog_flutter/src/surveys/models/survey_callbacks.dart';
import 'package:posthog_flutter/src/util/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PostHog Flutter Platform Implementation for HarmonyOS
///
/// This implementation uses HTTP API directly instead of a native SDK,
/// since PostHog doesn't have an official HarmonyOS SDK.
class PosthogFlutterHarmonyOS extends PosthogFlutterPlatformInterface {
  static const MethodChannel _methodChannel = MethodChannel('posthog_flutter');

  PosthogApiClient? _apiClient;
  EventQueue? _eventQueue;
  SuperPropertiesManager? _superPropertiesManager;
  PostHogSessionManager? _sessionManager;
  SharedPreferences? _prefs;
  Timer? _flushTimer;

  String? _distinctId;
  Map<String, Object> _featureFlags = {};
  Map<String, Object> _featureFlagPayloads = {};

  bool _optOut = false;
  bool _debug = false;
  PostHogConfig? _config;

  OnFeatureFlagsCallback? _onFeatureFlagsCallback;
  List<BeforeSendCallback> _beforeSendCallbacks = [];

  // App lifecycle tracking
  bool _isInForeground = true;
  _LifecycleObserver? _lifecycleObserver;

  PosthogFlutterHarmonyOS() {
    _methodChannel.setMethodCallHandler(_handleMethodCall);
  }

  @override
  Future<void> setup(PostHogConfig config) async {
    if (!isSupportedPlatform()) return;

    _config = config;
    _optOut = config.optOut;
    _debug = config.debug;
    _beforeSendCallbacks = config.beforeSend;

    // Initialize shared preferences
    _prefs = await SharedPreferences.getInstance();

    // Initialize event queue
    _eventQueue = EventQueue(
      prefs: _prefs!,
      maxQueueSize: config.maxQueueSize,
    );

    // Initialize super properties manager
    _superPropertiesManager = SuperPropertiesManager(prefs: _prefs!);

    // Initialize session manager
    _sessionManager = PostHogSessionManager(
      sessionTimeout: const Duration(minutes: 30),
      onSessionStart: (sessionId) {
        // Session started
        _onFeatureFlagsCallback?.call();
      },
      onSessionEnd: (sessionId) {
        // Session ended
      },
    );
    _sessionManager!.getOrCreateSessionId();

    // Initialize API client
    _apiClient = PosthogApiClient(
      apiKey: config.apiKey,
      host: config.host,
    );

    // Generate or retrieve distinct ID
    _distinctId = _prefs!.getString('posthog_distinct_id') ?? _generateDistinctId();
    await _prefs!.setString('posthog_distinct_id', _distinctId!);

    // Load cached feature flags
    _loadCachedFeatureFlags();

    // Start auto flush
    _startAutoFlush(config.flushInterval);

    // Load feature flags if preload is enabled
    if (config.preloadFeatureFlags && !_optOut) {
      unawaited(reloadFeatureFlags());
    }

    // Store feature flags callback
    _onFeatureFlagsCallback = config.onFeatureFlags;

    // Setup app lifecycle observer if needed
    if (config.captureApplicationLifecycleEvents) {
      _setupLifecycleObserver();
    }

    // Setup error handlers if enabled
    _setupErrorHandlers(config.errorTrackingConfig);

    // Setup session replay if enabled
    if (config.sessionReplay) {
      _setupSessionReplay(config.sessionReplayConfig);
    }
  }

  /// Setup error handlers for automatic error capture
  void _setupErrorHandlers(PostHogErrorTrackingConfig errorConfig) {
    // Flutter error handler
    if (errorConfig.captureFlutterErrors) {
      FlutterError.onError = (details) {
        // Capture Flutter framework errors
        final exception = PostHogException(
          details.exception,
          mechanism: 'FlutterError',
          handled: details.silent,
        );
        _captureExceptionSync(exception, details.stack, silent: details.silent);
      };
    }

    // PlatformDispatcher error handler
    if (errorConfig.capturePlatformDispatcherErrors) {
      PlatformDispatcher.instance.onError = (error, stackTrace) {
        final exception = PostHogException(
          error,
          mechanism: 'PlatformDispatcher',
          handled: false,
        );
        _captureExceptionSync(exception, stackTrace);
        return true;
      };
    }

    // Isolate error handler
    if (errorConfig.captureIsolateErrors) {
      final errorPort = RawReceivePort((error) {
        _handleIsolateError(error);
      });
      Isolate.current.addErrorListener(errorPort.sendPort);
    }
  }

  /// Handle isolate errors
  void _handleIsolateError(Object error) {
    final exception = PostHogException(
      error,
      mechanism: 'Isolate',
      handled: false,
    );
    _captureExceptionSync(exception, null);
  }

  /// Synchronous exception capture (for error handlers)
  void _captureExceptionSync(
    Object error,
    StackTrace? stackTrace, {
    bool silent = false,
  }) {
    if (_optOut) return;

    // Convert to PostHogException if needed
    PostHogException exception;
    if (error is PostHogException) {
      exception = error;
    } else {
      exception = PostHogException(
        error,
        handled: !silent,
      );
    }

    // Process and queue the exception event
    final exceptionProps = HarmonyOSExceptionProcessor.processException(
      error: exception.source,
      stackTrace: stackTrace,
      properties: null,
      inAppIncludes: _config?.errorTrackingConfig.inAppIncludes,
      inAppExcludes: _config?.errorTrackingConfig.inAppExcludes,
      inAppByDefault: _config?.errorTrackingConfig.inAppByDefault ?? true,
    );

    // Queue the event asynchronously (don't await)
    _queueExceptionEvent(exceptionProps.cast<String, Object>());
  }

  /// Queue exception event asynchronously
  void _queueExceptionEvent(Map<String, Object> properties) {
    // Update session activity
    _sessionManager?.recordActivity();

    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final event = {
      'event': '\$exception',
      'properties': {
        'distinct_id': _distinctId,
        'token': _apiClient!.apiKey,
        'time': timestamp,
        '\$lib': _apiClient!.sdkName,
        '\$lib_version': _apiClient!.sdkVersion,
        if (_sessionManager?.sessionId != null) '\$session_id': _sessionManager?.sessionId,
        ...properties,
        ..._getDevicePropertiesSync(),
        ...?_superPropertiesManager?.getAll(),
      },
    };

    // Add to queue asynchronously without awaiting
    _eventQueue?.enqueue(event);
  }

  /// Get device properties synchronously (fallback)
  Map<String, Object> _getDevicePropertiesSync() {
    // Return cached device info or empty map
    return {
      '\$os': 'HarmonyOS',
      '\$lib': 'posthog-flutter',
    };
  }

  /// Setup session replay
  void _setupSessionReplay(PostHogSessionReplayConfig replayConfig) {
    // Pass configuration to SessionReplayManager via MethodChannel
    // The actual screenshot capture will be handled by native layer
    _methodChannel.invokeMethod('setupSessionReplay', {
      'maskAllTexts': replayConfig.maskAllTexts,
      'maskAllImages': replayConfig.maskAllImages,
      'throttleDelayMs': replayConfig.throttleDelay.inMilliseconds,
    }).catchError((e) {
      _logDebug('Failed to setup session replay: $e');
    });
  }

  /// Applies the beforeSend callbacks to an event in order.
  /// Returns the possibly modified event, or null if any callback drops it.
  Future<PostHogEvent?> _runBeforeSend(
    String eventName,
    Map<String, Object>? properties, {
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) async {
    var event = PostHogEvent(
      event: eventName,
      properties: properties,
      userProperties: userProperties,
      userPropertiesSetOnce: userPropertiesSetOnce,
    );

    if (_beforeSendCallbacks.isEmpty) return event;

    for (final callback in _beforeSendCallbacks) {
      try {
        final callbackResult = callback(event);
        if (callbackResult is Future<PostHogEvent?>) {
          final result = await callbackResult;
          if (result == null) return null;
          event = result;
        } else if (callbackResult == null) {
          return null;
        } else {
          event = callbackResult;
        }
      } catch (e) {
        _logDebug('beforeSend callback threw exception: $e');
        // Continue with next callback on error
      }
    }
    return event;
  }

  /// Setup app lifecycle observer
  void _setupLifecycleObserver() {
    _lifecycleObserver = _LifecycleObserver(
      onStateChanged: (state) async {

        switch (state) {
          case AppLifecycleState.resumed:
            if (!_isInForeground) {
              _isInForeground = true;
              await capture(
                eventName: 'Application Opened',
                properties: {
                  'from_background': true,
                },
              );
            }
            break;
          case AppLifecycleState.paused:
          case AppLifecycleState.inactive:
          case AppLifecycleState.detached:
            if (_isInForeground) {
              _isInForeground = false;
              await capture(
                eventName: 'Application Backgrounded',
                properties: {
                  'state': state.toString(),
                },
              );
            }
            break;
          case AppLifecycleState.hidden:
            // App is hidden
            break;
        }
      },
    );
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);
  }

  @override
  Future<void> capture({
    required String eventName,
    Map<String, Object>? properties,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) async {
    if (!isSupportedPlatform() || _optOut) return;

    // Apply beforeSend callback
    final processedEvent = await _runBeforeSend(
      eventName,
      properties,
      userProperties: userProperties,
      userPropertiesSetOnce: userPropertiesSetOnce,
    );

    if (processedEvent == null) {
      _logDebug('[PostHog] Event dropped by beforeSend: $eventName');
      return;
    }

    // Update session activity
    _sessionManager?.recordActivity();

    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final event = {
      'event': processedEvent.event,
      'properties': {
        'distinct_id': _distinctId,
        'token': _apiClient!.apiKey,
        'time': timestamp,
        '\$lib': _apiClient!.sdkName,
        '\$lib_version': _apiClient!.sdkVersion,
        if (_sessionManager?.sessionId != null) '\$session_id': _sessionManager?.sessionId,
        ...?processedEvent.properties,
        ...await _getDeviceProperties(),
        ...?_superPropertiesManager?.getAll(),
      },
      if (processedEvent.userProperties != null)
        '\$set': processedEvent.userProperties,
      if (processedEvent.userPropertiesSetOnce != null)
        '\$set_once': processedEvent.userPropertiesSetOnce,
    };

    final shouldFlush = await _eventQueue!.enqueue(event);

    // Check if should flush based on queue size
    if (_config != null && _eventQueue!.size >= _config!.flushAt) {
      await flush();
    } else if (shouldFlush) {
      await flush();
    }
  }

  @override
  Future<void> screen({
    required String screenName,
    Map<String, Object>? properties,
  }) async {
    // Apply beforeSend callback - screen events are captured as $screen
    final processedEvent = await _runBeforeSend(
      '\$screen',
      <String, Object>{
        '\$screen_name': screenName,
        ...?properties,
      },
    );

    if (processedEvent == null) {
      _logDebug('[PostHog] Screen event dropped by beforeSend: $screenName');
      return;
    }

    await capture(
      eventName: processedEvent.event,
      properties: processedEvent.properties?.cast<String, Object>(),
    );
  }

  @override
  Future<void> identify({
    required String userId,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) async {
    if (!isSupportedPlatform() || _optOut) return;

    _distinctId = userId;
    await _prefs!.setString('posthog_distinct_id', userId);

    // Check personProfiles config
    final shouldSendPersonProfiles = _shouldSendPersonProfiles();

    // Send $set event to update user properties if needed
    if (shouldSendPersonProfiles && (userProperties != null || userPropertiesSetOnce != null)) {
      await capture(
        eventName: '\$identify',
        properties: null,
        userProperties: userProperties,
        userPropertiesSetOnce: userPropertiesSetOnce,
      );
    } else {
      // Still need to call capture to track the identify event
      await capture(
        eventName: '\$identify',
        properties: null,
      );
    }
  }

  /// Determine if person profiles should be sent based on config
  bool _shouldSendPersonProfiles() {
    final personProfiles = _config?.personProfiles ?? PostHogPersonProfiles.identifiedOnly;

    switch (personProfiles) {
      case PostHogPersonProfiles.never:
        return false;
      case PostHogPersonProfiles.always:
        return true;
      case PostHogPersonProfiles.identifiedOnly:
        // Only send if userId is set (not the generated anonymous one)
        // For simplicity, we check if userId differs from initial anonymous ID
        return _distinctId != null && !_distinctId!.startsWith('timestamp-');
    }
  }

  @override
  Future<void> alias({
    required String alias,
  }) async {
    if (!isSupportedPlatform() || _optOut) return;

    await capture(
      eventName: '\$create_alias',
      properties: {
        'alias': alias,
        'distinct_id': _distinctId ?? '',
      },
    );
  }

  @override
  Future<void> group({
    required String groupType,
    required String groupKey,
    Map<String, Object>? groupProperties,
  }) async {
    if (!isSupportedPlatform() || _optOut) return;

    await capture(
      eventName: '\$groupidentify',
      properties: {
        '\$group_type': groupType,
        '\$group_key': groupKey,
        if (groupProperties != null) '\$group_set': groupProperties,
      },
    );
  }

  @override
  Future<String> getDistinctId() async {
    return _distinctId ?? '';
  }

  @override
  Future<void> reset() async {
    if (!isSupportedPlatform()) return;

    _distinctId = _generateDistinctId();
    await _prefs!.setString('posthog_distinct_id', _distinctId!);
    await _eventQueue!.clear();
    _featureFlags.clear();
    await _superPropertiesManager?.clear();
    _sessionManager?.reset();
  }

  @override
  Future<void> flush() async {
    if (!isSupportedPlatform() || _optOut) return;

    final allEvents = _eventQueue!.drain();
    if (allEvents.isEmpty) return;

    // Split into batches if maxBatchSize is set
    final batchSize = _config?.maxBatchSize ?? 50;
    final batches = _splitIntoBatches(allEvents, batchSize);

    for (final batch in batches) {
      if (batch.isEmpty) break;

      try {
        await _apiClient!.batch(batch);
      } catch (e) {
        // Failed to send, re-add to queue
        for (final event in batch) {
          await _eventQueue!.enqueue(event);
        }
        _logDebug('Failed to send batch: $e');
      }
    }
  }

  /// Split events into batches
  List<List<Map<String, dynamic>>> _splitIntoBatches(
    List<Map<String, dynamic>> events,
    int batchSize,
  ) {
    final batches = <List<Map<String, dynamic>>>[];
    for (int i = 0; i < events.length; i += batchSize) {
      final end = (i + batchSize < events.length) ? i + batchSize : events.length;
      batches.add(events.sublist(i, end));
    }
    return batches;
  }

  @override
  Future<void> enable() async {
    if (!isSupportedPlatform()) return;
    _optOut = false;
  }

  @override
  Future<void> disable() async {
    if (!isSupportedPlatform()) return;
    _optOut = true;
  }

  @override
  Future<bool> isOptOut() async {
    return _optOut;
  }

  @override
  Future<void> debug(bool enabled) async {
    _debug = enabled;
    _logDebug('Debug mode: ${enabled ? "enabled" : "disabled"}');
  }

  @override
  Future<void> register(String key, Object value) async {
    if (!isSupportedPlatform()) return;
    await _superPropertiesManager?.register(key, value);
  }

  @override
  Future<void> unregister(String key) async {
    if (!isSupportedPlatform()) return;
    await _superPropertiesManager?.unregister(key);
  }

  @override
  Future<Object?> getFeatureFlag({required String key}) async {
    await reloadFeatureFlags();
    return _featureFlags[key];
  }

  @override
  Future<bool> isFeatureEnabled(String key) async {
    await reloadFeatureFlags();

    final value = _featureFlags[key];

    // Send feature flag called event if enabled
    if (_config?.sendFeatureFlagEvents == true) {
      unawaited(capture(
        eventName: '\$feature_flag_called',
        properties: {
          '\$feature_flag': key,
          '\$feature_flag_response': value ?? false,
        },
      ));
    }

    return value is bool ? value : false;
  }

  @override
  Future<Object?> getFeatureFlagPayload({required String key}) async {
    await reloadFeatureFlags();
    return _featureFlagPayloads[key];
  }

  @override
  Future<void> reloadFeatureFlags() async {
    if (!isSupportedPlatform() || _optOut) return;

    try {
      final response = await _apiClient!.decide(
        distinctId: _distinctId!,
      );

      final flags = response['featureFlags'] as Map<String, dynamic>?;
      final payloads = response['featureFlagPayloads'] as Map<String, dynamic>?;

      if (flags != null) {
        _featureFlags = flags.cast<String, Object>();
        await _prefs!.setString('posthog_feature_flags', jsonEncode(flags));
      }

      if (payloads != null) {
        _featureFlagPayloads = payloads.cast<String, Object>();
      }

      // Notify callback if set
      _onFeatureFlagsCallback?.call();
    } catch (e) {
      // On error, try to load from cache
      _loadCachedFeatureFlags();
    }
  }

  @override
  Future<void> captureException({
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object>? properties,
  }) async {
    if (!isSupportedPlatform() || _optOut) return;

    final exceptionProps = HarmonyOSExceptionProcessor.processException(
      error: error,
      stackTrace: stackTrace,
      properties: properties,
      inAppIncludes: _config?.errorTrackingConfig.inAppIncludes,
      inAppExcludes: _config?.errorTrackingConfig.inAppExcludes,
      inAppByDefault: _config?.errorTrackingConfig.inAppByDefault ?? true,
    );

    await capture(
      eventName: '\$exception',
      properties: exceptionProps.cast<String, Object>(),
    );
  }

  @override
  Future<void> close() async {
    if (!isSupportedPlatform()) return;

    await flush();
    _flushTimer?.cancel();
    _apiClient?.dispose();
    _eventQueue?.dispose();
    _sessionManager?.dispose();
    if (_lifecycleObserver != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
    }
  }

  @override
  Future<String?> getSessionId() async {
    return _sessionManager?.getOrCreateSessionId();
  }

  @override
  Future<void> showSurvey(Map<String, dynamic> survey) async {
    // Check if surveys are enabled
    if (_config?.surveys != true) {
      _logDebug('Surveys are disabled');
      return;
    }

    if (!isSupportedPlatform()) {
      printIfDebug('Cannot show survey: Platform is not supported');
      return;
    }

    // Convert the survey map to PostHogDisplaySurvey
    final displaySurvey = models.PostHogDisplaySurvey.fromDict(survey);

    // Use SurveyService to display the survey
    // This works the same way on all platforms since it's Flutter UI
    await SurveyService().showSurvey(
      displaySurvey,
      (survey) async {
        // onShown callback
        try {
          await _methodChannel.invokeMethod('surveyAction', {'type': 'shown'});
        } on PlatformException catch (exception) {
          printIfDebug('Exception on surveyAction(shown): $exception');
        }
      },
      (survey, index, response) async {
        // onResponse callback
        int nextIndex = index;
        bool isSurveyCompleted = false;

        try {
          final result = await _methodChannel.invokeMethod('surveyAction', {
            'type': 'response',
            'index': index,
            'response': response,
          }) as Map;
          nextIndex = (result['nextIndex'] as num).toInt();
          isSurveyCompleted = result['isSurveyCompleted'] as bool;
        } on PlatformException catch (exception) {
          printIfDebug('Exception on surveyAction(response): $exception');
        }

        final nextQuestion = PostHogSurveyNextQuestion(
          questionIndex: nextIndex,
          isSurveyCompleted: isSurveyCompleted,
        );
        return nextQuestion;
      },
      (survey) async {
        // onClosed callback
        try {
          await _methodChannel.invokeMethod('surveyAction', {'type': 'closed'});
        } on PlatformException catch (exception) {
          printIfDebug('Exception on surveyAction(closed): $exception');
        }
      },
    );
  }

  @override
  Future<void> openUrl(String url) async {
    if (!isSupportedPlatform()) return;

    try {
      await _methodChannel.invokeMethod('openUrl', url);
    } catch (e) {
      // Ignore errors
    }
  }

  // Private methods

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'showSurvey':
        final survey = Map<String, dynamic>.from(call.arguments);
        return showSurvey(survey);
      case 'hideSurveys':
        await cleanupSurveys();
        return null;
      default:
        break;
    }
  }

  /// Cleans up any active surveys
  Future<void> cleanupSurveys() async {
    if (!isSupportedPlatform()) {
      printIfDebug('Cannot cleanup surveys: Platform is not supported');
      return;
    }
    SurveyService().hideSurvey();
  }

  void _startAutoFlush(Duration interval) {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(interval, (_) {
      flush();
    });
  }

  String _generateDistinctId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = _randomString(8);
    return '$timestamp-$random';
  }

  String _randomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return List.generate(length, (index) => chars[random.nextInt(chars.length)])
        .join();
  }

  Future<Map<String, Object>> _getDeviceProperties() async {
    try {
      final deviceInfo = await _methodChannel.invokeMethod('getDeviceInfo');
      if (deviceInfo != null) {
        return Map<String, Object>.from(deviceInfo);
      }
    } catch (e) {
      // Ignore errors
    }
    return {};
  }

  void _loadCachedFeatureFlags() {
    try {
      final cached = _prefs!.getString('posthog_feature_flags');
      if (cached != null) {
        _featureFlags = jsonDecode(cached);
      }
    } catch (e) {
      // Ignore parsing errors
    }
  }

  void _logDebug(String message) {
    if (_debug) {
      printIfDebug('[PostHog] $message');
    }
  }
}

/// Lifecycle observer for tracking app state changes
class _LifecycleObserver extends WidgetsBindingObserver {
  final void Function(AppLifecycleState) onStateChanged;

  _LifecycleObserver({required this.onStateChanged});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onStateChanged(state);
  }
}
