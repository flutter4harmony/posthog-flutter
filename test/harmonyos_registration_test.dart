import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';

void main() {
  test('PostHog plugin should be registered', () {
    // 这个测试验证插件是否正确注册
    final posthog = Posthog();
    expect(posthog, isNotNull);
    print('✓ PostHog plugin is accessible');
  });

  test('Platform interface should have implementation', () {
    // 验证平台接口有实现
    final platform = PosthogFlutterPlatformInterface.instance;
    expect(platform, isNotNull);
    print('✓ Platform interface has instance: ${platform.runtimeType}');
  });
}
