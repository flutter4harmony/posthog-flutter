# PostHog 鸿蒙平台故障排查

## 问题：MissingPluginException

错误信息：
```
MissingPluginException: No implementation found for method setup on channel posthog_flutter
```

## 原因

这个错误表示 Flutter Dart 层无法找到鸿蒙原生层（ArkTS）的插件实现。

## 解决步骤

### 1. 确认使用鸿蒙版本的 Flutter

```bash
flutter --version
```

应该看到类似输出：
```
Flutter 3.32.4-ohos-0.0.1 • channel [user-branch]
```

### 2. 检查插件配置

确认 `pubspec.yaml` 中有 harmonyos 配置：

```yaml
flutter:
  plugin:
    platforms:
      harmonyos:
        pluginClass: PosthogFlutterPlugin
        fileName: posthog_flutter_harmonyos.dart
```

### 3. 运行 `flutter pub get`

```bash
flutter pub get
```

### 4. 在鸿蒙设备/模拟器上运行

**重要**：不能只运行 `flutter run`，需要：

```bash
# 列出可用设备
flutter devices

# 应该看到类似输出：
# harmonyos • HMN-AL00 • harmonyos • HarmonyOS

# 在鸿蒙设备上运行
flutter run -d harmonyos
```

### 5. 检查 DevEco Studio 项目

确保：
1. DevEco Studio 中已打开项目
2. 项目依赖已正确安装
3. 构建成功（无错误）

### 6. 检查原生日志

在 DevEco Studio 的 HiLog 中搜索：
- `PosthogFlutterPlugin`
- `Method channel initialized`

应该看到：
```
PosthogFlutterPlugin attached to engine
Method channel initialized
```

### 7. 简化测试

创建一个最简单的测试应用：

```dart
import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 直接使用默认实现
  await Posthog().setup(
    PostHogConfig('YOUR_API_KEY', debug: true),
  );

  runApp(const MyApp());
}
```

## 如果问题仍然存在

### 选项 A：使用纯 Dart 实现（不依赖原生）

某些功能可能不需要原生层，可以暂时只使用 Dart 层功能。

### 选项 B：检查 Flutter HarmonyOS 版本

确保使用的是支持插件的鸿蒙 Flutter 版本：

```bash
flutter --version
flutter upgrade
```

### 选项 C：查看完整错误日志

```bash
flutter run -d harmonyos -v 2>&1 | grep -i "plugin\|posthog"
```

## 常见问题

**Q: 为什么 iOS/Android 能工作，鸿蒙不行？**

A: 鸿蒙的插件系统还在发展中，可能与标准 Flutter 插件有些差异。

**Q: 需要在 DevEco Studio 中做什么？**

A: 确保项目已打开并成功构建。DevEco Studio 会处理鸿蒙特定的构建配置。

**Q: 如何确认原生插件已加载？**

A: 在应用启动时查看日志，应该看到：
```
PosthogFlutterPlugin attached to engine
Method channel initialized
```

## 下一步

如果以上步骤都无法解决问题，请提供：
1. Flutter 版本：`flutter --version`
2. 设备列表：`flutter devices`
3. 完整错误日志
4. DevEco Studio 构建日志

在 GitHub Issues 中提交：
https://github.com/PostHog/posthog-flutter/issues
