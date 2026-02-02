# PostHog Flutter SDK 鸿蒙平台适配分析

## 目录

- [1. 项目概述](#1-项目概述)
- [2. iOS/Android 平台实现分析](#2-iosandroid-平台实现分析)
- [3. 鸿蒙平台适配可行性评估](#3-鸿蒙平台适配可行性评估)
- [4. 鸿蒙平台适配实施方案](#4-鸿蒙平台适配实施方案)
- [5. 技术挑战与解决方案](#5-技术挑战与解决方案)
- [6. 开发路线图](#6-开发路线图)
- [7. 总结](#7-总结)

---

## 1. 项目概述

### 1.1 SDK 架构

PostHog Flutter SDK 采用**平台插件架构**，通过 Flutter 的 **MethodChannel** 机制实现跨平台调用：

```
┌─────────────────────────────────────────┐
│         Flutter Layer (Dart)            │
│  ┌───────────────────────────────────┐  │
│  │  Posthog (主 API 类)               │  │
│  │  - 统一的业务接口                    │  │
│  │  - 配置管理                          │  │
│  └───────────────────────────────────┘  │
│                 ↓                        │
│  ┌───────────────────────────────────┐  │
│  │  PosthogFlutterPlatformInterface   │  │
│  │  - 平台抽象层                       │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
                    │
        ┌───────────┼───────────┐
        │           │           │
        ↓           ↓           ↓
┌───────────┐ ┌─────────┐ ┌─────────┐
│   iOS     │ │ Android │ │   Web   │
│  Swift    │ │ Kotlin  │ │   JS    │
└───────────┘ └─────────┘ └─────────┘
```

### 1.2 核心依赖

#### iOS 端
- **PostHog iOS SDK**: `>= 3.32.0, < 4.0.0`
- **最低版本**: iOS 13.0+
- **语言**: Swift 5.3

#### Android 端
- **PostHog Android SDK**: `[3.25.0, 4.0.0)`
- **最低版本**: API 21 (Android 5.0)
- **语言**: Kotlin 2.0

#### Flutter 端
- **SDK**: `>= 3.4.0 < 4.0.0`
- **Flutter**: `>= 3.22.0`
- **核心依赖**: `plugin_platform_interface`, `stack_trace`, `web`

---

## 2. iOS/Android 平台实现分析

### 2.1 iOS 平台实现细节

#### 2.1.1 核心文件
- **主插件类**: `ios/Classes/PosthogFlutterPlugin.swift`
- **依赖**: PostHog iOS SDK (CocoaPods)

#### 2.1.2 主要功能模块

| 功能 | 实现方式 | 关键代码位置 |
|------|----------|--------------|
| **事件追踪** | 调用 `PostHogSDK.shared.capture()` | `PosthogFlutterPlugin.swift:565-575` |
| **用户识别** | 调用 `PostHogSDK.shared.identify()` | `PosthogFlutterPlugin.swift:534-553` |
| **功能标志** | 调用 `PostHogSDK.shared.getFeatureFlag()` | `PosthogFlutterPlugin.swift:492-532` |
| **Session Replay** | 自定义快照发送逻辑 | `PosthogFlutterPlugin.swift:354-457` |
| **调查问卷** | 实现 `PostHogSurveysDelegate` | `PosthogFlutterPlugin.swift:243-351` |
| **错误追踪** | 捕获并上报异常 | `PosthogFlutterPlugin.swift:704-721` |

#### 2.1.3 Session Replay 实现

iOS 端的 Session Replay 是**原生实现**，包含两个核心方法：

1. **sendMetaEvent** - 发送屏幕元数据
```swift
// 发送屏幕尺寸、名称等元信息
PostHogSDK.shared.capture("$snapshot",
    properties: [
        "$snapshot_source": "mobile",
        "$snapshot_data": snapshotsData
    ]
)
```

2. **sendFullSnapshot** - 发送完整截图
```swift
// 将 Flutter 传来的图片字节流转为 Base64
// 包装成 snapshot 事件发送
```

#### 2.1.4 调查问卷实现

iOS 通过**委托模式**实现问卷功能：

```swift
extension PosthogFlutterPlugin: PostHogSurveysDelegate {
    public func renderSurvey(
        _ survey: PostHogDisplaySurvey,
        onSurveyShown: @escaping OnPostHogSurveyShown,
        onSurveyResponse: @escaping OnPostHogSurveyResponse,
        onSurveyClosed: @escaping OnPostHogSurveyClosed
    ) {
        // 将问卷数据转为字典发送给 Flutter
        invokeFlutterMethod("showSurvey", arguments: survey.toDict())
    }
}
```

### 2.2 Android 平台实现细节

#### 2.2.1 核心文件
- **主插件类**: `android/src/main/kotlin/com/posthog/flutter/PosthogFlutterPlugin.kt`
- **辅助类**:
  - `SnapshotSender.kt` - 快照发送器
  - `PostHogFlutterSurveysDelegate.kt` - 调查委托
- **依赖**: PostHog Android SDK (Gradle)

#### 2.2.2 主要功能模块

| 功能 | 实现方式 | 关键代码位置 |
|------|----------|--------------|
| **事件追踪** | 调用 `PostHog.capture()` | `PosthogFlutterPlugin.kt:385-404` |
| **用户识别** | 调用 `PostHog.identify()` | `PosthogFlutterPlugin.kt:370-383` |
| **功能标志** | 调用 `PostHog.getFeatureFlag()` | `PosthogFlutterPlugin.kt:344-368` |
| **Session Replay** | 使用 `SnapshotSender` 辅助类 | `SnapshotSender.kt:12-63` |
| **调查问卷** | `PostHogFlutterSurveysDelegate` | `PostHogFlutterSurveysDelegate.kt` |
| **错误追踪** | 捕获并上报异常 | `PosthogFlutterPlugin.kt:564-590` |

#### 2.2.3 Session Replay 实现

Android 使用独立的 `SnapshotSender` 类：

```kotlin
class SnapshotSender {
    fun sendFullSnapshot(imageBytes: ByteArray, id: Int, x: Int, y: Int) {
        val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
        val base64String = bitmap.base64()

        val wireframe = RRWireframe(
            id = id, x = x, y = y,
            width = bitmap.width, height = bitmap.height,
            type = "screenshot", base64 = base64String
        )

        val snapshotEvent = RRFullSnapshotEvent(listOf(wireframe), ...)
        listOf(snapshotEvent).capture()
    }
}
```

#### 2.2.4 调查问卷实现

Android 使用独立的委托类处理问卷逻辑：

```kotlin
class PostHogFlutterSurveysDelegate(
    private val channel: MethodChannel
) : PostHogSurveysDelegate {
    fun handleSurveyAction(
        action: String,
        payload: Map<String, Any>?,
        result: MethodChannel.Result
    ) {
        // 处理问卷交互
    }
}
```

### 2.3 平台通信机制

#### 2.3.1 MethodChannel 定义

**iOS/Swift**:
```swift
let methodChannel = FlutterMethodChannel(
    name: "posthog_flutter",
    binaryMessenger: registrar.messenger()
)
```

**Android/Kotlin**:
```kotlin
channel = MethodChannel(
    flutterPluginBinding.binaryMessenger,
    "posthog_flutter"
)
```

#### 2.3.2 方法映射表

| Flutter 方法 | iOS 方法 | Android 方法 |
|-------------|----------|--------------|
| `setup` | ✅ | ✅ |
| `capture` | ✅ | ✅ |
| `identify` | ✅ | ✅ |
| `screen` | ✅ | ✅ |
| `getFeatureFlag` | ✅ | ✅ |
| `sendFullSnapshot` | ✅ | ✅ |
| `sendMetaEvent` | ✅ | ✅ |
| `surveyAction` | ✅ (iOS 15+) | ✅ |
| `captureException` | ✅ | ✅ |
| `openUrl` | ✅ | ✅ |

---

## 3. 鸿蒙平台适配可行性评估

### 3.1 可行性分析

| 评估维度 | 结论 | 说明 |
|---------|------|------|
| **技术可行性** | ✅ 高度可行 | 鸿蒙支持 Flutter，已有 MethodChannel 支持 |
| **SDK 可用性** | ⚠️ 需评估 | PostHog 官方暂无鸿蒙原生 SDK |
| **工作量** | 🟡 中等偏高 | 需要实现鸿蒙原生 SDK 或纯 Dart 实现 |
| **维护成本** | 🟡 中等 | 需要持续跟进鸿蒙平台更新 |

### 3.2 关键技术支持

#### 3.2.1 鸿蒙 Flutter 支持
- ✅ Flutter 3.22+ 支持鸿蒙平台
- ✅ HarmonyOS NEXT 提供完整的 Flutter 插件开发能力
- ✅ MethodChannel 机制完全兼容

#### 3.2.2 鸿蒙原生能力
- ✅ 网络请求 (http 模块)
- ✅ 本地存储 (preferences 模块)
- ✅ 系统信息 (@kit.BasicServicesKit)
- ✅ 应用生命周期 (@kit.AbilityKit)

### 3.3 缺失依赖评估

**关键问题**: PostHog 官方**没有提供鸿蒙原生 SDK**。

这意味着我们需要：
1. **方案 A**: 从零实现 PostHog 鸿蒙原生 SDK
2. **方案 B**: 在 Flutter 层实现纯 Dart 版本（推荐）
3. **方案 C**: 混合方案 - 部分 Dart + 部分原生能力

---

## 4. 鸿蒙平台适配实施方案

### 4.1 推荐方案：纯 Dart 实现（HarmonyOS Platform）

#### 4.1.1 方案概述

不依赖原生 PostHog SDK，而是在 Flutter 层实现所有核心功能，仅在必要时调用鸿蒙原生能力。

#### 4.1.2 架构设计

```
┌─────────────────────────────────────────┐
│         Flutter Layer (Dart)            │
│  ┌───────────────────────────────────┐  │
│  │  Posthog (统一 API，无需修改)      │  │
│  └───────────────────────────────────┘  │
│                 ↓                        │
│  ┌───────────────────────────────────┐  │
│  │  PosthogFlutterHarmonyOS          │  │
│  │  - HTTP 请求发送                   │  │
│  │  - 本地存储 (super_properties)     │  │
│  │  - 队列管理                        │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
                    │
        ┌───────────┴───────────┐
        │   HarmonyOS 原生层     │
        │  - 系统信息获取        │
        │  - 应用生命周期        │
        │  - 网络状态监听        │
└───────┴───────────────────────┘
```

#### 4.1.3 需要实现的核心模块

##### 1. HTTP 通信模块
```dart
class HarmonyOSHttpClient {
  Future<void> capture(PostHogEvent event) async {
    // 使用鸿蒙的 http 模块或 Flutter 的 http 包
    final response = await http.post(
      Uri.parse('$host/capture/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(event.toJson()),
    );
  }
}
```

##### 2. 本地存储模块
```dart
class HarmonyOSS storage {
  Future<void> setSuperProperties(Map<String, dynamic> properties) async {
    // 使用 Flutter 的 shared_preferences 或鸿蒙 preferences
    await prefs.setString('super_properties', jsonEncode(properties));
  }
}
```

##### 3. 队列管理模块
```dart
class HarmonyOSEventQueue {
  final Queue<PostHogEvent> _queue = Queue();
  final int _maxQueueSize = 1000;

  Future<void> enqueue(PostHogEvent event) async {
    if (_queue.length >= _maxQueueSize) {
      await flush();
    }
    _queue.add(event);
    await _persist();
  }
}
```

##### 4. 功能标志模块
```dart
class HarmonyOSFeatureFlags {
  Future<Map<String, dynamic>> fetchFeatureFlags() async {
    final response = await http.get(
      Uri.parse('$host/decide/?v=3'),
    );
    return jsonDecode(response.body)['featureFlags'];
  }
}
```

#### 4.1.4 需要调用的鸿蒙原生能力

| 功能 | 鸿蒙 API | 用途 |
|------|----------|------|
| **设备信息** | `@kit.BasicServicesKit` | 获取设备型号、OS 版本 |
| **应用信息** | `@kit.AbilityKit` | 获取应用版本、包名 |
| **网络状态** | `@kit.ConnectivityKit` | 检测网络连接状态 |
| **生命周期** | `UIAbility` | 监听应用前后台切换 |

### 4.2 实现步骤

#### 步骤 1: 创建鸿蒙插件文件结构

```
posthog_flutter/
├── harmonyos/                           # 新增鸿蒙平台目录
│   ├── entry/
│   │   └── src/
│   │       └── main/
│   │           ├── ets/
│   │           │   └── PosthogFlutterPlugin.ets
│   │           ├── resources/
│   │           └── module.json5
│   └── oh-package.json5
├── lib/
│   └── src/
│       └── posthog_flutter_harmonyos.dart  # 新增鸿蒙平台实现
└── pubspec.yaml
```

#### 步骤 2: 实现鸿蒙插件类

```typescript
// PosthogFlutterPlugin.ets
import { http } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';

export default class PosthogFlutterPlugin {
  private static channel: MethodChannel | null = null;
  private static storage: preferences.Preferences | null = null;

  static onAttachedToEngine(engine: FlutterPluginBinding) {
    this.channel = new MethodChannel(
      engine.binaryMessenger,
      'posthog_flutter'
    );

    this.channel.setMethodCallHandler(this.handleMethodCall);
  }

  static async handleMethodCall(call: MethodCall, result: MethodResult) {
    switch (call.method) {
      case 'setup':
        await this.setup(call.arguments);
        result.success(null);
        break;
      case 'capture':
        await this.capture(call.arguments);
        result.success(null);
        break;
      // ... 其他方法
    }
  }

  private static async setup(config: Map<string, Object>) {
    // 初始化配置，获取设备信息
    const deviceId = await this.getDeviceId();
    // 保存配置
  }

  private static async capture(args: Map<string, Object>) {
    const event = {
      event: args['eventName'],
      properties: {
        ...args['properties'],
        device_id: this.deviceId,
        timestamp: Date.now(),
      },
    };

    // 发送到 PostHog 服务器
    await this.sendEvent(event);
  }
}
```

#### 步骤 3: 实现 Flutter 端平台接口

```dart
// lib/src/posthog_flutter_harmonyos.dart
class PosthogFlutterHarmonyOS extends PosthogFlutterPlatformInterface {
  static void registerWith() {
    PosthogFlutterPlatformInterface.instance = PosthogFlutterHarmonyOS();
  }

  @override
  Future<void> setup(PostHogConfig config) async {
    // 调用鸿蒙原生层或使用纯 Dart 实现
    await _channel.invokeMethod('setup', config.toMap());
  }

  @override
  Future<void> capture({
    required String eventName,
    Map<String, Object>? properties,
  }) async {
    await _channel.invokeMethod('capture', {
      'eventName': eventName,
      'properties': properties,
    });
  }

  // ... 其他方法实现
}
```

#### 步骤 4: 更新 pubspec.yaml

```yaml
flutter:
  plugin:
    platforms:
      android:
        package: com.posthog.flutter
        pluginClass: PosthogFlutterPlugin
      ios:
        pluginClass: PosthogFlutterPlugin
      harmonyos:                           # 新增鸿蒙平台
        pluginClass: PosthogFlutterPlugin
        fileName: posthog_flutter_harmonyos.dart
```

---

## 5. 技术挑战与解决方案

### 5.1 挑战 1: 缺少原生 SDK

**问题**: PostHog 没有官方鸿蒙 SDK

**解决方案**:
1. **短期**: 在 Flutter 层实现核心功能（HTTP、存储、队列）
2. **长期**: 联系 PostHog 团队，争取官方支持；或基于 PostHog API 规范实现开源鸿蒙 SDK

**实现要点**:
```dart
class PostHogHttpClient {
  final String host;
  final String apiKey;

  Future<void> sendEvent(PostHogEvent event) async {
    // 参考 PostHog HTTP API 规范
    // https://posthog.com/docs/api/post-only-endpoints
  }
}
```

### 5.2 挑战 2: Session Replay 实现

**问题**: 需要截图和录屏能力

**解决方案**:
1. 使用 Flutter 的 `RepaintBoundary` + `Screenshot` 包
2. 将截图编码为 Base64
3. 参考 Android/iOS 实现格式发送

```dart
class HarmonyOSSessionReplay {
  Future<void> captureSnapshot() async {
    // 1. 使用 RepaintBoundary 捕获
    final image = await _captureWidget();
    // 2. 转为 Base64
    final base64 = await _imageToBase64(image);
    // 3. 发送
    await _sendSnapshot(base64);
  }
}
```

### 5.3 挑战 3: 调查问卷 UI

**问题**: 需要实现问卷 UI 组件

**解决方案**:
1. **复用现有 Flutter 实现** - 问卷 UI 已经在 Flutter 层实现
2. 鸿蒙层只需要提供问卷数据
3. 使用 `showModalBottomSheet` 显示问卷

```dart
// 现有实现已支持，无需修改
class SurveyBottomSheet extends StatelessWidget {
  // 已有的 Flutter 实现
}
```

### 5.4 挑战 4: 错误追踪

**问题**: 需要捕获鸿蒙原生错误

**解决方案**:
1. Flutter 层错误: 使用现有的 `PostHogErrorTrackingAutoCaptureIntegration`
2. 鸿蒙原生错误: 实现原生错误监听器

```typescript
// 鸿蒙原生错误监听
import { errorManager } from '@kit.BasicServicesKit';

errorManager.on('error', (error) => {
  // 发送到 Flutter 层
  PosthogFlutterPlugin.channel.invokeMethod('captureException', {
    'message': error.message,
    'stackTrace': error.stack,
  });
});
```

### 5.5 挑战 5: 功能标志同步

**问题**: 需要与 PostHog 服务器同步功能标志

**解决方案**:
1. 实现 `/decide/` 端点调用
2. 本地缓存功能标志
3. 支持 WebSocket 实时更新（可选）

```dart
class HarmonyOSFeatureFlagProvider {
  Future<Map<String, dynamic>> loadFeatureFlags() async {
    final response = await http.get(
      Uri.parse('$host/decide/?v=3'),
      headers: {'Authorization': 'Bearer $apiKey'},
    );

    final data = jsonDecode(response.body);
    await _cacheFlags(data['featureFlags']);
    return data['featureFlags'];
  }
}
```

---

## 6. 开发路线图

### 6.1 第一阶段：核心功能 (MVP)

**目标**: 实现基本的事件追踪和用户识别

**任务清单**:
- [ ] 创建鸿蒙插件文件结构
- [ ] 实现 `setup` 方法（配置初始化）
- [ ] 实现 `capture` 方法（事件发送）
- [ ] 实现 `identify` 方法（用户识别）
- [ ] 实现 `screen` 方法（页面浏览）
- [ ] 实现 HTTP 客户端封装
- [ ] 实现本地存储（super_properties）
- [ ] 实现事件队列管理
- [ ] 编写单元测试

**预期工作量**: 2-3 周

### 6.2 第二阶段：高级功能

**目标**: 实现功能标志和错误追踪

**任务清单**:
- [ ] 实现 `getFeatureFlag` 方法
- [ ] 实现 `isFeatureEnabled` 方法
- [ ] 实现 `/decide/` 端点集成
- [ ] 实现 `captureException` 方法
- [ ] 实现栈帧解析
- [ ] 实现自动错误捕获
- [ ] 实现 `group` 方法（用户组）
- [ ] 实现 `alias` 方法（用户别名）

**预期工作量**: 2-3 周

### 6.3 第三阶段：Session Replay

**目标**: 实现会话回放功能

**任务清单**:
- [ ] 实现 `sendMetaEvent` 方法
- [ ] 实现 `sendFullSnapshot` 方法
- [ ] 集成 `screenshot` 包
- [ ] 实现截图压缩和 Base64 编码
- [ ] 实现快照队列管理
- [ ] 优化内存占用
- [ ] 实现 `isSessionReplayActive` 方法

**预期工作量**: 3-4 周

### 6.4 第四阶段：调查问卷

**目标**: 实现问卷功能

**任务清单**:
- [ ] 实现 `surveyAction` 方法
- [ ] 实现 `PostHogFlutterSurveysDelegate` (鸿蒙版)
- [ ] 集成现有 Flutter 问卷 UI
- [ ] 实现问卷显示逻辑
- [ ] 实现问卷响应回调
- [ ] 实现问卷关闭回调
- [ ] 测试各种问卷类型

**预期工作量**: 2-3 周

### 6.5 第五阶段：测试与优化

**目标**: 确保稳定性和性能

**任务清单**:
- [ ] 端到端测试
- [ ] 性能优化
- [ ] 内存泄漏检查
- [ ] 网络异常处理
- [ ] 离线队列测试
- [ ] 文档编写
- [ ] 示例应用更新

**预期工作量**: 2 周

**总计工作量**: 约 11-15 周

---

## 7. 总结

### 7.1 核心发现

1. **架构优势**: PostHog Flutter SDK 采用良好的平台抽象设计，便于扩展新平台
2. **实现简洁**: iOS 和 Android 实现相对简单，主要依赖原生 SDK
3. **主要难点**: 缺少 PostHog 官方鸿蒙 SDK 是最大挑战

### 7.2 推荐方案

**采用纯 Dart + 必要原生能力的混合方案**:

1. **核心逻辑** (HTTP、队列、存储) - 纯 Dart 实现
2. **系统能力** (设备信息、网络状态) - 调用鸿蒙原生 API
3. **高级功能** (Session Replay) - Flutter 层实现
4. **UI 组件** (调查问卷) - 复用现有 Flutter 实现

### 7.3 可行性结论

✅ **高度可行**

- ✅ 鸿蒙已支持 Flutter
- ✅ MethodChannel 机制完全兼容
- ✅ 大部分功能可在 Flutter 层实现
- ✅ 现有代码结构良好，便于扩展

⚠️ **注意事项**:

1. 需要从零实现 PostHog 核心功能（HTTP API 集成）
2. Session Replay 需要额外的截图处理
3. 需要充分测试网络异常和离线场景
4. 建议与 PostHog 团队沟通，争取官方支持

### 7.4 后续行动

1. **立即可做**:
   - 创建鸿蒙插件分支
   - 实现 MVP 版本（setup, capture, identify）
   - 编写技术验证 Demo

2. **短期目标** (1-2 个月):
   - 完成核心功能开发
   - 实现功能标志和错误追踪
   - 内部测试验证

3. **长期目标** (3-6 个月):
   - 完成 Session Replay 和调查问卷
   - 全面测试和优化
   - 发布正式版本
   - 贡献给 PostHog 社区

### 7.5 资源需求

- **开发人员**: 1-2 名（熟悉 Flutter + 鸿蒙）
- **测试人员**: 1 名
- **开发设备**: 鸿蒙设备/模拟器
- **测试账号**: PostHog 项目账号
- **时间投入**: 3-6 个月（根据功能范围）

---

## 附录

### A. 关键文件索引

| 文件 | 说明 |
|------|------|
| `ios/Classes/PosthogFlutterPlugin.swift` | iOS 插件主类 |
| `android/.../PosthogFlutterPlugin.kt` | Android 插件主类 |
| `android/.../SnapshotSender.kt` | Android 快照发送器 |
| `lib/src/posthog.dart` | Flutter 主 API |
| `lib/src/posthog_flutter_platform_interface.dart` | 平台抽象接口 |
| `lib/src/replay/` | Session Replay 模块 |
| `lib/src/surveys/` | 调查问卷模块 |
| `lib/src/error_tracking/` | 错误追踪模块 |

### B. PostHog API 参考文档

- **HTTP API**: https://posthog.com/docs/api/post-only-endpoints
- **JavaScript SDK**: https://github.com/PostHog/posthog-js
- **iOS SDK**: https://github.com/PostHog/posthog-ios
- **Android SDK**: https://github.com/PostHog/posthog-android

### C. 鸿蒙开发资源

- **Flutter HarmonyOS**: https://developer.harmonyos.com/cn/develop/flutter
- **鸿蒙 API 参考**: https://developer.harmonyos.com/cn/docs/documentation/doc-references-V3/
- **MethodChannel 指南**: https://api.flutter.dev/javadoc/io/flutter/plugin/common/MethodChannel.html

---

**文档版本**: 1.0
**创建日期**: 2025-01-30
**最后更新**: 2025-01-30
**作者**: AI 辅助分析
