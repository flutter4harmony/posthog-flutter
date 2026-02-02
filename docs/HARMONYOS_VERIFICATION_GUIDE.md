# PostHog Flutter SDK - 鸿蒙平台验证指南

## 前置要求

### 1. 开发环境
- DevEco Studio 4.0+
- HarmonyOS SDK API 9+
- Flutter SDK 3.0+
- 真机或模拟器（推荐使用真机）

### 2. PostHog 账号
- 注册 [PostHog](https://app.posthog.com/) 账号
- 创建项目并获取 API Key

---

## 验证步骤

### 第一步：构建应用

```bash
# 1. 确保 Flutter 环境正常
flutter doctor

# 2. 获取依赖
flutter pub get

# 3. 在 example 目录中使用测试应用
# 或将 example_harmonyos_test.dart 复制到你的项目中

# 4. 构建鸿蒙应用
flutter build --help  # 查看构建选项
```

### 第二步：配置 API Key

在测试应用中替换 `YOUR_API_KEY`：

```dart
await Posthog().setup(
  PostHogConfig(
    apiKey: 'phc_YOUR_ACTUAL_API_KEY', // 替换这里
    host: 'https://app.posthog.com',
    debug: true, // 重要：启用调试日志
  ),
);
```

### 第三步：运行应用并查看日志

#### 方法 1：DevEco Studio 日志
1. 在 DevEco Studio 中打开项目
2. 连接鸿蒙设备或启动模拟器
3. 点击 Run 运行应用
4. 在 HiLog 窗口中查看日志

#### 方法 2：命令行查看日志
```bash
# 查看设备日志
hdc shell hilog | grep PostHog

# 或者查看所有日志
hdc shell hilog
```

### 第四步：功能验证清单

#### ✅ 1. 基础事件追踪

**测试步骤：**
1. 点击"捕获简单事件"按钮
2. 点击"捕获带属性的事件"按钮
3. 点击"发送多个事件"按钮

**验证点：**
- 日志显示 `📤 beforeSend: button_clicked`
- 日志显示 `✅ 捕获简单事件`
- 在 PostHog Dashboard 的 "Events" 页面能看到事件
- 事件属性正确显示

**PostHog Dashboard 验证：**
```
1. 打开 https://app.posthog.com/
2. 进入你的项目
3. 点击左侧 "Events"
4. 搜索 "button_clicked", "purchase_completed"
5. 点击事件查看属性
```

---

#### ✅ 2. 用户识别

**测试步骤：**
1. 记录当前 Distinct ID（应该是匿名 ID，如 `timestamp-xxx`）
2. 点击"识别用户"按钮
3. 观察 Distinct ID 是否变为你设置的用户 ID（如 `user_xxx`）
4. 点击"重置用户"按钮
5. 观察 Distinct ID 是否重新生成为匿名 ID

**验证点：**
- 日志显示识别成功
- Distinct ID 正确更新
- 在 PostHog Dashboard 的 "Persons" 页面能看到用户

**PostHog Dashboard 验证：**
```
1. 点击左侧 "Persons"
2. 搜索你的用户 ID
3. 查看用户属性（name, email, plan）
```

---

#### ✅ 3. 屏幕浏览追踪

**测试步骤：**
1. 启用 `captureScreenViews: true`
2. 在不同屏幕间切换
3. 点击"屏幕浏览事件"按钮

**验证点：**
- 日志显示屏幕浏览事件
- PostHog Dashboard 能看到 `$pageview` 事件
- 屏幕名称正确

---

#### ✅ 4. 超级属性

**测试步骤：**
1. 点击"注册超级属性"
2. 点击"捕获简单事件"
3. 在 PostHog Dashboard 查看事件属性
4. 点击"注册一次属性"
5. 点击"删除超级属性"
6. 再次捕获事件

**验证点：**
- 第一次捕获的事件包含 `user_type: tester`
- `first_open` 属性只出现一次
- 删除后的事件不再包含 `user_type`

**PostHog Dashboard 验证：**
```
1. 打开任意事件详情
2. 查看 "Event Properties"
3. 应该看到 user_type, app_version 等超级属性
```

---

#### ✅ 5. 功能标志

**前置准备：**
在 PostHog Dashboard 中创建功能标志：
```
1. 点击左侧 "Feature Flags"
2. 点击 "New feature flag"
3. Key: test-feature
4. 创建
```

**测试步骤：**
1. 点击"重新加载功能标志"
2. 点击"检查功能是否启用"
3. 点击"获取功能标志值"
4. 在 Dashboard 中切换功能标志状态
5. 重新测试

**验证点：**
- 日志显示 `✅ Feature flags loaded`
- 功能状态正确显示
- 切换 Dashboard 中的状态后，应用中状态同步更新

---

#### ✅ 6. 组事件

**测试步骤：**
1. 点击"发送组事件"按钮
2. 查看日志输出

**验证点：**
- 日志显示成功
- PostHog Dashboard 能看到组信息

**PostHog Dashboard 验证：**
```
1. 点击左侧 "Groups"
2. 选择 "company" 类型
3. 应该能看到 "acme-corp" 组
```

---

#### ✅ 7. 异常捕获

**手动捕获测试：**
1. 点击"捕获异常"按钮
2. 查看日志

**自动捕获测试：**
1. 确保配置中启用了错误追踪：
   ```dart
   errorTrackingConfig: PostHogErrorTrackingConfig(
     captureFlutterErrors: true,
     capturePlatformDispatcherErrors: true,
   ),
   ```
2. 点击"触发异常"按钮
3. 应用可能崩溃或显示错误

**验证点：**
- 日志显示异常被捕获
- PostHog Dashboard 能看到 `$exception` 事件
- 异常栈帧信息正确

**PostHog Dashboard 验证：**
```
1. 点击左侧 "Events"
2. 搜索 "$exception"
3. 查看异常详情和栈帧
```

---

#### ✅ 8. 应用生命周期事件

**测试步骤：**
1. 启用 `captureApplicationLifecycleEvents: true`
2. 切换到后台（Home 键）
3. 重新打开应用
4. 重复多次

**验证点：**
- 日志显示 `Application Lifecycle: paused`
- 日志显示 `Application Lifecycle: resumed`
- PostHog Dashboard 能看到 `$set` 事件

---

#### ✅ 9. SDK 控制

**测试步骤：**
1. 点击"禁用 SDK"
2. 尝试捕获事件
3. 点击"启用 SDK"
4. 再次尝试捕获事件

**验证点：**
- 禁用后事件不被发送（或被忽略）
- 启用后事件正常发送
- 日志显示正确的状态

---

#### ✅ 10. 队列管理

**测试步骤：**
1. 快速点击"发送多个事件"多次
2. 观察日志中的队列大小
3. 点击"立即发送队列"
4. 在 Dashboard 验证事件已接收

**验证点：**
- 事件按批处理发送
- 队列大小正确显示
- 手动刷新立即发送

**PostHog Dashboard 验证：**
```
1. 查看 "Live Events" 页面
2. 应该能看到事件实时到达
```

---

#### ⚠️ 11. Session Replay（框架完成）

**当前状态：**
- 框架代码已完成
- 由于鸿蒙截图 API 限制，实际截图功能待官方 API 完善

**测试步骤：**
1. 点击"手动截图"
2. 观察日志

**预期结果：**
```
ℹ️ 截图功能待鸿蒙 API 完善
```

**未来验证：**
- 截图成功返回 Base64
- PostHog Dashboard 能查看回放

---

#### ✅ 12. 网络请求

**测试步骤：**
1. 点击"打开 URL"
2. 验证浏览器是否打开

**验证点：**
- 系统浏览器打开 posthog.com

---

### 第五步：PostHog Dashboard 综合验证

#### 1. 实时事件流
```
1. 打开 https://app.posthog.com/project/YOUR_PROJECT_ID/live
2. 在测试应用中执行各种操作
3. 应该能看到事件实时流式到达
```

#### 2. 用户活动
```
1. 点击左侧 "Persons"
2. 查看识别的用户列表
3. 点击用户查看详细活动
```

#### 3. 事件分析
```
1. 点击左侧 "Insights"
2. 创建新的 Insight
3. 选择 "Trends"
4. 选择测试的事件
5. 应该能看到事件趋势图
```

#### 4. 功能标志使用
```
1. 点击左侧 "Feature Flags"
2. 查看功能标志使用情况
3. 查看曝光用户数
```

---

## 日志验证清单

### 正常启动日志应该包含：
```
✓ PostHog setup started
✓ Event queue initialized
✓ Super properties manager initialized
✓ Session manager initialized
✓ API client initialized
✓ Distinct ID: timestamp-xxx
✓ Feature flags loaded
✓ Auto flush timer started
✓ Lifecycle observer started
✓ Error handlers installed
```

### 事件发送日志应该包含：
```
📤 beforeSend: button_clicked
✓ Event queued: button_clicked
✓ Batch sent (5 events)
✓ Response: 200 OK
```

### 错误日志（如果出现问题）：
```
❌ API Error: 401 Unauthorized
❌ Network error: Failed host lookup
⚠️ Event dropped by beforeSend
```

---

## 常见问题排查

### 问题 1：事件未出现在 Dashboard

**检查清单：**
1. API Key 是否正确？
2. 网络连接是否正常？
3. 日志是否显示发送成功？
4. Dashboard 中项目是否正确？

**解决方案：**
```dart
// 启用详细调试
await Posthog().setup(
  PostHogConfig(
    apiKey: 'YOUR_KEY',
    debug: true, // 确保这是 true
  ),
);

// 手动刷新队列
await Posthog().flush();
```

---

### 问题 2：功能标志加载失败

**检查清单：**
1. PostHog Dashboard 中是否创建了功能标志？
2. 用户是否已识别（identified）？
3. 网络请求是否成功？

**解决方案：**
```dart
// 1. 先识别用户
await Posthog().identify(userId: 'test-user');

// 2. 重新加载功能标志
await Posthog().reloadFeatureFlags();

// 3. 等待回调
PostHogConfig(
  onFeatureFlags: () {
    print('Feature flags loaded!');
  },
)
```

---

### 问题 3：异常未被捕获

**检查清单：**
1. 错误追踪配置是否启用？
2. 异常是否在应用内代码中？

**解决方案：**
```dart
errorTrackingConfig: PostHogErrorTrackingConfig(
  captureFlutterErrors: true,      // ✓ 启用
  capturePlatformDispatcherErrors: true,  // ✓ 启用
  captureIsolateErrors: true,      // ✓ 启用
  inAppIncludes: ['com.example'],  // ✓ 配置你的包名
),
```

---

### 问题 4：超级属性未生效

**检查清单：**
1. 属性是否正确注册？
2. 是否被后续的 register 覆盖？

**解决方案：**
```dart
// 使用 registerOnce 确保不被覆盖
await Posthog().registerOnce('first_open', DateTime.now().toString());

// 验证属性是否注册
final prefs = await SharedPreferences.getInstance();
final superProps = prefs.getString('posthog_super_properties');
print('Super properties: $superProps');
```

---

## 性能验证

### 内存使用
```bash
# 在 DevEco Studio 中使用 Profiler
# 观察：
# - 内存使用是否稳定
# - 没有内存泄漏
# - 队列大小合理（< 1000）
```

### 网络请求
```bash
# 查看网络请求频率
# 应该：
# - 批量发送，而非逐个发送
# - 有合理的节流（至少 1 秒间隔）
# - 离线时队列持久化
```

---

## 自动化测试

如果需要自动化测试，可以使用：

```dart
// test/integration_test/posthog_harmonyos_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PostHog 鸿蒙平台集成测试', (WidgetTester tester) async {
    // 1. 启动应用
    await tester.pumpWidget(MyApp());

    // 2. 等待 PostHog 初始化
    await tester.pumpAndSettle();

    // 3. 测试事件捕获
    await tester.tap(find.text('捕获简单事件'));
    await tester.pumpAndSettle();

    // 4. 验证日志或状态
    expect(find.text('成功'), findsOneWidget);

    // 5. 更多测试...
  });
}
```

运行：
```bash
flutter test integration_test/posthog_harmonyos_test.dart
```

---

## 总结

### 核心验证点
- ✅ 事件正确发送到 PostHog
- ✅ Dashboard 能实时看到数据
- ✅ 用户识别正确
- ✅ 功能标志正常工作
- ✅ 异常被正确捕获
- ✅ 超级属性正确附加
- ✅ SDK 控制功能正常

### 验证完成标准
1. 所有测试按钮点击后状态显示"成功"
2. 日志无错误信息
3. PostHog Dashboard 能看到所有事件和用户
4. 应用性能正常，无卡顿或崩溃

### 下一步
验证通过后，你可以：
1. 集成到你的实际应用
2. 配置生产环境参数
3. 设置更多自定义配置
4. 开始收集用户数据！
