# PostHog Flutter SDK 鸿蒙平台开发计划

## 概述

为 PostHog Flutter SDK 添加鸿蒙（HarmonyOS）平台支持，实现与 iOS/Android 平台功能对等的事件追踪、功能标志、会话回放和调查问卷功能。

## 技术方案

### 核心决策：纯 Dart + 最小原生调用

由于 PostHog 官方**没有鸿蒙原生 SDK**，采用以下方案：
- **HTTP API 直接调用**：通过 PostHog 的 `/batch` 和 `/decide` 端点与服务器通信
- **Dart 层实现核心逻辑**：事件队列、存储、批处理
- **原生层最小化**：仅处理截图、URL 打开、设备信息获取

### 方案优势
- 开发周期短（4-6 周 MVP，16-22 周完整版）
- 维护成本低，代码可控
- 不依赖第三方原生 SDK
- 与现有架构无缝集成

---

## 目录结构

```
posthog-flutter/
├── ohos/                                    # 新增鸿蒙平台目录
│   ├── entry/
│   │   └── src/
│   │       └── main/
│   │           ├── ets/
│   │           │   ├── plugin/
│   │           │   │   ├── PosthogFlutterPlugin.ets         # 主插件类
│   │           │   │   ├── PosthogMethodCallHandler.ets      # 方法处理器
│   │           │   │   ├── screenshot/
│   │           │   │   │   └── ScreenshotCapturer.ets        # 截图功能
│   │           │   │   └── utils/
│   │           │   │       ├── DeviceInfo.ets                # 设备信息
│   │           │   │       └── Logger.ets                    # 日志
│   │           ├── module.json5                               # 模块配置
│   │           └── resources/
│   └── oh-package.json5
├── lib/
│   └── src/
│       ├── posthog_flutter_harmonyos.dart                    # 新增：鸿蒙平台实现
│       ├── core/
│       │   ├── http/
│       │   │   ├── posthog_api_client.dart                   # HTTP API 客户端
│       │   │   └── feature_flags_api.dart                    # 功能标志 API
│       │   ├── storage/
│       │   │   ├── event_queue.dart                          # 事件队列
│       │   │   └── storage_manager.dart                      # 存储管理
│       │   └── models/
│       │       └── batch_event.dart                          # 批量事件模型
│       └── util/
│           └── platform_io_real.dart                          # 修改：添加鸿蒙支持
└── pubspec.yaml                                              # 修改：添加鸿蒙平台
```

---

## 关键文件清单

### 需要新建的文件

| 文件路径 | 说明 | 优先级 |
|---------|------|--------|
| `ohos/entry/src/main/ets/plugin/PosthogFlutterPlugin.ets` | 鸿蒙插件主类 | ⭐⭐⭐ |
| `ohos/entry/src/main/ets/plugin/PosthogMethodCallHandler.ets` | MethodChannel 处理器 | ⭐⭐⭐ |
| `ohos/entry/src/main/ets/plugin/utils/DeviceInfo.ets` | 设备信息工具 | ⭐⭐⭐ |
| `ohos/entry/src/main/module.json5` | 鸿蒙模块配置 | ⭐⭐⭐ |
| `lib/src/posthog_flutter_harmonyos.dart` | 鸿蒙平台 Dart 实现 | ⭐⭐⭐ |
| `lib/src/core/http/posthog_api_client.dart` | HTTP API 客户端 | ⭐⭐⭐ |
| `lib/src/core/storage/event_queue.dart` | 事件队列管理 | ⭐⭐⭐ |

### 需要修改的文件

| 文件路径 | 修改内容 |
|---------|----------|
| `lib/src/util/platform_io_real.dart` | 添加鸿蒙平台检测 |
| `pubspec.yaml` | 添加 harmonyos 平台配置和 http、shared_preferences 依赖 |

---

## 实现步骤

### 第一阶段：MVP 核心功能（4-6 周）

**目标**：基础事件追踪和功能标志

1. **创建鸿蒙插件基础结构**（2 天）
   - 创建 `ohos/` 目录结构
   - 编写 `module.json5` 配置
   - 实现 `PosthogFlutterPlugin.ets` 主类

2. **实现 HTTP API 客户端**（5 天）
   - 实现 `PosthogApiClient` 类
   - 实现 `/batch` 端点调用
   - 实现 `/decide` 端点调用
   - 添加错误处理和重试逻辑

3. **实现事件队列管理**（4 天）
   - 实现 `EventQueue` 类
   - 支持内存队列和磁盘持久化
   - 实现批量发送逻辑
   - 添加自动刷新定时器

4. **实现核心 API**（5 天）
   - 实现 `setup()` 方法
   - 实现 `capture()` 方法
   - 实现 `identify()` 方法
   - 实现 `screen()` 方法
   - 实现 `flush()` 和 `reset()` 方法

5. **实现功能标志**（5 天）
   - 实现 `getFeatureFlag()` 方法
   - 实现 `isFeatureEnabled()` 方法
   - 实现 `reloadFeatureFlags()` 方法
   - 添加本地缓存

6. **实现设备信息获取**（3 天）
   - ArkTS 层实现 `DeviceInfo.ets`
   - 获取设备型号、OS 版本等
   - 通过 MethodChannel 传递给 Dart 层

7. **Dart 层平台适配**（2 天）
   - 修改 `platform_io_real.dart` 支持鸿蒙
   - 实现自动平台注册逻辑
   - 更新 `pubspec.yaml`

8. **测试**（5 天）
   - 单元测试
   - 集成测试
   - 真机验证

**交付物**：
- ✅ 基础事件追踪（capture, identify, screen）
- ✅ 功能标志（getFeatureFlag, isFeatureEnabled）
- ✅ 事件队列和批量发送
- ✅ 用户管理（reset, flush, getDistinctId）

---

### 第二阶段：高级功能（3-4 周）

1. **实现组事件**（3 天）
   - 实现 `group()` 方法
   - 支持组属性设置

2. **实现超级属性**（3 天）
   - 实现 `register()` 方法
   - 实现 `unregister()` 方法
   - 持久化超级属性

3. **实现异常捕获**（4 天）
   - 实现 `captureException()` 方法
   - 集成现有错误追踪模块
   - 栈帧解析

4. **实现会话管理**（3 天）
   - 实现 `getSessionId()` 方法
   - 会话生命周期管理

5. **实现禁用/启用**（2 天）
   - 实现 `enable()` 方法
   - 实现 `disable()` 方法
   - 实现 `isOptOut()` 方法

6. **性能优化**（5 天）
   - 内存优化
   - 网络请求优化
   - 队列管理优化

**交付物**：
- ✅ 组事件追踪
- ✅ 超级属性
- ✅ 异常追踪
- ✅ 会话管理
- ✅ 禁用/启用控制

---

### 第三阶段：Session Replay（4-5 周）

1. **研究鸿蒙截图 API**（3 天）
   - 调研 `@ohos.screenshot` API
   - 调研权限要求

2. **实现截图捕获器**（7 天）
   - 实现 `ScreenshotCapturer.ets`
   - 请求截图权限
   - 截取屏幕

3. **实现图片转 Base64**（3 天）
   - PixelMap 转 JPEG/PNG
   - Base64 编码

4. **实现快照管理器**（5 天）
   - 实现 `SnapshotManager.dart`
   - 实现元事件发送
   - 实现完整快照发送

5. **实现节流和优化**（3 天）
   - 添加节流逻辑
   - 图片压缩优化

6. **测试**（5 天）

**交付物**：
- ✅ 截图功能
- ✅ Session Replay 基础实现
- ✅ 性能优化

---

### 第四阶段：Surveys 问卷（3-4 周）

1. **复用现有问卷 UI**（5 天）
   - 现有 Flutter 问卷 UI 无需修改
   - 鸿蒙层只需提供数据

2. **实现问卷回调**（3 天）
   - 实现 `showSurvey()` 方法
   - 实现 `surveyAction()` 处理

3. **集成 MethodChannel**（3 天）

4. **测试**（4 天）

**交付物**：
- ✅ 问卷显示功能
- ✅ 问卷响应处理

---

### 第五阶段：优化和发布（2-3 周）

1. **性能优化**（5 天）
   - 内存管理
   - 网络优化
   - 并发优化

2. **错误处理**（3 天）
   - 完善错误处理
   - 日志系统

3. **文档编写**（4 天）
   - 接入文档
   - API 文档
   - 示例代码

4. **示例应用**（3 天）

5. **发布**（2 天）

---

## MethodChannel 方法映射

| Flutter 方法 | HarmonyOS 实现 | 说明 |
|-------------|---------------|------|
| `setup` | Dart 层处理 | 初始化 API 客户端、事件队列 |
| `capture` | Dart → HTTP API | 事件捕获，通过 /batch 端点 |
| `screen` | Dart → HTTP API | 屏幕浏览事件 |
| `identify` | Dart → HTTP API | 用户识别 |
| `alias` | Dart → HTTP API | 用户别名 |
| `group` | Dart → HTTP API | 组事件 |
| `getFeatureFlag` | Dart → /decide API | 获取功能标志值 |
| `isFeatureEnabled` | Dart → /decide API | 功能标志判断 |
| `reloadFeatureFlags` | Dart → /decide API | 重新加载功能标志 |
| `flush` | Dart → HTTP API | 立即发送队列 |
| `reset` | Dart 清除存储 | 重置状态 |
| `getDistinctId` | Dart 存储读取 | 获取用户 ID |
| `register` | Dart 存储超级属性 | 注册超级属性 |
| `unregister` | Dart 删除超级属性 | 删除超级属性 |
| `enable` | Dart 设置标志 | 启用追踪 |
| `disable` | Dart 设置标志 | 禁用追踪 |
| `isOptOut` | Dart 读取标志 | 检查是否退出 |
| `captureException` | Dart → HTTP API | 异常捕获 |
| `getSessionId` | Dart 会话管理 | 会话 ID |
| `close` | Dart 清理资源 | 关闭 SDK |
| `captureScreenshot` | ArkTS 截图 | Session Replay |
| `openUrl` | ArkTS 打开浏览器 | 打开链接 |
| `getDeviceInfo` | ArkTS 设备信息 | 获取设备属性 |
| `showSurvey` | Dart UI + 回调 | 显示问卷 |
| `surveyAction` | Dart 处理响应 | 问卷交互 |

---

## pubspec.yaml 配置

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
      harmonyos:
        pluginClass: PosthogFlutterPlugin
        fileName: posthog_flutter_harmonyos.dart

dependencies:
  http: ^1.2.0
  shared_preferences: ^2.2.0
```

---

## 测试验证

### 单元测试
- `PosthogApiClient` 测试
- `EventQueue` 测试
- `FeatureFlags` 测试

### 集成测试
- 端到端事件追踪测试
- 功能标志测试
- 离线队列测试

### 真机验证
- 鸿蒙设备上运行示例应用
- 验证所有核心功能
- 性能测试

---

## 工作量评估

| 阶段 | 工作量 |
|-----|--------|
| 第一阶段（MVP） | 4-6 周 |
| 第二阶段（高级） | 3-4 周 |
| 第三阶段 | 4-5 周 |
| 第四阶段 | 3-4 周 |
| 第五阶段（优化） | 2-3 周 |
| **总计** | **16-22 周** |

---

## 关键风险

| 风险 | 缓解措施 |
|-----|----------|
| PostHog API 变更 | 版本锁定 + 抽象层设计 |
| 鸿蒙截图 API 限制 | 提前技术预研 + 备选方案 |
| 网络不稳定 | 离线队列 + 自动重试 |
| 性能问题 | 批量发送 + 本地队列 + 节流 |

---

## 参考资料

- PostHog HTTP API: https://posthog.com/docs/api/capture
- Feature Flags API: https://posthog.com/docs/api/feature-flags
- 鸿蒙网络请求: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-http
