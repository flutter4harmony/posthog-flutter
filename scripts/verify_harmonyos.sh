#!/bin/bash

# PostHog 鸿蒙平台快速验证脚本
# 使用方法: ./scripts/verify_harmonyos.sh <API_KEY>

set -e

API_KEY="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}PostHog 鸿蒙平台验证脚本${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# 1. 检查环境
echo -e "${YELLOW}[1/6] 检查开发环境...${NC}"

# 检查 Flutter
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ Flutter 未安装${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Flutter: $(flutter --version | head -1)${NC}"

# 检查鸿蒙 SDK（如果有）
if command -v hdc &> /dev/null; then
    echo -e "${GREEN}✓ HarmonyOS SDK 已安装${NC}"
else
    echo -e "${YELLOW}⚠️  HarmonyOS SDK 未找到（可能未安装）${NC}"
fi

# 检查项目结构
if [ -d "$PROJECT_ROOT/ohos" ]; then
    echo -e "${GREEN}✓ 鸿蒙项目目录存在${NC}"
else
    echo -e "${RED}❌ 鸿蒙项目目录不存在${NC}"
    exit 1
fi

echo ""

# 2. 验证 API Key
echo -e "${YELLOW}[2/6] 验证 API Key...${NC}"

if [ -z "$API_KEY" ]; then
    echo -e "${RED}❌ 请提供 API Key${NC}"
    echo "使用方法: ./scripts/verify_harmonyos.sh <API_KEY>"
    echo ""
    echo "获取 API Key:"
    echo "1. 访问 https://app.posthog.com/"
    echo "2. 创建项目或进入现有项目"
    echo "3. 点击 Settings -> Project"
    echo "4. 复制 API Key"
    exit 1
fi

if [[ $API_KEY == phc_* ]]; then
    echo -e "${GREEN}✓ API Key 格式正确${NC}"
else
    echo -e "${YELLOW}⚠️  API Key 格式可能不正确（应以 phc_ 开头）${NC}"
fi

echo ""

# 3. 代码分析
echo -e "${YELLOW}[3/6] 运行代码分析...${NC}"

cd "$PROJECT_ROOT"

if flutter analyze --no-fatal-infos 2>&1 | grep -q "No issues found"; then
    echo -e "${GREEN}✓ 代码分析通过，无问题${NC}"
else
    echo -e "${RED}❌ 代码分析发现问题${NC}"
    flutter analyze
    exit 1
fi

echo ""

# 4. 运行测试
echo -e "${YELLOW}[4/6] 运行单元测试...${NC}"

if flutter test 2>&1 | grep -q "All tests passed"; then
    echo -e "${GREEN}✓ 所有测试通过${NC}"
else
    echo -e "${RED}❌ 部分测试失败${NC}"
    flutter test
    exit 1
fi

echo ""

# 5. 检查关键文件
echo -e "${YELLOW}[5/6] 检查关键文件...${NC}"

FILES=(
    "lib/src/posthog_flutter_harmonyos.dart"
    "ohos/entry/src/main/ets/plugin/PosthogFlutterPlugin.ets"
    "ohos/entry/src/main/ets/plugin/PosthogMethodCallHandler.ets"
    "lib/src/core/http/posthog_api_client.dart"
    "lib/src/core/storage/event_queue.dart"
)

MISSING=0
for file in "${FILES[@]}"; do
    if [ -f "$PROJECT_ROOT/$file" ]; then
        echo -e "${GREEN}✓ $file${NC}"
    else
        echo -e "${RED}✗ $file 缺失${NC}"
        MISSING=1
    fi
done

if [ $MISSING -eq 1 ]; then
    exit 1
fi

echo ""

# 6. 生成验证报告
echo -e "${YELLOW}[6/6] 生成验证报告...${NC}"

cat > "$PROJECT_ROOT/harmonyos_verification_report.txt" << EOF
PostHog 鸿蒙平台验证报告
生成时间: $(date)
API Key: ${API_KEY:0:20}...

## 环境信息
Flutter 版本: $(flutter --version | head -1)
Dart 版本: $(dart --version)
项目路径: $PROJECT_ROOT

## 代码质量
- 代码分析: ✓ 通过
- 单元测试: ✓ 通过
- 测试数量: $(flutter test 2>&1 | grep -o '[0-9]* tests passed' | head -1)

## 文件检查
$(for file in "${FILES[@]}"; do
    if [ -f "$PROJECT_ROOT/$file" ]; then
        echo "- ✓ $file"
    else
        echo "- ✗ $file (缺失)"
    fi
done)

## API 验证清单
请在鸿蒙设备/模拟器上验证以下功能：

### 核心功能
- [ ] 事件追踪 (capture)
- [ ] 用户识别 (identify)
- [ ] 屏幕浏览 (screen)
- [ ] 用户别名 (alias)
- [ ] 组事件 (group)

### 配置功能
- [ ] 超级属性 (register/unregister)
- [ ] SDK 控制 (enable/disable/optOut)
- [ ] 调试模式 (debug)

### 高级功能
- [ ] 功能标志 (getFeatureFlag/isFeatureEnabled)
- [ ] 异常捕获 (captureException)
- [ ] 会话管理 (getSessionId)
- [ ] 队列管理 (flush)

### 平台功能
- [ ] 应用生命周期事件
- [ ] 设备信息获取
- [ ] URL 打开
- [ ] Session Replay（框架）

## 下一步
1. 使用测试应用验证功能
2. 在 PostHog Dashboard 中查看数据
3. 参考验证指南: docs/HARMONYOS_VERIFICATION_GUIDE.md
EOF

echo -e "${GREEN}✓ 报告已生成: harmonyos_verification_report.txt${NC}"

echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${GREEN}✅ 验证完成！${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo "下一步："
echo "1. 查看验证报告: cat harmonyos_verification_report.txt"
echo "2. 使用测试应用: see example_harmonyos_test.dart"
echo "3. 阅读验证指南: docs/HARMONYOS_VERIFICATION_GUIDE.md"
echo ""
echo -e "${YELLOW}提示：在实际设备上验证以获得最佳结果${NC}"
