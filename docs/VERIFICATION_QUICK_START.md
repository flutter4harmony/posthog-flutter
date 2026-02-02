# PostHog 鸿蒙平台 - 快速验证指南

## 方法一：使用现有的 example 应用

最简单的验证方式是使用项目自带的 example 应用：

```bash
cd example
flutter lib/main.dart  # 查看示例代码
```

### 修改 example/lib/main.dart

添加你的 API Key 和启用调试：

```dart
await Posthog().setup(
  PostHogConfig(
    'YOUR_API_KEY_HERE',  // 替换这里
    debug: true,           // 启用调试日志
    host: 'https://app.posthog.com',
  ),
);
```

### 在鸿蒙设备上运行

```bash
cd example
flutter run -d harmonyos  # 在鸿蒙设备上运行
```

查看日志输出，应该看到类似：

```
[PostHog] Setup started
[PostHog] Event queue initialized
[PostHog] API client initialized
```

---

## 方法二：PostHog Dashboard 验证

这是最可靠的验证方法，因为你可以直接看到数据是否到达。

### 步骤：

1. **初始化 SDK**
   ```dart
   await Posthog().setup(
     PostHogConfig('YOUR_API_KEY', debug: true),
   );
   ```

2. **发送测试事件**
   ```dart
   await Posthog().capture(eventName: 'harmonyos_test_event');
   await Posthog().flush();  // 立即发送
   ```

3. **在 Dashboard 中验证**
   - 打开 https://app.posthog.com/
   - 进入你的项目
   - 点击左侧 **"Events"**
   - 搜索 `harmonyos_test_event`
   - 如果看到事件，说明 SDK 工作正常！

---

## 方法三：使用验证脚本

```bash
# 运行验证脚本（会检查代码质量和测试）
./scripts/verify_harmonyos.sh YOUR_API_KEY
```

脚本会检查：
- ✅ 代码分析是否通过
- ✅ 单元测试是否通过
- ✅ 关键文件是否存在
- ✅ 生成验证报告

---

## 关键验证点

### 1. 事件是否发送到 PostHog？

**在代码中：**
```dart
await Posthog().capture(eventName: 'test');
await Posthog().flush();  // 立即发送，不要等
```

**在 Dashboard 中：**
- 访问 https://app.posthog.com/project/YOUR_PROJECT_ID/live
- 应该能看到 `test` 事件出现在实时流中

### 2. 用户识别是否工作？

**在代码中：**
```dart
await Posthog().identify(
  userId: 'test_user_123',
  userProperties: {'name': '测试用户'},
);
```

**在 Dashboard 中：**
- 点击 "Persons"
- 搜索 `test_user_123`
- 应该能看到该用户及其属性

### 3. 功能标志是否工作？

**在 Dashboard 中创建功能标志：**
1. 点击 "Feature Flags"
2. 点击 "New feature flag"
3. Key: `test-flag`
4. 保存

**在代码中测试：**
```dart
await Posthog().reloadFeatureFlags();
final isEnabled = await Posthog().isFeatureEnabled('test-flag');
print('功能标志状态: $isEnabled');
```

### 4. 异常是否被捕获？

**在代码中：**
```dart
try {
  throw Exception('测试异常');
} catch (e, stackTrace) {
  await Posthog().captureException(
    error: e,
    stackTrace: stackTrace,
  );
}
```

**在 Dashboard 中：**
- 搜索事件 `$exception`
- 应该能看到异常详情

---

## 最简单的验证（5分钟）

### 步骤 1：获取 API Key
```
1. 访问 https://app.posthog.com/
2. 注册/登录
3. 创建新项目
4. 复制 API Key (格式: phc_xxx)
```

### 步骤 2：创建最小测试应用

```dart
import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Posthog().setup(
    PostHogConfig('YOUR_API_KEY', debug: true),
  );

  // 发送测试事件
  await Posthog().capture(eventName: 'harmonyos_test');
  await Posthog().flush();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('PostHog 鸿蒙测试')),
      ),
    );
  }
}
```

### 步骤 3：在鸿蒙设备上运行

```bash
flutter run -d harmonyos
```

### 步骤 4：验证

在 PostHog Dashboard 的 "Events" 页面搜索 `harmonyos_test`。

如果看到这个事件，恭喜！PostHog 鸿蒙 SDK 工作正常！🎉

---

## 常见问题

### Q: 没有鸿蒙设备怎么办？

A: 你可以使用：
1. HarmonyOS 模拟器（DevEco Studio）
2. 先在 iOS/Android 上验证 Dart 层代码
3. 单元测试已经覆盖大部分逻辑

### Q: 如何查看调试日志？

A: 在 DevEco Studio 的 HiLog 窗口中搜索 "PostHog"。

### Q: 事件为什么没有出现在 Dashboard？

A: 检查：
1. API Key 是否正确？
2. 网络连接是否正常？
3. 是否调用了 `flush()`？
4. Dashboard 中是否选择了正确的项目？

### Q: Session Replay 为什么不工作？

A: 这是已知的限制。鸿蒙截图 API 尚未完全公开，框架已完成但需要等待官方 API。

---

## 需要帮助？

- 📖 完整验证指南: `docs/HARMONYOS_VERIFICATION_GUIDE.md`
- 📝 API 文档: `docs/HARMONYOS_SETUP_GUIDE.md`
- 💬 GitHub Issues: https://github.com/PostHog/posthog-flutter/issues
