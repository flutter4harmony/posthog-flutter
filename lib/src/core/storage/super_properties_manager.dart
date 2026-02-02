import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Super Properties Manager
/// Manages persistent storage of super properties (global event properties)
class SuperPropertiesManager {
  final SharedPreferences _prefs;
  final String _propertiesKey;
  final String _oncePropertiesKey;

  Map<String, Object> _superProperties = {};
  Map<String, Object> _superPropertiesOnce = {};

  SuperPropertiesManager({
    required SharedPreferences prefs,
    String propertiesKey = 'posthog_super_properties',
    String oncePropertiesKey = 'posthog_super_properties_once',
  })  : _prefs = prefs,
        _propertiesKey = propertiesKey,
        _oncePropertiesKey = oncePropertiesKey {
    _loadFromDisk();
  }

  /// Register a super property
  /// These properties are included with all events
  Future<void> register(String key, Object value) async {
    _superProperties[key] = value;
    await _saveToDisk();
  }

  /// Register multiple super properties
  Future<void> registerAll(Map<String, Object> properties) async {
    _superProperties.addAll(properties);
    await _saveToDisk();
  }

  /// Register a property to be sent only once
  Future<void> registerOnce(String key, Object value) async {
    if (!_superPropertiesOnce.containsKey(key)) {
      _superPropertiesOnce[key] = value;
      await _saveToDisk();
    }
  }

  /// Register multiple properties to be sent only once
  Future<void> registerOnceAll(Map<String, Object> properties) async {
    var hasNewProperties = false;

    for (final entry in properties.entries) {
      if (!_superPropertiesOnce.containsKey(entry.key)) {
        _superPropertiesOnce[entry.key] = entry.value;
        hasNewProperties = true;
      }
    }

    if (hasNewProperties) {
      await _saveToDisk();
    }
  }

  /// Unregister (remove) a super property
  Future<void> unregister(String key) async {
    _superProperties.remove(key);
    _superPropertiesOnce.remove(key);
    await _saveToDisk();
  }

  /// Clear all super properties
  Future<void> clear() async {
    _superProperties.clear();
    _superPropertiesOnce.clear();
    await _prefs.remove(_propertiesKey);
    await _prefs.remove(_oncePropertiesKey);
  }

  /// Get all super properties (including once properties)
  Map<String, Object> getAll() {
    return {
      ..._superPropertiesOnce,
      ..._superProperties,
    };
  }

  /// Get a specific super property
  Object? get(String key) {
    return _superProperties[key] ?? _superPropertiesOnce[key];
  }

  /// Check if a property exists
  bool has(String key) {
    return _superProperties.containsKey(key) || _superPropertiesOnce.containsKey(key);
  }

  /// Load properties from disk
  void _loadFromDisk() {
    try {
      final propsJson = _prefs.getString(_propertiesKey);
      if (propsJson != null) {
        final Map<String, dynamic> decoded = jsonDecode(propsJson);
        _superProperties = decoded.cast<String, Object>();
      }

      final oncePropsJson = _prefs.getString(_oncePropertiesKey);
      if (oncePropsJson != null) {
        final Map<String, dynamic> decoded = jsonDecode(oncePropsJson);
        _superPropertiesOnce = decoded.cast<String, Object>();
      }
    } catch (e) {
      // Ignore parsing errors
    }
  }

  /// Save properties to disk
  Future<void> _saveToDisk() async {
    try {
      final propsJson = jsonEncode(_superProperties);
      await _prefs.setString(_propertiesKey, propsJson);

      final oncePropsJson = jsonEncode(_superPropertiesOnce);
      await _prefs.setString(_oncePropertiesKey, oncePropsJson);
    } catch (e) {
      // Ignore save errors
    }
  }
}
