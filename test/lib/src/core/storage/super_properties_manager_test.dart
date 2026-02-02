import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/core/storage/super_properties_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SuperPropertiesManager', () {
    late SharedPreferences prefs;
    late SuperPropertiesManager manager;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      manager = SuperPropertiesManager(prefs: prefs);
    });

    test('should register super property', () async {
      await manager.register('test_prop', 'test_value');

      expect(manager.get('test_prop'), 'test_value');
    });

    test('should register multiple super properties', () async {
      await manager.register('prop1', 'value1');
      await manager.register('prop2', 123);
      await manager.register('prop3', true);

      final all = manager.getAll();
      expect(all['prop1'], 'value1');
      expect(all['prop2'], 123);
      expect(all['prop3'], true);
    });

    test('should register property only once', () async {
      await manager.registerOnce('once_prop', 'first_value');
      expect(manager.get('once_prop'), 'first_value');

      await manager.registerOnce('once_prop', 'second_value');
      expect(manager.get('once_prop'), 'first_value');
    });

    test('should registerOnce for new properties', () async {
      await manager.registerOnce('new_prop', 'value');

      expect(manager.get('new_prop'), 'value');
    });

    test('should unregister property', () async {
      await manager.register('temp_prop', 'temp_value');
      expect(manager.has('temp_prop'), true);

      await manager.unregister('temp_prop');
      expect(manager.has('temp_prop'), false);
    });

    test('should persist properties to disk', () async {
      await manager.register('persistent_prop', 'persistent_value');

      // Create new manager instance
      final newManager = SuperPropertiesManager(prefs: prefs);
      expect(newManager.get('persistent_prop'), 'persistent_value');
    });

    test('should clear all properties', () async {
      await manager.register('prop1', 'value1');
      await manager.register('prop2', 'value2');

      await manager.clear();

      expect(manager.getAll().isEmpty, true);
    });

    test('should merge registerOnce and register properties', () async {
      await manager.registerOnce('once_prop', 'once_value');
      await manager.register('normal_prop', 'normal_value');

      final all = manager.getAll();
      expect(all['once_prop'], 'once_value');
      expect(all['normal_prop'], 'normal_value');
    });

    test('should handle complex property values', () async {
      final mapValue = {'key': 'value'};
      final listValue = [1, 2, 3];

      await manager.register('map_prop', mapValue);
      await manager.register('list_prop', listValue);

      expect(manager.get('map_prop'), mapValue);
      expect(manager.get('list_prop'), listValue);
    });

    test('should return empty map when no properties', () {
      final all = manager.getAll();
      expect(all, isEmpty);
    });

    test('should overwrite existing register properties', () async {
      await manager.register('prop', 'value1');
      await manager.register('prop', 'value2');

      expect(manager.get('prop'), 'value2');
    });

    test('should not overwrite registerOnce properties', () async {
      await manager.registerOnce('prop', 'value1');
      await manager.register('prop', 'value2');

      // register should overwrite registerOnce
      expect(manager.get('prop'), 'value2');
    });

    test('should handle persistence of both property types', () async {
      await manager.registerOnce('once', 'once_value');
      await manager.register('normal', 'normal_value');

      final newManager = SuperPropertiesManager(prefs: prefs);
      final all = newManager.getAll();

      expect(all['once'], 'once_value');
      expect(all['normal'], 'normal_value');
    });

    test('should check if key exists', () async {
      expect(manager.has('non_existent'), false);

      await manager.register('existent', 'value');
      expect(manager.has('existent'), true);
    });

    test('should clear persistence', () async {
      await manager.register('prop', 'value');
      await manager.clear();

      final newManager = SuperPropertiesManager(prefs: prefs);
      expect(newManager.getAll(), isEmpty);
    });
  });
}
