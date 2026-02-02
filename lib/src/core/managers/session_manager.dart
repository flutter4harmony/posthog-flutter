import 'dart:async';

/// Session Manager for PostHog
/// Manages session lifecycle and session ID generation
class PostHogSessionManager {
  static const Duration _defaultSessionTimeout = Duration(minutes: 30);

  String? _sessionId;
  DateTime? _lastActivityTime;
  Timer? _sessionTimer;
  Duration _sessionTimeout;

  final void Function(String sessionId) onSessionStart;
  final void Function(String sessionId)? onSessionEnd;

  PostHogSessionManager({
    Duration? sessionTimeout,
    required this.onSessionStart,
    this.onSessionEnd,
  }) : _sessionTimeout = sessionTimeout ?? _defaultSessionTimeout;

  /// Get current session ID
  String? get sessionId => _sessionId;

  /// Get current session ID or create a new one
  String getOrCreateSessionId() {
    if (_sessionId == null || _isSessionExpired()) {
      _startNewSession();
    }
    _updateActivity();
    return _sessionId!;
  }

  /// Record user activity
  void recordActivity() {
    _updateActivity();
  }

  /// End current session
  void endSession() {
    if (_sessionId != null) {
      final oldSessionId = _sessionId;
      _sessionId = null;
      _lastActivityTime = null;
      _stopTimer();
      onSessionEnd?.call(oldSessionId!);
    }
  }

  /// Reset session manager
  void reset() {
    endSession();
    _startNewSession();
  }

  /// Set session timeout
  void setSessionTimeout(Duration timeout) {
    _sessionTimeout = timeout;
    _restartTimer();
  }

  /// Start a new session
  void _startNewSession() {
    _sessionId = _generateSessionId();
    _lastActivityTime = DateTime.now();
    _restartTimer();
    onSessionStart(_sessionId!);
  }

  /// Update last activity time
  void _updateActivity() {
    _lastActivityTime = DateTime.now();
    _restartTimer();
  }

  /// Check if session has expired
  bool _isSessionExpired() {
    if (_lastActivityTime == null) return true;
    return DateTime.now().difference(_lastActivityTime!) > _sessionTimeout;
  }

  /// Restart session timer
  void _restartTimer() {
    _stopTimer();
    _sessionTimer = Timer(_sessionTimeout, () {
      if (_isSessionExpired()) {
        endSession();
      }
    });
  }

  /// Stop session timer
  void _stopTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
  }

  /// Generate a new session ID
  String _generateSessionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = _randomString(8);
    return '$timestamp-$random';
  }

  /// Generate random string
  String _randomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = DateTime.now().microsecondsSinceEpoch % chars.length;
    return List.generate(length, (index) => chars[(random + index) % chars.length])
        .join();
  }

  /// Dispose resources
  void dispose() {
    _stopTimer();
  }
}
