# PostHog Flutter SDK 深度分析与鸿蒙化方案

## 目录
1. [项目概述](#1-项目概述)
2. [架构设计](#2-架构设计)
3. [iOS 原生层分析](#3-ios-原生层分析)
4. [Android 原生层分析](#4-android-原生层分析)
5. [Dart 层分析](#5-dart-层分析)
6. [核心功能模块](#6-核心功能模块)
7. [鸿蒙化可行性分析](#7-鸿蒙化可行性分析)
8. [鸿蒙化实施方案](#8-鸿蒙化实施方案)
9. [工作量评估](#9-工作量评估)
10. [风险与挑战](#10-风险与挑战)

---

## 1. 项目概述

### 1.1 基本信息
- **项目名称**: posthog_flutter
- **版本**: 5.12.0
- **支持平台**: iOS、Android、macOS、Web
- **SDK 要求**: Dart >=3.4.0 <4.0.0, Flutter >=3.22.0
- **官方仓库**: https://github.com/posthog/posthog-flutter

### 1.2 项目结构
```
posthog-flutter/
├── android/                    # Android 原生代码 (Kotlin)
│   └── src/main/kotlin/com/posthog/flutter/
│       ├── PosthogFlutterPlugin.kt       # 主插件类
│       ├── SnapshotSender.kt             # 会话回放快照发送
│       ├── PostHogFlutterSurveysDelegate.kt  # 调查问卷代理
│       ├── PostHogDisplaySurveyExt.kt    # 调查问卷扩展
│       └── PostHogVersion.kt             # 版本信息
├── ios/                        # iOS 原生代码 (Swift)
│   └── Classes/
│       ├── PosthogFlutterPlugin.swift    # 主插件类
│       ├── PostHogDisplaySurvey+Dict.swift  # 调查问卷字典转换
│       └── PostHogFlutterVersion.swift   # 版本信息
├── lib/                        # Dart 层代码
│   ├── posthog_flutter.dart              # 主入口
│   ├── posthog_flutter_web.dart          # Web 实现
│   └── src/
│       ├── posthog.dart                  # 核心 API 类
│       ├── posthog_flutter_io.dart       # IO 平台实现
│       ├── posthog_flutter_platform_interface.dart  # 平台接口
│       ├── posthog_config.dart           # 配置类
│       ├── replay/                       # 会话回放模块
│       ├── surveys/                      # 调查问卷模块
│       ├── error_tracking/               # 错误追踪模块
│       └── util/                         # 工具类
└── example/                    # 示例项目
```

---

## 2. 架构设计

### 2.1 分层架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Dart 层 (Flutter)                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │   Posthog    │  │ SurveyService│  │ Error Tracking   │   │
│  │   (主 API)    │  │  (调查问卷)   │  │   (错误追踪)      │   │
│  └──────────────┘  └──────────────┘  └──────────────────┘   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │Session Replay│  │  Posthog     │  │ PosthogObserver  │   │
│  │  (会话回放)   │  │  Widget      │  │  (路由观察)       │   │
│  └──────────────┘  └──────────────┘  └──────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│              Platform Channel (MethodChannel)               │
├─────────────────────────────────────────────────────────────┤
│                  原生平台层 (iOS/Android)                     │
│  ┌─────────────────────────┐  ┌─────────────────────────┐   │
│  │    iOS (Swift)          │  │   Android (Kotlin)      │   │
│  │  PosthogFlutterPlugin   │  │  PosthogFlutterPlugin   │   │
│  │  PostHog SDK (Swift)    │  │  PostHog SDK (Android)  │   │
│  └─────────────────────────┘  └─────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 通信机制
- **MethodChannel**: `posthog_flutter`
- **通信方向**: 
  - Dart → Native: 调用原生方法 (capture, identify, screen 等)
  - Native → Dart: 回调通知 (feature flags 更新、调查问卷显示等)

---

## 3. iOS 原生层分析

### 3.1 文件位置
- 主插件: `ios/Classes/PosthogFlutterPlugin.swift`
- 调查问卷扩展: `ios/Classes/PostHogDisplaySurvey+Dict.swift`
- 版本信息: `ios/Classes/PostHogFlutterVersion.swift`

### 3.2 核心功能实现

#### 3.2.1 插件注册与初始化
```swift
public static func register(with registrar: FlutterPluginRegistrar) {
    let methodChannel = FlutterMethodChannel(name: "posthog_flutter", 
                                              binaryMessenger: registrar.messenger())
    let instance = PosthogFlutterPlugin()
    instance.channel = methodChannel
    PosthogFlutterPlugin.instance = instance
    initPlugin()  // 从 Info.plist 读取配置自动初始化
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
}
```

#### 3.2.2 支持的 Method Channel 方法
| 方法名 | 功能描述 | 参数 |
|--------|----------|------|
| `setup` | 初始化配置 | apiKey, host, debug, etc. |
| `identify` | 用户识别 | userId, userProperties |
| `capture` | 事件捕获 | eventName, properties |
| `screen` | 屏幕追踪 | screenName, properties |
| `alias` | 设置别名 | alias |
| `distinctId` | 获取设备 ID | - |
| `reset` | 重置用户 | - |
| `enable/disable` | 启用/禁用 | - |
| `isOptOut` | 检查是否退出 | - |
| `getFeatureFlag` | 获取特性开关 | key |
| `isFeatureEnabled` | 检查特性开关 | key |
| `getFeatureFlagPayload` | 获取开关负载 | key |
| `reloadFeatureFlags` | 重新加载开关 | - |
| `group` | 分组追踪 | groupType, groupKey |
| `register/unregister` | 注册全局属性 | key, value |
| `flush` | 刷新队列 | - |
| `captureException` | 捕获异常 | properties, timestamp |
| `close` | 关闭 SDK | - |
| `sendMetaEvent` | 发送元事件 (回放) | width, height, screen |
| `sendFullSnapshot` | 发送全量快照 | imageBytes, id, x, y |
| `isSessionReplayActive` | 检查回放状态 | - |
| `getSessionId` | 获取会话 ID | - |
| `openUrl` | 打开 URL | url |
| `surveyAction` | 调查问卷操作 | type, index, response |

#### 3.2.3 会话回放 (Session Replay) 实现
```swift
private func sendFullSnapshot(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let date = Date()
    let timestamp = dateToMillis(date)
    if let args = call.arguments as? [String: Any] {
        let id = args["id"] as? Int ?? 1
        let x = args["x"] as? Int ?? 0
        let y = args["y"] as? Int ?? 0
        guard let imageBytes = args["imageBytes"] as? FlutterStandardTypedData else {
            _badArgumentError(result)
            return
        }
        
        dispatchQueue.async {
            guard let image = UIImage(data: imageBytes.data) else { return }
            guard let base64 = imageToBase64(image) else { return }
            
            var snapshotsData: [Any] = []
            var wireframes: [Any] = []
            
            let wireframe: [String: Any] = [
                "id": id,
                "x": x,
                "y": y,
                "width": Int(image.size.width),
                "height": Int(image.size.height),
                "type": "screenshot",
                "base64": base64,
                "style": [:],
            ]
            wireframes.append(wireframe)
            
            let initialOffset = ["top": 0, "left": 0]
            let data: [String: Any] = ["initialOffset": initialOffset, "wireframes": wireframes]
            let snapshotData: [String: Any] = ["type": 2, "data": data, "timestamp": timestamp]
            snapshotsData.append(snapshotData)
            
            PostHogSDK.shared.capture("$snapshot", 
                properties: ["$snapshot_source": "mobile", "$snapshot_data": snapshotsData], 
                timestamp: date)
        }
        result(nil)
    }
}
```

#### 3.2.4 调查问卷 (Surveys) 实现
iOS 实现了 `PostHogSurveysDelegate` 协议，将原生调查问卷的渲染委托给 Flutter 层：

```swift
extension PosthogFlutterPlugin: PostHogSurveysDelegate {
    public func renderSurvey(
        _ survey: PostHogDisplaySurvey,
        onSurveyShown: @escaping OnPostHogSurveyShown,
        onSurveyResponse: @escaping OnPostHogSurveyResponse,
        onSurveyClosed: @escaping OnPostHogSurveyClosed
    ) {
        currentSurvey = survey
        onSurveyShownCallback = onSurveyShown
        onSurveyResponseCallback = onSurveyResponse
        onSurveyClosedCallback = onSurveyClosed
        
        // 通知 Flutter 层显示调查问卷
        invokeFlutterMethod("showSurvey", arguments: survey.toDict())
    }
}
```

#### 3.2.5 依赖的原生 SDK
- **PostHog iOS SDK**: 通过 CocoaPods/SPM 引入
- **核心依赖**: `PostHog` 框架

---

## 4. Android 原生层分析

### 4.1 文件位置
- 主插件: `android/src/main/kotlin/com/posthog/flutter/PosthogFlutterPlugin.kt`
- 快照发送: `android/src/main/kotlin/com/posthog/flutter/SnapshotSender.kt`
- 调查问卷代理: `android/src/main/kotlin/com/posthog/flutter/PostHogFlutterSurveysDelegate.kt`
- 调查问卷扩展: `android/src/main/kotlin/com/posthog/flutter/PostHogDisplaySurveyExt.kt`
- 版本信息: `android/src/main/kotlin/com/posthog/flutter/PostHogVersion.kt`

### 4.2 核心功能实现

#### 4.2.1 插件注册与初始化
```kotlin
class PosthogFlutterPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var applicationContext: Context
    private val snapshotSender = SnapshotSender()
    private var flutterSurveysDelegate: PostHogFlutterSurveysDelegate? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "posthog_flutter")
        this.applicationContext = flutterPluginBinding.applicationContext
        initPlugin()  // 从 AndroidManifest.xml 读取配置
        channel.setMethodCallHandler(this)
    }
}
```

#### 4.2.2 配置读取 (AndroidManifest.xml)
```kotlin
private fun initPlugin() {
    val ai = getApplicationInfo(applicationContext)
    val bundle = ai.metaData ?: Bundle()
    val autoInit = bundle.getBoolean("com.posthog.posthog.AUTO_INIT", true)
    val apiKey = bundle.getString("com.posthog.posthog.API_KEY")
    val host = bundle.getString("com.posthog.posthog.POSTHOG_HOST", PostHogConfig.DEFAULT_HOST)
    // ...
}
```

#### 4.2.3 会话回放快照发送
```kotlin
class SnapshotSender {
    fun sendFullSnapshot(imageBytes: ByteArray, id: Int, x: Int, y: Int) {
        val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
        val base64String = bitmap.base64()
        
        val wireframe = RRWireframe(
            id = id,
            x = x,
            y = y,
            width = bitmap.width,
            height = bitmap.height,
            type = "screenshot",
            base64 = base64String,
            style = RRStyle(),
        )
        
        val snapshotEvent = RRFullSnapshotEvent(
            listOf(wireframe),
            initialOffsetTop = 0,
            initialOffsetLeft = 0,
            timestamp = System.currentTimeMillis(),
        )
        
        listOf(snapshotEvent).capture()
    }
}
```

#### 4.2.4 调查问卷代理实现
```kotlin
class PostHogFlutterSurveysDelegate(private val channel: MethodChannel) : PostHogSurveysDelegate {
    override fun renderSurvey(
        survey: PostHogDisplaySurvey,
        onSurveyShown: OnPostHogSurveyShown,
        onSurveyResponse: OnPostHogSurveyResponse,
        onSurveyClosed: OnPostHogSurveyClosed
    ) {
        currentSurvey = survey
        onSurveyShownCallback = onSurveyShown
        onSurveyResponseCallback = onSurveyResponse
        onSurveyClosedCallback = onSurveyClosed
        
        // 在主线程调用 Flutter 方法
        invokeFlutterMethod("showSurvey", survey.toMap())
    }
}
```

#### 4.2.5 依赖的原生 SDK
- **PostHog Android SDK**: 通过 Gradle 引入
- **核心依赖**: `com.posthog:posthog-android`

---

## 5. Dart 层分析

### 5.1 核心类结构

```
lib/
├── posthog_flutter.dart              # 主入口，导出公共 API
├── posthog_flutter_web.dart          # Web 平台实现
└── src/
    ├── posthog.dart                  # Posthog 主类 (单例)
    ├── posthog_flutter_io.dart       # IO 平台实现 (MethodChannel)
    ├── posthog_flutter_platform_interface.dart  # 平台接口定义
    ├── posthog_config.dart           # 配置类 (PostHogConfig)
    ├── posthog_event.dart            # 事件模型
    ├── posthog_constants.dart        # 常量定义
    ├── posthog_widget.dart           # Widget 包装器
    ├── posthog_observer.dart         # 路由观察器
    ├── replay/                       # 会话回放模块
    │   ├── native_communicator.dart  # 原生通信
    │   ├── screenshot/               # 截图相关
    │   ├── mask/                     # 隐私遮罩
    │   └── element_parsers/          # 元素解析
    ├── surveys/                      # 调查问卷模块
    │   ├── survey_service.dart       # 调查问卷服务
    │   ├── models/                   # 数据模型
    │   └── widgets/                  # UI 组件
    ├── error_tracking/               # 错误追踪模块
    │   ├── dart_exception_processor.dart
    │   ├── posthog_error_tracking_autocapture_integration.dart
    │   └── ...
    └── util/                         # 工具类
```

### 5.2 Posthog 主类 (单例模式)
```dart
class Posthog {
  static PosthogFlutterPlatformInterface get _posthog =>
      PosthogFlutterPlatformInterface.instance;
  
  static final _instance = Posthog._internal();
  PostHogConfig? _config;
  String? _currentScreen;
  
  factory Posthog() => _instance;
  Posthog._internal();
  
  // 核心方法
  Future<void> setup(PostHogConfig config) async { ... }
  Future<void> identify({required String userId, ...}) async { ... }
  Future<void> capture({required String eventName, ...}) async { ... }
  Future<void> screen({required String screenName, ...}) async { ... }
  Future<Object?> getFeatureFlag(String key) async { ... }
  Future<void> captureException({required Object error, ...}) async { ... }
  // ... 更多方法
}
```

### 5.3 平台接口设计
```dart
abstract class PosthogFlutterPlatformInterface extends PlatformInterface {
  Future<void> setup(PostHogConfig config);
  Future<void> identify({required String userId, ...});
  Future<void> capture({required String eventName, ...});
  Future<void> screen({required String screenName, ...});
  Future<Object?> getFeatureFlag({required String key});
  Future<bool> isSessionReplayActive();
  Future<String?> getSessionId();
  // ... 更多抽象方法
}
```

### 5.4 会话回放实现

#### 5.4.1 截图捕获流程
```dart
// lib/src/replay/screenshot/screenshot_capturer.dart
class ScreenshotCapturer {
  Future<void> captureScreenshot() async {
    // 1. 检查是否活跃
    if (!await _nativeCommunicator.isSessionReplayActive()) return;
    
    // 2. 捕获屏幕截图
    final image = await _captureScreen();
    
    // 3. 应用隐私遮罩
    final maskedImage = await _applyMasks(image);
    
    // 4. 发送到原生层
    await _nativeCommunicator.sendFullSnapshot(
      maskedImage,
      id: _getElementId(),
      x: position.dx.toInt(),
      y: position.dy.toInt(),
    );
  }
}
```

#### 5.4.2 隐私遮罩实现
```dart
// lib/src/replay/mask/posthog_mask_widget.dart
class PostHogMaskWidget extends StatelessWidget {
  final Widget child;
  
  @override
  Widget build(BuildContext context) {
    // 使用 CustomPainter 绘制遮罩
    return CustomPaint(
      painter: ImageMaskPainter(
        maskRects: _getSensitiveAreas(),
      ),
      child: child,
    );
  }
}
```

### 5.5 调查问卷实现

#### 5.5.1 服务层
```dart
// lib/src/surveys/survey_service.dart
class SurveyService {
  Future<void> showSurvey(
    PostHogDisplaySurvey survey,
    OnPostHogSurveyShown onShown,
    OnPostHogSurveyResponse onResponse,
    OnPostHogSurveyClosed onClosed,
  ) async {
    // 显示底部弹窗
    await showModalBottomSheet(
      context: context,
      builder: (context) => SurveyBottomSheet(
        survey: survey,
        onResponse: (index, response) {
          // 通知原生层
          onResponse(survey, index, response);
        },
      ),
    );
  }
}
```

### 5.6 错误追踪实现
```dart
// lib/src/error_tracking/posthog_error_tracking_autocapture_integration.dart
class PostHogErrorTrackingAutoCaptureIntegration {
  static void install({required PostHogErrorTrackingConfig config, ...}) {
    // 捕获 Flutter 框架错误
    if (config.captureFlutterErrors) {
      FlutterError.onError = (FlutterErrorDetails details) {
        _captureFlutterError(details);
      };
    }
    
    // 捕获 PlatformDispatcher 错误
    if (config.capturePlatformDispatcherErrors) {
      PlatformDispatcher.instance.onError = (error, stack) {
        _capturePlatformError(error, stack);
        return false;
      };
    }
    
    // 捕获 Isolate 错误
    if (config.captureIsolateErrors) {
      Isolate.current.addErrorListener(...);
    }
  }
}
```

---

## 6. 核心功能模块

### 6.1 事件追踪 (Event Tracking)
| 功能 | 描述 | 实现位置 |
|------|------|----------|
| capture | 自定义事件追踪 | Dart + Native |
| screen | 屏幕浏览追踪 | Dart + Native |
| identify | 用户识别 | Dart + Native |
| alias | 用户别名 | Dart + Native |
| group | 分组追踪 | Dart + Native |

### 6.2 特性开关 (Feature Flags)
| 功能 | 描述 | 实现位置 |
|------|------|----------|
| getFeatureFlag | 获取开关值 | Native SDK |
| isFeatureEnabled | 检查开关状态 | Native SDK |
| getFeatureFlagPayload | 获取负载数据 | Native SDK |
| reloadFeatureFlags | 重新加载 | Native SDK |
| onFeatureFlags 回调 | 开关更新通知 | Native → Dart |

### 6.3 会话回放 (Session Replay)
| 功能 | 描述 | 实现位置 |
|------|------|----------|
| 屏幕截图 | 定时捕获屏幕 | Dart (replay/screenshot) |
| 隐私遮罩 | 敏感信息遮挡 | Dart (replay/mask) |
| 快照发送 | 发送到服务器 | Dart → Native |
| 元事件 | 屏幕尺寸信息 | Dart → Native |

### 6.4 调查问卷 (Surveys)
| 功能 | 描述 | 实现位置 |
|------|------|----------|
| 问卷显示 | 底部弹窗展示 | Dart (surveys/widgets) |
| 问题类型 | 单选/多选/评分/文本 | Dart |
| 响应收集 | 用户答案收集 | Dart → Native |
| 原生委托 | 问卷生命周期管理 | Native |

### 6.5 错误追踪 (Error Tracking)
| 功能 | 描述 | 实现位置 |
|------|------|----------|
| Flutter 错误 | FlutterError.onError | Dart |
| PlatformDispatcher 错误 | 平台调度器错误 | Dart |
| Isolate 错误 | 隔离区错误 | Dart |
| 原生异常 (Android) | Java/Kotlin 异常 | Native |

---

## 7. 鸿蒙化可行性分析

### 7.1 鸿蒙平台支持情况

#### 7.1.1 Flutter on HarmonyOS
- **现状**: Flutter 官方已支持 OpenHarmony/HarmonyOS NEXT
- **版本要求**: Flutter 3.22+ (与当前 SDK 要求一致)
- **平台标识**: `platform` 为 `ohos` (OpenHarmony OS)

#### 7.1.2 原生 SDK 依赖分析

| 依赖项 | iOS | Android | 鸿蒙可用性 | 替代方案 |
|--------|-----|---------|-----------|----------|
| PostHog iOS SDK | ✅ | - | ❌ | 需自行实现或使用 HTTP API |
| PostHog Android SDK | - | ✅ | ⚠️ 部分 | 需适配或自行实现 |
| MethodChannel | ✅ | ✅ | ✅ | Flutter 官方支持 |

### 7.2 可行性评估

#### 7.2.1 高可行性 (可直接复用 Dart 代码)
- ✅ Dart 层业务逻辑 (posthog.dart)
- ✅ 平台接口定义 (posthog_flutter_platform_interface.dart)
- ✅ 调查问卷 UI (surveys/widgets/)
- ✅ 错误追踪 (部分功能)
- ✅ 路由观察器 (posthog_observer.dart)

#### 7.2.2 中等可行性 (需适配)
- ⚠️ 会话回放截图 (replay/screenshot/) - 需验证鸿蒙截图 API
- ⚠️ 隐私遮罩 (replay/mask/) - 需验证渲染性能
- ⚠️ 文件存储/缓存 - 需使用鸿蒙文件 API

#### 7.2.3 需重新实现 (原生层)
- ❌ iOS/Android 原生插件实现
- ❌ PostHog 原生 SDK 功能
- ❌ 网络请求/队列管理
- ❌ 设备信息获取
- ❌ 应用生命周期监听

---

## 8. 鸿蒙化实施方案

### 8.1 方案一：原生插件实现 (推荐)

#### 8.1.1 架构设计
```
┌─────────────────────────────────────────────────────────────┐
│                    Dart 层 (Flutter)                         │
│              (复用现有代码，无需修改)                          │
├─────────────────────────────────────────────────────────────┤
│              Platform Channel (MethodChannel)               │
├─────────────────────────────────────────────────────────────┤
│              鸿蒙原生层 (HarmonyOS ArkTS/Native)              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │           PosthogFlutterPlugin (ArkTS)                 │  │
│  │  - MethodChannel 处理                                   │  │
│  │  - 业务逻辑转发                                         │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │         PostHog HarmonyOS SDK (ArkTS/Native)           │  │
│  │  - 事件队列管理                                         │  │
│  │  - 网络请求 (HTTP Client)                               │  │
│  │  - 本地存储 (Preferences/文件)                          │  │
│  │  - 设备信息获取                                         │  │
│  │  - 会话管理                                             │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

#### 8.1.2 目录结构
```
posthog-flutter/
├── ohos/                           # 新增鸿蒙平台目录
│   ├── src/main/ets/               # ArkTS 源码
│   │   ├── components/
│   │   │   └── PosthogFlutterPlugin.ets    # 主插件类
│   │   ├── sdk/
│   │   │   ├── PostHog.ets         # SDK 主类
│   │   │   ├── PostHogConfig.ets   # 配置类
│   │   │   ├── PostHogQueue.ets    # 事件队列
│   │   │   ├── PostHogApi.ets      # HTTP API
│   │   │   ├── PostHogStorage.ets  # 本地存储
│   │   │   └── PostHogReplay.ets   # 会话回放
│   │   └── utils/
│   │       └── ...
│   ├── build-profile.json5
│   ├── hvigorfile.ts
│   └── oh-package.json5
└── lib/
    └── src/
        └── util/
            └── platform_io_real.dart  # 修改：添加鸿蒙支持
```

#### 8.1.3 核心实现步骤

**Step 1: 创建鸿蒙插件模块**
```typescript
// ohos/src/main/ets/components/PosthogFlutterPlugin.ets
import { FlutterPlugin, MethodCall, MethodResult } from '@ohos/flutter_ohos';

export default class PosthogFlutterPlugin implements FlutterPlugin {
  private channel: MethodChannel;
  private context: Context;
  
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'posthog_flutter');
    this.context = binding.getApplicationContext();
    this.channel.setMethodCallHandler(this);
    this.initPlugin();
  }
  
  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'setup':
        this.setup(call, result);
        break;
      case 'capture':
        this.capture(call, result);
        break;
      // ... 其他方法
      default:
        result.notImplemented();
    }
  }
}
```

**Step 2: 实现 PostHog 核心 SDK**
```typescript
// ohos/src/main/ets/sdk/PostHog.ets
export class PostHog {
  private static instance: PostHog;
  private config: PostHogConfig;
  private queue: PostHogQueue;
  private api: PostHogApi;
  
  static getSharedInstance(): PostHog {
    if (!PostHog.instance) {
      PostHog.instance = new PostHog();
    }
    return PostHog.instance;
  }
  
  setup(config: PostHogConfig): void {
    this.config = config;
    this.queue = new PostHogQueue(config);
    this.api = new PostHogApi(config);
    
    // 启动定时刷新
    this.startFlushTimer();
    
    // 恢复未发送事件
    this.queue.restore();
  }
  
  capture(event: string, properties?: Record<string, Object>): void {
    const eventData = {
      event: event,
      properties: {
        ...properties,
        $lib: 'posthog-flutter',
        $lib_version: POSTHOG_VERSION,
      },
      timestamp: new Date().toISOString(),
      distinct_id: this.getDistinctId(),
    };
    
    this.queue.enqueue(eventData);
    
    // 达到阈值立即发送
    if (this.queue.size() >= this.config.flushAt) {
      this.flush();
    }
  }
  
  async flush(): Promise<void> {
    const events = this.queue.dequeueAll();
    if (events.length === 0) return;
    
    try {
      await this.api.sendEvents(events);
    } catch (error) {
      // 发送失败，重新入队
      this.queue.requeue(events);
    }
  }
}
```

**Step 3: HTTP API 实现**
```typescript
// ohos/src/main/ets/sdk/PostHogApi.ets
import http from '@ohos.net.http';

export class PostHogApi {
  private config: PostHogConfig;
  
  async sendEvents(events: Array<Record<string, Object>>): Promise<void> {
    const httpRequest = http.createHttp();
    const url = `${this.config.host}/batch`;
    
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
      },
      extraData: JSON.stringify({
        api_key: this.config.apiKey,
        batch: events,
      }),
    });
    
    if (response.responseCode !== 200) {
      throw new Error(`HTTP ${response.responseCode}`);
    }
  }
  
  async getFeatureFlags(distinctId: string): Promise<Record<string, Object>> {
    // 实现特性开关获取
  }
}
```

**Step 4: 本地存储实现**
```typescript
// ohos/src/main/ets/sdk/PostHogStorage.ets
import preferences from '@ohos.data.preferences';

export class PostHogStorage {
  private preferences: preferences.Preferences;
  
  async init(context: Context): Promise<void> {
    this.preferences = await preferences.getPreferences(context, 'posthog');
  }
  
  async setString(key: string, value: string): Promise<void> {
    await this.preferences.put(key, value);
    await this.preferences.flush();
  }
  
  async getString(key: string): Promise<string | null> {
    return await this.preferences.get(key, null) as string;
  }
  
  async saveQueue(events: Array<Record<string, Object>>): Promise<void> {
    await this.setString('event_queue', JSON.stringify(events));
  }
  
  async loadQueue(): Promise<Array<Record<string, Object>>> {
    const data = await this.getString('event_queue');
    return data ? JSON.parse(data) : [];
  }
}
```

**Step 5: 会话回放实现**
```typescript
// ohos/src/main/ets/sdk/PostHogReplay.ets
import image from '@ohos.multimedia.image';

export class PostHogReplay {
  async sendFullSnapshot(
    imageBytes: ArrayBuffer,
    id: number,
    x: number,
    y: number
  ): Promise<void> {
    // 将图片转为 Base64
    const base64 = this.arrayBufferToBase64(imageBytes);
    
    // 获取图片尺寸
    const imageSource = image.createImageSource(imageBytes);
    const imageInfo = await imageSource.getImageInfo();
    
    const snapshot = {
      type: 2,  // Full Snapshot
      data: {
        wireframes: [{
          id: id,
          x: x,
          y: y,
          width: imageInfo.size.width,
          height: imageInfo.size.height,
          type: 'screenshot',
          base64: base64,
          style: {},
        }],
        initialOffset: { top: 0, left: 0 },
      },
      timestamp: Date.now(),
    };
    
    PostHog.getSharedInstance().capture('$snapshot', {
      $snapshot_source: 'mobile',
      $snapshot_data: [snapshot],
    });
  }
  
  private arrayBufferToBase64(buffer: ArrayBuffer): string {
    const bytes = new Uint8Array(buffer);
    let binary = '';
    for (let i = 0; i < bytes.byteLength; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    return btoa(binary);
  }
}
```

**Step 6: 修改 Dart 层支持鸿蒙**
```dart
// lib/src/util/platform_io_real.dart
import 'dart:io';

bool isSupportedPlatform() {
  return Platform.isAndroid || 
         Platform.isIOS || 
         Platform.isMacOS ||
         Platform.isWindows ||
         Platform.isLinux ||
         _isHarmonyOS();  // 新增鸿蒙检测
}

bool _isHarmonyOS() {
  // 通过 Platform.operatingSystem 或特定标识检测
  return Platform.operatingSystem == 'ohos' ||
         Platform.environment.containsKey('HARMONYOS');
}
```

**Step 7: 更新 pubspec.yaml**
```yaml
flutter:
  plugin:
    platforms:
      android:
        package: com.posthog.flutter
        pluginClass: PosthogFlutterPlugin
      ios:
        pluginClass: PosthogFlutterPlugin
      macos:
        pluginClass: PosthogFlutterPlugin
      web:
        pluginClass: PosthogFlutterWeb
        fileName: posthog_flutter_web.dart
      ohos:  # 新增鸿蒙平台
        package: com.posthog.flutter
        pluginClass: PosthogFlutterPlugin
```

### 8.2 方案二：纯 Dart 实现 (备选)

#### 8.2.1 适用场景
- 不需要原生特定功能（如应用生命周期、推送等）
- 希望减少原生代码维护成本
- 对性能要求不高的场景

#### 8.2.2 实现思路
```dart
// 纯 Dart 实现，使用 dart:io 进行 HTTP 请求
class PostHogDartOnly {
  final String apiKey;
  final String host;
  final List<Map<String, dynamic>> _queue = [];
  
  Future<void> capture(String event, {Map<String, dynamic>? properties}) async {
    _queue.add({
      'event': event,
      'properties': properties,
      'timestamp': DateTime.now().toIso8601String(),
    });
    
    if (_queue.length >= 20) {
      await _flush();
    }
  }
  
  Future<void> _flush() async {
    final client = HttpClient();
    final request = await client.postUrl(Uri.parse('$host/batch'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'api_key': apiKey,
      'batch': _queue,
    }));
    await request.close();
    _queue.clear();
  }
}
```

### 8.3 功能实现优先级

| 优先级 | 功能模块 | 说明 |
|--------|----------|------|
| P0 | 事件追踪 (capture, identify, screen) | 核心功能，必须实现 |
| P0 | 特性开关 (Feature Flags) | 核心功能，必须实现 |
| P1 | 队列管理与批量发送 | 保证数据不丢失 |
| P1 | 本地存储与恢复 | 离线支持 |
| P2 | 会话回放 (Session Replay) | 高级功能 |
| P2 | 调查问卷 (Surveys) | 高级功能 |
| P3 | 错误追踪 (原生异常) | 增强功能 |
| P3 | 应用生命周期追踪 | 增强功能 |

---

## 9. 工作量评估

### 9.1 方案一：原生插件实现

| 模块 | 工作量 | 说明 |
|------|--------|------|
| 鸿蒙插件框架搭建 | 2-3 天 | 创建 ohos 目录结构，配置构建文件 |
| MethodChannel 实现 | 2-3 天 | 实现所有 Dart-Native 通信方法 |
| PostHog 核心 SDK | 5-7 天 | 事件队列、HTTP API、存储 |
| 特性开关功能 | 2-3 天 | Feature Flags 获取与缓存 |
| 会话回放 | 3-5 天 | 图片处理、Base64 编码 |
| 调查问卷 | 2-3 天 | 代理实现、回调处理 |
| Dart 层适配 | 1-2 天 | 平台检测、条件编译 |
| 测试与调试 | 3-5 天 | 功能测试、性能测试 |
| **总计** | **20-31 天** | 约 1-1.5 个月 |

### 9.2 方案二：纯 Dart 实现

| 模块 | 工作量 | 说明 |
|------|--------|------|
| HTTP 客户端封装 | 1-2 天 | 使用 dart:io |
| 事件队列管理 | 2-3 天 | 内存队列 + 持久化 |
| 核心 API 实现 | 3-5 天 | capture, identify 等 |
| 特性开关 | 2-3 天 | HTTP 轮询 |
| Dart 层适配 | 1 天 | 平台检测 |
| **总计** | **9-14 天** | 约 0.5 个月 |

---

## 10. 风险与挑战

### 10.1 技术风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 鸿蒙 Flutter 版本兼容性 | 高 | 持续跟进 Flutter 官方版本，使用稳定版 |
| PostHog API 变更 | 中 | 关注官方文档，保持版本同步 |
| 性能问题 (会话回放) | 中 | 优化截图频率，使用压缩算法 |
| 网络不稳定 | 中 | 实现可靠的队列重试机制 |

### 10.2 依赖风险

| 依赖项 | 风险等级 | 说明 |
|--------|----------|------|
| Flutter HarmonyOS 支持 | 中 | 需验证 MethodChannel 稳定性 |
| HTTP Client | 低 | 鸿蒙提供标准网络 API |
| 图片处理 | 低 | 鸿蒙提供 image 模块 |
| 本地存储 | 低 | 鸿蒙提供 preferences 模块 |

### 10.3 维护成本

- **代码同步**: 需要定期同步官方 SDK 更新
- **多平台维护**: iOS、Android、鸿蒙三端代码维护
- **测试成本**: 需要在鸿蒙设备上进行充分测试

---

## 11. 建议与总结

### 11.1 推荐方案

**方案一（原生插件实现）** 是更优选择，原因：
1. 与现有架构保持一致，便于维护
2. 可以充分利用鸿蒙原生能力
3. 性能更好，功能更完整
4. 便于后续功能扩展

### 11.2 实施建议

1. **分阶段实施**: 先实现核心功能 (P0)，再逐步添加高级功能
2. **保持接口兼容**: 确保 Dart 层 API 与官方 SDK 一致
3. **充分测试**: 在真实鸿蒙设备上进行测试
4. **文档完善**: 编写鸿蒙平台接入文档

### 11.3 结论

PostHog Flutter SDK 的鸿蒙化是**可行**的，主要工作集中在原生层的重新实现。Dart 层代码可以高度复用，开发工作量在可控范围内（约 1-1.5 个月）。

---

## 附录

### A. 参考链接
- [PostHog Flutter SDK 官方文档](https://posthog.com/docs/libraries/flutter)
- [Flutter HarmonyOS 适配指南](https://gitee.com/openharmony/flutter_flutter)
- [鸿蒙开发者文档](https://developer.harmonyos.com/)
- [PostHog HTTP API 文档](https://posthog.com/docs/api)

### B. 关键文件清单

| 文件路径 | 说明 |
|----------|------|
| `lib/src/posthog.dart` | Dart 层主 API |
| `lib/src/posthog_flutter_io.dart` | IO 平台实现 |
| `lib/src/posthog_flutter_platform_interface.dart` | 平台接口 |
| `ios/Classes/PosthogFlutterPlugin.swift` | iOS 原生实现 |
| `android/src/main/kotlin/com/posthog/flutter/PosthogFlutterPlugin.kt` | Android 原生实现 |
| `lib/src/replay/` | 会话回放 Dart 实现 |
| `lib/src/surveys/` | 调查问卷 Dart 实现 |

---

*文档生成时间: 2026-01-30*
*分析版本: posthog_flutter v5.12.0*
