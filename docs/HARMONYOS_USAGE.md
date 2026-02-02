# PostHog 鸿蒙平台使用说明

## 重要：必须在 HarmonyOS 平台上手动注册实现

由于 Flutter 插件系统的限制，需要在鸿蒙平台上手动设置实现：

### 使用方法

在你的应用的 `main()` 函数中，**在调用 `Posthog().setup()` 之前**，添加以下代码：

```dart
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/posthog_flutter_harmonyos.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ⚠️ 关键：在鸿蒙平台上必须先设置实现
  PosthogFlutterPlatformInterface.instance = PosthogFlutterHarmonyOS();

  // 然后再初始化 PostHog
  await Posthog().setup(
    PostHogConfig('YOUR_API_KEY', debug: true),
  );

  runApp(MyApp());
}
```

### 完整示例

```dart
import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/posthog_flutter_harmonyos.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1️⃣ 先设置鸿蒙平台实现
  PosthogFlutterPlatformInterface.instance = PosthogFlutterHarmonyOS();

  // 2️⃣ 然后初始化 PostHog
  await Posthog().setup(
    PostHogConfig(
      'phc_YOUR_API_KEY',
      debug: true,
      host: 'https://app.posthog.com',
    ),
  );

  // 3️⃣ 发送测试事件
  await Posthog().capture(eventName: 'harmonyos_test');
  await Posthog().flush();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('PostHog 鸿蒙测试')),
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              await Posthog().capture(eventName: 'button_click');
              await Posthog().flush();
              print('事件已发送');
            },
            child: const Text('发送事件'),
          ),
        ),
      ),
    );
  }
}
```

### 为什么需要手动注册？

Flutter 插件系统在不同平台上的默认实现：
- iOS/Android/macOS → `PosthogFlutterIO` (通过原生 MethodChannel)
- Web → `PosthogFlutterWeb` (通过 JavaScript)
- **HarmonyOS** → `PosthogFlutterHarmonyOS` (通过 HTTP API + 部分原生功能)

由于鸿蒙是新增的平台，需要手动指定使用 `PosthogFlutterHarmonyOS` 实现。

### 验证是否正确注册

运行应用后，查看日志，应该看到：

```
[PostHog] Setup started
[PostHog] Event queue initialized
[PostHog] API client initialized
```

如果看到 `MissingPluginException`，说明没有正确注册实现。

### 如果你在多平台项目上开发

可以使用条件导入来自动处理：

```dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

import 'package:posthog_flutter/posthog_flutter.dart';

// 条件导入平台实现
void setupPosthogPlatform() {
  // 检测是否是鸿蒙平台
  final isHarmonyOS = Platform.operatingSystem == 'ohos' ||
                      Platform.operatingSystem == 'harmonyos';

  if (isHarmonyOS) {
    // 鸿蒙平台
    import 'package:posthog_flutter/posthog_flutter_harmonyos.dart';
    PosthogFlutterPlatformInterface.instance = PosthogFlutterHarmonyOS();
  }
  // iOS/Android/macOS 会自动使用默认实现
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 设置平台实现
  setupPosthogPlatform();

  // 初始化 PostHog
  await Posthog().setup(
    PostHogConfig('YOUR_API_KEY', debug: true),
  );

  runApp(MyApp());
}
```

### 常见问题

**Q: 为什么会出现 `MissingPluginException`？**

A: 没有在调用 `setup()` 之前设置 `PosthogFlutterPlatformInterface.instance = PosthogFlutterHarmonyOS();`

**Q: 需要在每个平台上都设置吗？**

A: 不需要。只在鸿蒙平台上设置，iOS/Android/macOS 会自动使用默认实现。

**Q: 如何检测当前是鸿蒙平台？**

A:
```dart
import 'dart:io';

final isHarmonyOS = Platform.operatingSystem == 'ohos' ||
                    Platform.operatingSystem == 'harmonyos';
```
