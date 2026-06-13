# 测试总览 — toxee

> 语言 / Language: [中文](TESTING_OVERVIEW.md) | [English](TESTING_OVERVIEW.en.md)
>
> toxee 所有测试资产的一站式地图：有哪些、如何分类、从最便宜到最昂贵的运行顺序，
> 以及哪些跑在 CI、哪些只在本地。权威的重组计划见
> [`doc/research/TEST_CASE_ORGANIZATION_PLAN.en.md`](../research/TEST_CASE_ORGANIZATION_PLAN.en.md)；
> 本文是其 §1、§2、§3.5 面向人和 agent 的摘要。
>
> 范围：**仅 toxee 测试资产**。协议层套件 `third_party/tim2tox/auto_tests/`
> 保留自己的阶段清单（`run_tests_ordered.sh`）和 CI 分档，本文只引用、不重组。

## 一、清单（当前现状）

| # | 面 | 位置 | 数量 | 运行方式 | 是否在 CI？ |
|---|----|------|------|----------|-------------|
| 1 | 单元 + Widget 测试（L1） | `test/`（不含 `test/mcp/`） | 122 文件（87 已跟踪，35 新增；忽略垃圾文件已排除） | `flutter test` | analyze.yml，每个 PR |
| 2 | 真实 UI 的 WidgetTester 门禁（L1） | `test/ui/chat_core_real_ui_test.dart` | 6 个门禁 | `flutter test` | analyze.yml |
| 3 | Anchor/key 源码测试（L1） | `test/ui/testing/`、`test/ui/contact/`… | 17 文件（anchor/key/L3-debug） | `flutter test` | analyze.yml |
| 4 | host-bundle 生命周期（L2） | `integration_test/` | 6 个 Dart 文件（5 个可运行 `_test.dart`，打 `needs-native` tag + 1 个 harness） | 逐文件 `flutter test -d <os>` | e2e.yml，按需 `ci:e2e` |
| 5 | L3 runner 门禁（数据层） | `tool/mcp_test/scenarios/*.json` | 46（40 blocking，6 nonBlocking） | `run_l3_scenarios.dart` 对接活跃 debug 应用 | 否（本地） |
| 6 | 双进程 Fixture C / unified runner | `tool/mcp_test/fixture_c_unified_runner.dart`、`fixture_c_manifest.json`、`drive_fixture_c_*.dart` + legacy `.sh` | 1 个统一 runner / 27 个 Dart 驱动 / 28 个 legacy shell 包装 | `dart run tool/mcp_test/fixture_c_unified_runner.dart ...`（legacy shell 入口委托它） | 否（本地）；契约经 mcp_harness_smoke.yml |
| 7 | 双进程真实 UI 场景 | `tool/mcp_test/drive_real_ui_pair.dart`（由 unified runner 通过 manifest 规划） | 8 个固化场景 + 88 项可复用 campaign 目录（握手 / 握手详情 / 拒绝 / 消息 / 消息突发 / 自定义申请词 / 语音通话 / 拒接通话） | `fixture_c_unified_runner.dart --class=2proc-ui [--real-ui-scenario=<name> \| --real-ui-campaign=<name>]` 或直接 driver + osascript | 否（本地，macOS） |
| 8 | 单实例 UI 脚本驱动 | `tool/mcp_test/drive_export_account.dart` | 1 | 脚本 | 否（本地） |
| 9 | Harness 自检 | `fixture_c_helpers_regression.sh`、`fixture_c_unified_runner_regression.sh`、`echo_peer_{contract_smoke,drift_check,helpers_regression}.sh` | 5 个脚本 | 逐脚本 | `fixture_c_helpers_regression.sh` 在 mcp_harness_smoke.yml；其余本地 |
| 10 | L3 playbook（规格） | `test/mcp/S*.md` | 118（S1–S125，有空缺） | agent 驱动 | 不适用（规格） |
| 11 | 协议分档（超出范围） | `third_party/tim2tox/auto_tests` | 14 阶段 | `run_tests_ordered.sh` | auto_tests*.yml 第 1–4 档 |

## 二、规范分类法：两条正交轴

每个可执行测试资产都放在**两条**独立的轴上。不要把它们合并——测试的依赖层级
和它的执行成本是两个不同的问题。

### 轴 1 — 依赖层级（L1 / L2 / L3）

既有且权威的模型见
[`doc/architecture/UI_TEST_LAYERING.en.md`](UI_TEST_LAYERING.en.md)：
**能表达这个测试的最低层级胜出。**

- **L1** — 纯 Dart + mock channel + 一个构造函数接缝。`test/`。
- **L2** — 真实 Hive 引导、真实 `libtim2tox_ffi`、真实 `path_provider`，
  但**无**实时网络。`integration_test/`（tag `needs-native`）。
- **L3** — 实时 Tox DHT、两个 toxee 进程、原生文件选择器、麦克风/相机权限。
  `tool/mcp_test/` 下的 MCP/L3 harness。

### 轴 2 — 执行类（机器可读）

轴 2 是重组计划新增的：每个可执行产物**恰好一个**执行类，由声明的标志位
推导得出，而不是在某张中心表里手工维护。

| 类 | 含义 | 当前成员 |
|----|------|----------|
| `ci-hermetic` | `flutter test`，无原生库，每个 PR | `test/` 全部，含真实 UI 的 WidgetTester + anchor 测试 |
| `ci-host-bundle` | 真实宿主二进制 + `libtim2tox_ffi`，按需 label | `integration_test/`（6） |
| `harness-contract` | harness 自身的 hermetic 契约检查；子字段 `ci: true\|false` | `fixture_c_helpers_regression.sh`（ci: true）；`echo_peer_contract_smoke.sh`、`echo_peer_drift_check.sh`、`echo_peer_helpers_regression.sh`（ci: false） |
| `l3-gate` | 单实例、活跃应用、`l3_*` 调试工具、无 peer | 35 个场景 JSON |
| `l3-gate-echo` | 单实例 + echo peer（实时 DHT） | 7 个场景 JSON（`requiresEchoPeer`） |
| `l3-ui-single` | 单实例，驱动真实 widget（marionette/skill 点击或脚本） | 4 个 `l3_settings_*_tap` JSON（nonBlocking）+ `drive_export_account.dart` + S96–S125 战役 playbook |
| `2proc-l3` | 两个 toxee 进程，经 unified runner 规划、由 `l3_*` 工具驱动 | manifest 中全部 data-layer Fixture C 项（legacy `run_fixture_c_*.sh` 兼容入口最终委托 unified runner） |
| `2proc-ui` | 两个 toxee 进程，真实 widget + osascript | manifest 中的 `drive_real_ui_pair.dart` 场景与命名 campaign（经 unified runner 参与同一 planning / dry-run 体系） |
| `manual-playbook` | 钉在 L3、仅 agent 驱动（OS 对话框、媒体硬件、kill+重启） | 其余 `S*.md` |

（35 + 7 + 4 = 46 个场景 JSON。类由 JSON 标志位推导，故此名册再不需手工清点。）

映射到常被问起的几个类别：

- **CI** = `ci-*` 几个类。
- **单实例 real UI** = `l3-ui-single`，外加真实 UI 的 WidgetTester 门禁
  （它们是 CI *内部*的真实 UI）。
- **双进程 real UI** = `2proc-ui`。
- 数据层 harness 类（`l3-gate*`、`2proc-l3`）刻意保持独立，因为它们有意绕过 widget。

测试资产的类**在资产所在处声明**（JSON 字段、脚本头、playbook 头），
并**由生成器聚合**，再不在某张中心表里手工维护。

双进程入口现在统一到
`dart run tool/mcp_test/fixture_c_unified_runner.dart`。它读取同一个
`fixture_c_manifest.json` 来规划 `2proc-l3` 和 `2proc-ui`；legacy shell
入口（如 `run_fixture_c_non_media.sh`、`run_fixture_c_suite.sh`）只保留兼容壳层，
参数归一后委托给这个 Dart runner。因而 `2proc-ui` 不再在 planning 阶段被
NOTE-skip，`--plan-json` / `--dry-run` 也会展开 real-UI 场景；需要已有好友关系的
`message` 子场景则可以作为“已接受握手之后”的链式步骤来规划，而不是要求手工拆成
两次运行。`--plan-json` 里现在还会显式带出 `realUiScenarios` 和 `commands`，
因此“哪些 real-UI 场景能复用同一次启动”已经是 hermetic 可回归的契约，而不只是
live 观察结论。

对 `2proc-ui` 而言，契约是“能复用就复用”，而不是“每个场景都 fresh launch 一次”。
默认批次会尽量保留已经准备好的账号与联系人状态，因为 `message` 与 `call_voice`
都依赖已有好友关系。当前完整的默认批次会以一次 stateful launch 执行，中间按需
插入内部的 friendship reset，再继续跑下一个不兼容的好友请求分支；若只重放
`message` 或 `call_voice` 这类依赖已有好友关系的场景，则会通过
`paired_for_e2e` restore 自动补足前置状态。
当前可 discover 的 catalog 共有 88 个内建 campaign。`--list-real-ui-campaigns`
是唯一精确来源；文档只记录调度语义和推荐运行策略，避免再次手工维护完整清单。
当前 bucket：

- `rui-optimized-*`：首选的广覆盖真实 App bundle，目标是在一次 app pair 启动里复用
  已登录账号、好友关系和已打开页面，尽量覆盖更多真实控件。优先运行
  `rui-optimized-current`；需要聚焦时再选 `rui-c2c-optimized`、
  `rui-friendship-optimized`、`rui-single-app-optimized`。新增的
  `rui-c2c-deep-extra` / `rui-account-deep-extra` /
  `rui-group-conf-deep-extra` 已并入对应 optimized 链；native/移动端边界走独立
  `rui-native-boundary-guards`，其中附件/restore 已有 debug-only 固定路径 seam，
  OS/network/permission/mobile seam 仍可能是设计性 SKIP。
- `rui-*` domain sweep：按产品域拆分的真实控件用例，覆盖 settings/profile/login、
  contacts/conversation/chat/call、group/conference、账号管理、成员角色管理/移除、
  C2C 补充等。用于定位回归或补跑某个域。
- `accepted-friend-*`：在已接受好友关系后继续叠加聊天/通话/group 步骤。
- `fresh-*` / `no-friend-*` / `*-then-decline`：从无好友关系起步，或中途切回无好友分支；
  planner 会插入 `reset_friendship` 维护步，而不是默认强制 relaunch。
- `all-*`：保留的代表性端到端 smoke 调度形态。

这些 bucket 名称描述的是 planner / dry-run 的调度语义，不是“每个分支都已 live 验证完成”
的声明。live 端仍是本地 dogfood 门禁，不要把它提前解读成 CI 级稳定性承诺。

## 三、推荐战役顺序（便宜 → 昂贵）

按此顺序运行各套件；每一步都严格比下一步更便宜更快，因此失败会先以最低成本暴露。
每一步都能独立 exit 0——`--class` 选择器保证未被选中的分区不会产生虚假的
SKIP-exit-2。

| # | 步骤 | 类 | 入口命令 |
|---|------|----|----------|
| 1 | 单元 + Widget | `ci-hermetic` | `flutter test` |
| 2 | host-bundle 生命周期（若已构建原生库） | `ci-host-bundle` | `flutter test integration_test/` |
| 3 | L3 hermetic 套件 | `l3-gate` | `dart run tool/mcp_test/run_l3_scenarios.dart <ws_uri> --class=l3-gate` |
| 4 | L3 echo 套件 | `l3-gate-echo` | `dart run tool/mcp_test/run_l3_scenarios.dart <ws_uri> --class=l3-gate-echo --echo` |
| 5 | UI-tap 套件（nonBlocking） | `l3-ui-single` | `dart run tool/mcp_test/run_l3_scenarios.dart <ws_uri> --class=l3-ui-single --allow-skip` |
| 6 | Fixture C 非媒体统一战役 | `2proc-l3` + `2proc-ui` | `dart run tool/mcp_test/fixture_c_unified_runner.dart --tier=non-media` |
| 7 | Fixture C 媒体统一战役 | `2proc-l3` | `dart run tool/mcp_test/fixture_c_unified_runner.dart --tier=media` |
| 8 | 聚焦/优化双进程真实 UI（优先复用启动） | `2proc-ui` | `dart run tool/mcp_test/fixture_c_unified_runner.dart --class=2proc-ui --real-ui-campaign=rui-optimized-current` |
| 9 | 手动 playbook | `manual-playbook` | agent 驱动，仅用于上述都无法表达的流程（`test/mcp/S*.md`） |

说明：

- `<ws_uri>` 是活跃 debug 应用的 VM-service WebSocket URI，以 `/ws` 结尾
  （例如 `ws://127.0.0.1:8181/abcd=/ws`）。先启动应用；MCP/L3 playbook
  记录了 no-DDS 启动器以及如何读取该 URI。
- 第 3–8 步需要一个**正在运行**的桌面 debug 构建；它们不是 hermetic。
  第 1–2 步是 hermetic。
- 兼容入口仍保留：`run_fixture_c_non_media.sh`、`run_fixture_c_suite.sh`
  等 legacy shell 入口只做参数翻译 / 委托，不再各自维护规划逻辑。
- `fixture_c_unified_runner.dart` 的 `--plan-json` / `--dry-run` 现在会把
  `2proc-ui` 一起规划出来；如果只想重放某个 real-UI 场景，可用
  `--class=2proc-ui --real-ui-scenario=<name>`；具体名称以
  `drive_real_ui_pair.dart` 注册表和 `--list-real-ui-campaigns` 展开的 driver 名称为准。
  对依赖好友/账号/会议状态的场景，planner 仍会通过链式复用、restore 或显式维护步满足
  前置条件，而不是假定一个裸 fresh pair。
- 如果想直接选一个已合并好的 real-UI 批次，可用
  `--class=2proc-ui --real-ui-campaign=<name>`；完整目录可通过
  `--list-real-ui-campaigns` 打印。广覆盖本地 dogfood 默认先跑
  `rui-optimized-current`，再按失败域补跑 `rui-c2c-optimized`、
  `rui-friendship-optimized`、`rui-single-app-optimized`、新增 deep-extra
  domain sweep 或具体 `rui-*` domain sweep。这些名称描述的是调度形态，不是 CI 级
  live 覆盖承诺。
- 若只是做底层诊断，仍可直调 `drive_real_ui_pair.dart`；统一 runner 只是把它纳入同一
  manifest / 计划 / 过滤体系。
- 不要把外部脚本绑死在某个固定的 real-UI 启动次数上。只要场景顺序和前置条件正确，
  “更少 launch” 本身就是被鼓励的优化。
- 第 9 步是兜底：用于任何更便宜的类都确实无法表达的流程（OS 对话框、
  真实媒体硬件、kill 后重启）。

## 四、各类的 CI 状态

| 类 | 今日是否在 CI | 位置 |
|----|---------------|------|
| `ci-hermetic` | **是**，每个 PR | `analyze.yml`（`flutter test`） |
| `ci-host-bundle` | **按需**（label `ci:e2e`） | `e2e.yml` |
| `harness-contract`（ci: true） | **是**，hermetic | `mcp_harness_smoke.yml`（`fixture_c_helpers_regression.sh`） |
| `harness-contract`（ci: false） | 否（本地） | echo-peer 契约/漂移/回归脚本 |
| `l3-gate`、`l3-gate-echo`、`l3-ui-single` | **否**（本地门禁） | `run_l3_scenarios.dart` 对接活跃应用 |
| `2proc-l3`、`2proc-ui` | **否**（本地，macOS） | `fixture_c_unified_runner.dart`（必要时直调 `drive_real_ui_pair.dart`） |
| `manual-playbook` | 不适用（规格） | `test/mcp/S*.md` |

此外，`mcp_harness_smoke.yml` 跑 hermetic 的 harness 校验步骤（经 runner 的
`--validate-only` 做场景 JSON 的 schema/suite 校验，以及生成索引的
`--check` 不变量），因此即便活跃 L3 套件本身不在 CI 跑，harness 元数据也无法
悄悄漂移。

**为什么活跃类目前不在 CI。** 在 CI 跑 L3 hermetic 套件需要 macOS runner +
应用构建 + 已 seed 的账号——已解锁但昂贵。MCP 自动化成熟度结论（2026-06-01）
依然成立：活跃的 L3 / 双进程测试是**本地某一时刻的快照门禁**，还不是可信赖的
CI 回归门禁。把它升入 CI 的路径记录在
[`doc/research/UI_AUTOMATION_ROADMAP.en.md`](../research/UI_AUTOMATION_ROADMAP.en.md)。

## 五、移动端兼容（诚实的缺口）

分类法本身是平台中立的，且 **L1 widget 测试已覆盖移动端的输入/菜单变体**
（`..._input_mobile.dart` 以及移动端的通话/通知面——经 vendored UIKit fork）——
共享 Dart 的门禁在移动端 widget 树上同样运行。

诚实的缺口是**活跃实例类**（`l3-*`、`2proc-*`）：它们**目前仅限桌面宿主**。
它们经一个 VM-service URI 和 osascript 驱动真实桌面 debug 构建，这些在手机上
都不存在。移动端运行时自动化（在 iOS/Android 上驱动真实应用，含原生 OS 对话框）
是 **Patrol / E2E 路线图项**，不在当前 L3 harness 覆盖范围内。参见端到端策略
[`E2E_TESTING.md`](E2E_TESTING.md)（用 Patrol 处理移动端原生对话框）以及路线图
[`doc/research/UI_AUTOMATION_ROADMAP.en.md`](../research/UI_AUTOMATION_ROADMAP.en.md)。

## 六、接下来读什么

- [`UI_TEST_LAYERING.en.md`](UI_TEST_LAYERING.en.md) — L1/L2/L3 策略、晋升协议、
  状态向量。轴 1 的权威。
- [`MCP_UI_TEST_PLAYBOOK.en.md`](MCP_UI_TEST_PLAYBOOK.en.md) — L3 的 MCP 路由矩阵、
  no-DDS 启动器契约（如何拿到 `<ws_uri>`）、L3 场景目录。
- [`../../test/mcp/INDEX.en.md`](../../test/mcp/INDEX.en.md) — **生成的**覆盖索引：
  每个 S 编号一行，含层级、执行类、可执行产物、状态（由
  `gen_scenario_index.dart` 生成；其新鲜度由 `mcp_harness_smoke.yml` 的
  `--check` 在 CI 中把关）。
- [`E2E_TESTING.md`](E2E_TESTING.md) — 端到端策略与移动端原生对话框（Patrol）方案。
- [`doc/research/TEST_CASE_ORGANIZATION_PLAN.en.md`](../research/TEST_CASE_ORGANIZATION_PLAN.en.md)
  — 本总览所摘要的权威重组计划（schema、runner 排序、卫生、迁移步骤）。
