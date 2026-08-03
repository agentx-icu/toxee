[English](./E2E_TESTING.md)

# toxee 端到端测试策略

>
> 生成于 2026-05-20。兄弟文档：`HYBRID_ARCHITECTURE.md`、`MAINTAINER_ARCHITECTURE.md`，以及协议层测试套件 `third_party/tim2tox/auto_tests/README.md`。
>
> 另见：[`TESTING_OVERVIEW.md`](TESTING_OVERVIEW.md) — toxee 所有测试资产的一站式地图（清单、执行类分类法、便宜→昂贵的运行顺序、CI 状态）。

## 一、执行摘要

**结论：采用官方 Flutter `integration_test` 作为主 E2E 层，将 Patrol 作为移动端原生交互场景的备选。**

`integration_test` 是唯一一个可以覆盖**全部五个**目标平台（macOS、Linux、Windows、iOS、Android），在测试时**真正加载 `libtim2tox_ffi`**（也就是当前应用赖以为生的二进制），并且无需改动现有 `bootstrap_deps.dart` + `build_all.sh` 流水线即可接入 CI 的候选。Patrol 仅在 `integration_test` 无法覆盖的一个能力上有意义——驱动原生系统对话框（相机/麦克风/通知权限、iOS 任务切换器、Android `WebView`），这是移动端唯一系统性缺口。我们明确**不**推荐 Maestro（不支持 Flutter 桌面）、Appium（重、双驱动分裂、传输已被弃用）、Detox（仅服务于 React Native）。

需要看清的关键事实：toxee 的多数"端到端"价值已经被 `third_party/tim2tox/auto_tests/`（145 个场景，虚拟时钟 + 本地 bootstrap + 真实 DHT 多档）在协议层覆盖。我们**真正缺**的是验证"Flutter UI 在每个平台上通过混合 `Tim2ToxSdkPlatform` + 二进制替换路径正确驱动协议层"。这道缺口靠 `integration_test` 补齐，并不需要更花哨的工具。

## 二、现有覆盖（避免重复）

任何新层落地前，先认清这些已存在的内容。和下表重叠的工具引入即浪费。

| 层 | 工具 | 范围 | 位置 |
|---|---|---|---|
| 静态检查 | `flutter analyze`（strict lints） | `lib/`、`tool/` | `.github/workflows/analyze.yml` |
| 复杂度护栏 | `tool/check_complexity.dart` | `lib/**.dart` 超 500 行 | 同一 workflow |
| 单元 + Widget | `flutter test`（71 文件） | Dart 逻辑、providers、单页 widget 树 | `test/` |
| **协议 E2E** | tim2tox `auto_tests/`（145 场景，虚拟 + 实时 + DHT） | TIM/UIKit API 同时跑 Platform + 二进制替换两条路径 | `third_party/tim2tox/auto_tests/` |
| 全量重新引导 | `bootstrap_fresh.yml` | 干净 clone 跑 `dart run tool/bootstrap_deps.dart` | CI |
| 子模块远端校验 | `submodule_verify.yml` | 子模块 SHA 已推送 | CI |
| 打包构建 | `build-packages.yml` | 每个目标平台 `flutter build` 通过 | CI |

明显缺失的是：**真正构建出来的应用上跑 UI 驱动的端到端**：登录 → 首页 → 会话 → 发送消息 → 收消息 → 发起通话。这一切都未在真实原生栈上验证过 `lib/ui/**`。本计划针对的正是这一缺口。

## 三、候选方案盘点

### 评分表

打分 0-5，权重按 toxee 自身需求（混合 FFI、五个平台、GitHub 托管 CI、双节点流程）调整。

| 候选 | 移动 (iOS/Android) | 桌面 (mac/lin/win) | FFI 安全 | 多节点支持 | CI 成本 | 维护性 | 是否填补缺口 | 总分 |
|---|---|---|---|---|---|---|---|---|
| **`integration_test`（官方）** | 5 / 5 | 5 / 5 / 5 | 是，加载真实二进制 | 是（在 host 上跑两个进程 + 独立数据目录） | 低（Ubuntu 即可，mac 贵 10 倍） | 低 | 高 | **5** |
| **Patrol 4.5** | 5 / 5 | 4 / 0 / 0 | 是（封装 integration_test） | 是（同上） | 中 | 中 | 仅移动原生缺口 | **3.5** |
| **Maestro** | 5 / 5 | 0 / 0 / 0 | 是（黑盒） | 是（两次安装） | 低/中 | 低（YAML） | 仅移动缺口 | **2** |
| Appium + Flutter Driver | 4 / 4 | 3 / 2 / 2 | 是 | 是 | 高（Appium server） | 高（双驱动、弃用动荡） | 与官方重叠 | 1.5 |
| Appium-Flutter-Integration-Driver | 4 / 4 | 3（仅 macOS）/ 0 / 0 | 是 | 是 | 高 | 中（小社区，v2.0.3） | 与官方重叠 | 1.5 |
| XCUITest / swift-testing | 3 / 0 | 3 / 0 / 0 | 是 | 难（无 Dart 钩子） | 中 | 高（Swift 胶水） | 部分 | 1 |
| Espresso / UIAutomator | 0 / 3 | 0 / 0 / 0 | 是 | 难 | 中 | 高（Kotlin 胶水） | 部分 | 1 |
| Sikuli / 图像匹配 | 2 / 2 | 2 / 2 / 2 | 是 | 是 | 中 | 极高（图像脆弱） | 部分 | 0.5 |
| Detox | 0 / 0 | 0 / 0 / 0 | 否（仅 RN） | 不适用 | 不适用 | 不适用 | 无 | 0 |

依据：Patrol 在 pub.dev 上的平台 tag 仅列出 Android、iOS、macOS、web（缺 Linux/Windows）；Maestro 官方文档明确写"Maestro does not yet support Flutter for Desktop"；appium-flutter-driver 上游确认 `flutter_driver` 正走向弃用，集成驱动 fork（v2.0.3，2025 年 10 月）只在桌面侧加入 macOS；Detox 硬绑 React Native JS bridge。详见 [文末来源](#来源)。

### 各平台可行性

| 工具 × 平台 | macOS | Linux | Windows | iOS | Android |
|---|---|---|---|---|---|
| `integration_test`（官方） | 可，`flutter test integration_test -d macos` | CI 需 `xvfb-run` | 可，`-d windows` | macos-14 模拟器；真机走 Xcode Cloud | 模拟器（GH 慢）或 Firebase Test Lab |
| Patrol | macOS 原生对话框可用 | 不支持 | 不支持 | 完整支持 | 完整支持 |
| Maestro | 不支持 | 不支持 | 不支持 | 完整支持 | 完整支持 |
| Appium-Flutter-Driver | 通过 flutter-integration-driver 仅 macOS | 否 | 否 | 完整支持 | 完整支持 |
| Detox | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 |

含义：**只有官方 `integration_test` 一个工具同时覆盖 toxee 所有目标平台**。其余方案都意味着工具拼接。

## 四、多节点测试策略

toxee 的核心面向用户的能力——加好友、聊天、通话——都需要**两个 Tox 节点对话**。共有四种正当的搭建方式，但其中并非每一种都适合 CI。

| 策略 | 实现 | CI 延迟 | 确定性 | toxee E2E 适配性 |
|---|---|---|---|---|
| **双进程（推荐）** | 同一台机器跑两个 `flutter test integration_test` 进程，分别把 `HOME` / `XDG_DATA_HOME` / `%APPDATA%` 指向独立目录，通过本地 bootstrap 互联（不走 DHT） | 秒级 | 高 | **主选** —— 与 `auto_tests/` 思路一致，无需公网 |
| 虚拟时钟 | `auto_tests/` 已在用的 `*_virtual_test.dart` 模式，时间通过代码推进 | 亚秒级 | 极高 | **协议层已在用**；**不**适合 UI E2E，Flutter 帧调度不遵循虚拟时钟 |
| 本地 bootstrap | 在 `127.0.0.1` 跑一个 Tox bootstrap 节点，两端都指向它，沿用 `auto_tests/` 的做法 | 秒级 | 高 | 与上面"双进程"策略一同打包 |
| 真实 DHT | 通过公网 DHT 寻址，让节点在互联网上互相发现 | 几十秒、抖动大 | 低 | **PR CI 避免使用**；仅在夜间 / 发布前档（参考 `auto_tests_nightly.yml`）跑一两个金丝雀场景 |

具体推荐：**PR 档 = 双进程 + 本地 bootstrap**，配合一个**真实 DHT 夜间档（参照 `auto_tests_nightly.yml` 的节奏）**，仅跑一两个金丝雀场景。

## 五、推荐方案

**主：官方 `integration_test`**（`package:integration_test` + `flutter test integration_test`）。

- 一个工具覆盖五个平台。
- 真正运行 `./build_all.sh` 产出的 `libtim2tox_ffi`。现有 bootstrap（`tool/bootstrap_deps.dart`）已经处理好 vendored SDK + 补丁，无需新增安装步骤。
- 与 `flutter_test` 的 matcher 兼容，现有 `test/` 风格可平移。
- 双进程模式：在 host 端启动两个 `integration_test` 进程，分别使用独立数据目录，通过一个进程内 bootstrap 节点配对，地址惯例参照 `auto_tests/`（`127.0.0.1:33445`）。
- CI：Linux 用 ubuntu-24.04 + `xvfb-run`、macOS / iOS 用 macos-14、Windows 用 windows-latest，整体通过新的 `ci:e2e` 标签或独立 workflow 门控，避免拖慢 PR。

**备选（仅移动端）：Patrol 4.5**。

- **仅用于**必须驱动原生系统对话框的场景（通话麦克风权限、QR 配对相机权限、通知权限、iOS PIP）。`lib/call/permission_helper.dart` 涉及的 `permission_handler` 流程是明显目标。
- 把 Patrol 限制在一个子目录（`integration_test/native/`），不让它变成默认。`patrol_cli` 比 `flutter test` 更重更慢。
- **不**投入 Patrol 桌面：Linux/Windows 不在 pub.dev 平台 tag 内，单独覆盖 macOS 与上文 `integration_test` 重复，没有增量价值。

不选其它候选的一句话理由：

- **Maestro**：完全不支持 Flutter 桌面，会让移动（Maestro）和桌面（integration_test）方案分裂。
- **Appium-Flutter-Driver**：绑定的是已被弃用的 `flutter_driver`。新的 `appium-flutter-integration-driver` 是半成品 fork（v2.0.3、约 50 stars、桌面端仅 mac），相对直接跑 `flutter test integration_test` 没有任何优势。
- **XCUITest / Espresso**：迫使我们同时维护 Swift + Kotlin 的测试源，去做 Dart 一样表达的行为。要读 `libtim2tox_ffi` 状态又必须再过一遍平台通道或屏幕扫描，两者都是摩擦。
- **Detox**：仅服务 React Native；源码层面硬绑 JS bridge。
- **Sikuli / 图像匹配**：UIKit fork 任何一格像素变动都会让全部截图失效，维护成本远高于收益。

## 六、三步增量落地

下文步骤刻意收得很窄，每一步独立可以 PR；后续步骤不依赖更前面任何步骤未完成的部分。

### 第 1 步 —— 本地冒烟（暂不入 CI）

加入 `integration_test` 作为 dev dep、一个 happy-path 冒烟、一段运行脚本。先只在 macOS——日常开发的默认环境（详见 `CLAUDE.md`）。

```bash
# pubspec.yaml 的 dev_dependencies 增加
#   integration_test:
#     sdk: flutter
flutter pub get

mkdir -p integration_test
# 编写 integration_test/smoke_login_to_home_test.dart：
# 初始化测试 profile → pump 应用 → 期望出现登录 / 自动登录 → 首页渲染完成 →
# 通过本地 bootstrap 给一个同机的第二节点发送一条 C2C 消息。

# 本地运行脚本
./tool/run_e2e_macos.sh    # 新增：封装 `flutter test integration_test -d macos`
```

通过门槛：维护者的 macOS 本机跑绿。本步不动 CI。这一步真正要验证的是 FFI 库在 `integration_test` 下能被加载，以及测试驱动下 `Tim2ToxSdkPlatform` 正确装上——这两点并非天然成立，因为 `lib/bootstrap/logging_bootstrap.dart` 里有二进制替换的特殊处理。

### 第 2 步 —— CI 档，标签触发

新增 `.github/workflows/e2e.yml`，运行第 1 步的 macOS 冒烟 + 一个 Linux `xvfb-run` 冒烟。用 PR 标签门控，避免在每个 PR 上额外开销。

```yaml
# .github/workflows/e2e.yml（草图）
on:
  pull_request:
    types: [labeled, synchronize]
jobs:
  e2e-macos:
    if: contains(github.event.pull_request.labels.*.name, 'ci:e2e')
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
        with: { submodules: recursive }
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.41.9', channel: 'stable' }
      - run: dart run tool/bootstrap_deps.dart
      - run: flutter pub get
      - run: ./build_all.sh --platform macos --mode debug
      - run: flutter test integration_test -d macos
  e2e-linux:
    if: contains(github.event.pull_request.labels.*.name, 'ci:e2e')
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
        with: { submodules: recursive }
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.41.9', channel: 'stable' }
      - run: sudo apt-get update && sudo apt-get install -y xvfb libsodium-dev libopus-dev libvpx-dev libsqlite3-dev ninja-build libgtk-3-dev
      - run: dart run tool/bootstrap_deps.dart
      - run: flutter pub get
      - run: ./build_all.sh --platform linux --mode debug
      - run: xvfb-run -a flutter test integration_test -d linux
```

当套件稳定后，再在 `CODEOWNERS` 增加 `ci:e2e-required` 规则。在此之前保持咨询性质。

### 第 3 步 —— 移动 + 多节点扩展

加入 iOS 模拟器（macos-14）和 Android 模拟器（`reactivecircus/android-emulator-runner@v2`）任务，引入双进程 harness 和 Patrol 权限对话框子套件。

```bash
# 3a. 在 macOS / Linux 上的双进程 harness
./tool/run_e2e_pair.sh     # 新增：拉起两个 flutter test 进程
                           # TOXEE_DATA_DIR=$tmp/{alice,bob}，
                           # 通过进程内本地 bootstrap 节点配对。

# 3b. 引入 Patrol，处理移动端原生权限对话框
# pubspec.yaml: dev_deps 增加 patrol: ^4.5.0
dart pub global activate patrol_cli
mkdir -p integration_test/native
# 编写 integration_test/native/permissions_test.dart：
# 在通话流程外围调用 patrolTester.native2.{grantPermissionWhenInUse,
# grantNotificationsPermission}。

patrol test --target integration_test/native/permissions_test.dart -d <device>

# 3c. 仿照 auto_tests_nightly.yml 的节奏跑真实 DHT 金丝雀夜间档
# .github/workflows/e2e_nightly.yml —— schedule: cron '0 3 * * *'，
# 一个场景、3 次重试以容忍偶发抖动，连续失败时发 issue / Slack。
```

通过门槛：macOS + Linux 在 PR 档保持绿色；iOS 模拟器进慢档（3a/3b 可放在 `ci:e2e-mobile` 标签下）；真实 DHT 夜间档作为咨询信号。Windows 与 macOS/Linux 共用 `ci:e2e` 标签，但视为尽力支持：Windows runner 是三者中最慢，也是抖动风险最高的一个。

## 七、待解问题与风险

1. **Windows runner 稳定性**。我们目前没有生产数据证明 `flutter test integration_test -d windows` 在 GH Actions 上能稳跑 `libtim2tox_ffi.dll`。第 2 步上线后即可观察。如果不行，就降级为"Windows 仅参与构建，E2E 跑在 macOS/Linux 上"。
2. **GH 上的 Android 模拟器**。Patrol 自家文档都警告 GH Android 模拟器"启动慢、不稳定"。本计划接受这一限制，把 Android E2E 推到 `ci:e2e-mobile` 标签触发档和夜间档；如果未来预算允许，日常信号建议外接 Firebase Test Lab。
3. **iOS 真机覆盖**。macos-14 模拟器足够 UI 流程，但无法验证真正的后台行为（即 `doc/architecture/MOBILE_BACKGROUND.md` 描述的领域）。要测真后台只能靠真机 XCUITest，本计划 v1 不包含；如果"后台来电"成为主导问题再考虑。
4. **单例流程下的测试隔离**。`CLAUDE.md` 指出 toxee 使用 Tim2Tox 默认的单例模式。双进程方案通过运行**两个 OS 进程**而非一个进程内两实例来绕开这一约束。任何想偷懒在一个进程里复用两个 peer 的做法都会撞上 `ToxManager not initialized` 之类的错。务必在 harness 脚本注释里大声标明这一约定。
5. **Patrol 在 macOS 桌面**。Patrol 的 pub.dev tag 写了 macOS，但调研期间没有发现一个与 toxee 同形态的开源项目在 CI 上跑 Patrol-macOS。视为未经验证；只要桌面没有需要自动化原生对话框的需求，桌面端就只用官方 `integration_test`。
6. **与 `auto_tests/` 的覆盖重叠**。我们落定一条边界：`auto_tests/` 证明**协议**正确，新 E2E 层证明**UI** 正确驱动协议。任何能用"两个 TIM SDK 对话"表达的场景就该在 `auto_tests/`，不该出现在这里。
7. **Flutter 版本钉死**。本计划沿用 `analyze.yml` 里 3.41.9 stable 的钉法。Patrol 4.5 支持当前 stable Flutter，安装时复核即可。如果未来 Patrol 要求高于 CI 的 Flutter 版本，宁可把 Patrol 降级为"本地可选工具"，也不为单一工具而升级 CI。

## 来源

- [Patrol 在 pub.dev](https://pub.dev/packages/patrol) —— 平台 tag（Android、iOS、macOS、web）与当前版本 4.5.0。
- [Patrol CI 平台文档](https://patrol.leancode.co/ci/platforms) —— GH Actions Android 警告、macOS 分钟数比例。
- [Maestro 关于 Flutter 平台支持的文档](https://docs.maestro.dev/get-started/supported-platform/flutter) —— 明示"Maestro does not yet support Flutter for Desktop"。
- [appium-flutter-driver issue #210](https://github.com/appium/appium-flutter-driver/issues/210) —— `flutter_driver` 弃用进展。
- [appium-flutter-integration-driver](https://github.com/AppiumTestDistribution/appium-flutter-integration-driver) —— v2.0.3、2025 年 10 月、桌面端仅 macOS。
- [Maestro 关于 Detox 替代品的总结](https://maestro.dev/insights/detox-alternatives) —— 确认 Detox 仅服务 React Native JS bridge。
- [Flutter 官方集成测试文档](https://docs.flutter.dev/testing/integration-tests) —— Linux 需 xvfb、`-d macos|linux|windows`。
- 仓内：`CLAUDE.md`、`doc/architecture/HYBRID_ARCHITECTURE.md`、`third_party/tim2tox/auto_tests/README.md`（2026-05-20 核对）。
