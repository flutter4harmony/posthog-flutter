# PostHog Flutter SDK - 鸿蒙平台接入指南

## 概述

PostHog Flutter SDK 现已支持鸿蒙（HarmonyOS）平台。本文档将帮助您在鸿蒙应用中集成 PostHog SDK。

## 前置要求

- Flutter SDK 3.0+
- HarmonyOS SDK API 9+
- DevEco Studio 4.0+
- PostHog 账号和项目 API Key

## 安装

### 1. 添加依赖

在 `pubspec.yaml` 中添加 `posthog_flutter`：

```yaml
dependencies:
  posthog_flutter: [最新版本]
```

### 2. 安装依赖

```bash
flutter pub get
```

## 配置

### 1. 初始化 SDK

在应用启动时初始化 PostHog：

```dart
import 'package:posthog_flutter/posthog_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Posthog().setup(
    PostHogConfig(
      apiKey: 'your-api-key',
      host: 'https://app.posthog.com', // 或您的自托管实例
    ),
  );

  runApp(MyApp());
}
```

### 2. 配置选项

```dart
await Posthog().setup(
  PostHogConfig(
    apiKey: 'your-api-key',
    host: 'https://app.posthog.com',

    // 可选配置
    debug: true,                    // 启用调试日志
    flushInterval: Duration(seconds: 10),  // 自动发送间隔
    maxQueueSize: 1000,             // 队列最大大小
    captureApplicationLifecycleEvents: true, // 捕获应用生命周期事件
    captureScreenViews: true,       // 自动追踪屏幕浏览
    preloadFeatureFlags: true,      // 预加载功能标志
  ),
);
```

## 基础使用

### 事件追踪

```dart
// 捕获事件
await Posthog().capture(
  eventName: 'button_clicked',
  properties: {
    'button_name': 'signup',
    'screen': 'home',
  },
);
```

### 用户识别

```dart
// 识别用户
await Posthog().identify(
  userId: 'user-123',
  userProperties: {
    'email': 'user@example.com',
    'name': 'John Doe',
  },
);
```

### 屏幕追踪

```dart
// 手动追踪屏幕浏览
await Posthog().screen(
  screenName: 'Dashboard',
  properties: {
    'tab': 'analytics',
  },
);
```

### 用户别名

```dart
// 为用户创建别名
await Posthog().alias(alias: 'anonymous-id');
```

### 组事件

```dart
// 追踪组事件
await Posthog().group(
  groupType: 'company',
  groupKey: 'acme-corp',
  groupProperties: {
    'name': 'Acme Corporation',
    'industry': 'Technology',
  },
);
```

## 高级功能

### 超级属性

超级属性会自动包含在所有事件中：

```dart
// 注册超级属性（可被覆盖）
await Posthog().register('user_type', 'premium');

// 注册一次（不会被覆盖）
await Posthog().registerOnce('first_visit_date', DateTime.now().toString());

// 删除超级属性
await Posthog().unregister('user_type');
```

### 功能标志

```dart
// 检查功能是否启用
bool isEnabled = await Posthog().isFeatureEnabled('new-dashboard');
if (isEnabled) {
  // 显示新功能
}

// 获取功能标志值
var value = await Posthog().getFeatureFlag(key: 'experiment-variant');

// 获取功能标志载荷
var payload = await Posthog().getFeatureFlagPayload(key: 'experiment-config');

// 重新加载功能标志
await Posthog().reloadFeatureFlags();
```

### 会话管理

```dart
// 获取当前会话 ID
String? sessionId = await Posthog().getSessionId();
print('Current session: $sessionId');
```

### 异常追踪

```dart
try {
  // 可能抛出异常的代码
} catch (e, stackTrace) {
  await Posthog().captureException(
    error: e,
    stackTrace: stackTrace,
    properties: {
      'context': 'payment_processing',
    },
  );
}
```

## 配置选项详解

### PostHogConfig 参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| apiKey | String | 必填 | PostHog 项目 API Key |
| host | String | 'https://app.posthog.com' | PostHog 服务器地址 |
| debug | bool | false | 是否启用调试日志 |
| flushInterval | Duration | 10秒 | 自动发送事件的时间间隔 |
| maxQueueSize | int | 1000 | 队列中最大事件数量 |
| captureApplicationLifecycleEvents | bool | false | 是否自动捕获应用生命周期事件 |
| captureScreenViews | bool | false | 是否自动追踪屏幕浏览 |
| preloadFeatureFlags | bool | false | 是否在初始化时预加载功能标志 |
| sendFeatureFlagEvents | bool | true | 是否发送功能标志使用事件 |
| onFeatureFlags | VoidCallback? | null | 功能标志加载完成回调 |

### 错误追踪配置

```dart
await Posthog().setup(
  PostHogConfig(
    apiKey: 'your-api-key',
    errorTrackingConfig: PostHogErrorTrackingConfig(
      inAppIncludes: ['com.myapp'],         // 包含的包前缀
      inAppExcludes: ['com.myapp.third'],   // 排除的包前缀
      inAppByDefault: true,                 // 默认是否标记为应用内
    ),
  ),
);
```

## 网络权限

SDK 会自动在 `ohos/entry/src/main/module.json5` 中配置所需权限：

```json5
{
  "module": {
    "requestPermissions": [
      {
        "name": "ohos.permission.INTERNET",
        "reason": "$string:internet_permission_reason",
        "usedScene": {
          "abilities": ["EntryAbility"],
          "when": "inuse"
        }
      },
      {
        "name": "ohos.permission.GET_NETWORK_INFO",
        "reason": "$string:internet_permission_reason",
        "usedScene": {
          "abilities": ["EntryAbility"],
          "when": "inuse"
        }
      }
    ]
  }
}
```

## 最佳实践

### 1. 在应用启动时初始化

确保在 `main()` 函数中尽早初始化 SDK，以便捕获所有启动事件。

### 2. 使用用户属性

使用 `userProperties` 参数而不是事件属性来存储用户相关信息：

```dart
await Posthog().identify(
  userId: 'user-123',
  userProperties: {
    'email': 'user@example.com',  // 用户属性
  },
);
```

### 3. 批量设置超级属性

使用 `register` 一次性设置多个超级属性：

```dart
await Posthog().register('user_properties', {
  'plan': 'premium',
  'signup_date': '2024-01-01',
});
```

### 4. 清理用户数据

当用户登出时调用 `reset()`：

```dart
await Posthog().reset();
```

### 5. 启用调试模式

在开发环境启用调试以查看日志：

```dart
await Posthog().setup(
  PostHogConfig(
    apiKey: 'your-api-key',
    debug: kDebugMode,  // 仅在调试模式启用
  ),
);
```

## 故障排查

### 事件未发送

1. 检查网络连接
2. 验证 API Key 是否正确
3. 启用调试模式查看日志
4. 确认服务器地址配置正确

### 功能标志未加载

1. 确保 `preloadFeatureFlags` 设置为 `true`
2. 检查用户是否已通过 `identify()` 识别
3. 验证 PostHog 项目中是否配置了功能标志

### 会话回放问题

由于鸿蒙截图 API 限制，Session Replay 功能当前仅提供框架支持。完整功能需要等待鸿蒙官方 API 完善。

## 限制和注意事项

### Session Replay

当前 Session Replay 处于框架完成状态（80%）。由于鸿蒙系统截图 API 尚未完全公开，完整的截图捕获功能需要等待官方 API 完善。

### 已知限制

1. **Session Replay**: 框架已完成，待鸿蒙 API 完善
2. **推送通知**: 需要额外的原生配置
3. **深度链接**: 需要在鸿蒙项目中配置

## 示例项目

完整的示例项目请参考：
- [example](../example) - 基础使用示例

## 支持

如有问题，请：
1. 查看 [PostHog 文档](https://posthog.com/docs)
2. 在 [GitHub Issues](https://github.com/PostHog/posthog-flutter/issues) 提问
3. 加入 [PostHog Community](https://posthog.com/slack)

## 更新日志

查看 [CHANGELOG](../CHANGELOG.md) 了解最新版本更新。

## 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](../LICENSE) 文件
