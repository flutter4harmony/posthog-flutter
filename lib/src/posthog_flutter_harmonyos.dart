import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:posthog_flutter/src/posthog_config.dart';
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
  PostHogConfig? _config;

  OnFeatureFlagsCallback? _onFeatureFlagsCallback;

  PosthogFlutterHarmonyOS() {
    _methodChannel.setMethodCallHandler(_handleMethodCall);
  }

  @override
  Future<void> setup(PostHogConfig config) async {
    if (!isSupportedPlatform()) return;

    _config = config;
    _optOut = config.optOut;

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
        // Session started - could send $session_start event here
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
  }

  @override
  Future<void> capture({
    required String eventName,
    Map<String, Object>? properties,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) async {
    if (!isSupportedPlatform() || _optOut) return;

    // Update session activity
    _sessionManager?.recordActivity();

    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final event = {
      'event': eventName,
      'properties': {
        'distinct_id': _distinctId,
        'token': _apiClient!.apiKey,
        'time': timestamp,
        '\$lib': _apiClient!.sdkName,
        '\$lib_version': _apiClient!.sdkVersion,
        if (_sessionManager?.sessionId != null) '\$session_id': _sessionManager?.sessionId,
        ...?properties,
        ...await _getDeviceProperties(),
        ...?_superPropertiesManager?.getAll(),
      },
      if (userProperties != null) '\$set': userProperties,
      if (userPropertiesSetOnce != null) '\$set_once': userPropertiesSetOnce,
    };

    final shouldFlush = await _eventQueue!.enqueue(event);

    if (shouldFlush) {
      await flush();
    }
  }

  @override
  Future<void> screen({
    required String screenName,
    Map<String, Object>? properties,
  }) async {
    await capture(
      eventName: '\$screen',
      properties: {
        '\$screen_name': screenName,
        ...?properties,
      },
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

    // Send $set event to update user properties
    await capture(
      eventName: '\$identify',
      properties: null,
      userProperties: userProperties,
      userPropertiesSetOnce: userPropertiesSetOnce,
    );
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

    final events = _eventQueue!.drain();
    if (events.isEmpty) return;

    try {
      await _apiClient!.batch(events);
    } catch (e) {
      // Failed to send, re-add to queue
      for (final event in events) {
        await _eventQueue!.enqueue(event);
      }
      rethrow;
    }
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
    // Enable/disable debug logging
    // Currently not implemented for HarmonyOS
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
  }

  @override
  Future<String?> getSessionId() async {
    return _sessionManager?.getOrCreateSessionId();
  }

  @override
  Future<void> showSurvey(Map<String, dynamic> survey) async {
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
}
