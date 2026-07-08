# toxee 文档
> 语言 / Language: [中文](README.md) | [English](README.en.md)

## 推荐阅读路径（按角色）

- **新用户（只想跑起来）**  
  [主 README](../README.zh-CN.md)「5 分钟理解」+「快速开始」→ 完整步骤见 [getting-started.md](getting-started.md)；若遇问题 → [operations/DEPENDENCY_BOOTSTRAP.md](operations/DEPENDENCY_BOOTSTRAP.md) → [TROUBLESHOOTING.md](TROUBLESHOOTING.md)。

- **接入方（集成 Tim2Tox 到自己的客户端）**  
  [主 README](../README.zh-CN.md)「与 Tim2Tox 的关系」→ [integration/INTEGRATION_GUIDE.md](integration/INTEGRATION_GUIDE.md) → [architecture/HYBRID_ARCHITECTURE.md](architecture/HYBRID_ARCHITECTURE.md) →（按需）[reference/CALLING_AND_EXTENSIONS.md](reference/CALLING_AND_EXTENSIONS.md)、[Tim2Tox 文档](https://github.com/agentx-icu/tim2tox)（[本地 doc](../third_party/tim2tox/doc/README.md)）的 INTEGRATION_OVERVIEW / API 等。

- **维护者（改代码、排错、发版）**  
  [主 README](../README.zh-CN.md)「当前架构概览」→ 本页维护入口 → [architecture/MAINTAINER_ARCHITECTURE.md](architecture/MAINTAINER_ARCHITECTURE.md) → [reference/IMPLEMENTATION_DETAILS.md](reference/IMPLEMENTATION_DETAILS.md)、[reference/ACCOUNT_AND_SESSION.md](reference/ACCOUNT_AND_SESSION.md) → 构建/排障时 [operations/BUILD_AND_DEPLOY.md](operations/BUILD_AND_DEPLOY.md)、[operations/DEPENDENCY_BOOTSTRAP.md](operations/DEPENDENCY_BOOTSTRAP.md)、[TROUBLESHOOTING.md](TROUBLESHOOTING.md)、[operations/PATCH_MAINTENANCE.md](operations/PATCH_MAINTENANCE.md)。

---

## 维护入口

- [architecture/MAINTAINER_ARCHITECTURE.md](architecture/MAINTAINER_ARCHITECTURE.md) - **维护者视角**：混合架构设计、双路径成因、模块职责、初始化时序、最容易改坏的地方、阅读顺序
- [architecture/ARCHITECTURE.md](architecture/ARCHITECTURE.md) - 客户端整体架构、核心组件和数据流
- [architecture/HYBRID_ARCHITECTURE.md](architecture/HYBRID_ARCHITECTURE.md) - 当前混合架构的职责与回调路径
- [reference/ACCOUNT_AND_SESSION.md](reference/ACCOUNT_AND_SESSION.md) - 账号初始化、切换、退出与删除的生命周期
- [reference/IMPLEMENTATION_DETAILS.md](reference/IMPLEMENTATION_DETAILS.md) - 关键模块与消息/事件处理实现细节
- [reviews/2026-05-26-core-feature-review.md](reviews/2026-05-26-core-feature-review.md) - 本轮核心功能 review、修复项、验证范围与限制

## 入门与操作

- [getting-started.md](getting-started.md) - 从克隆到跑起来的单页指引（首次运行推荐）
- [operations/BUILD_AND_DEPLOY.md](operations/BUILD_AND_DEPLOY.md) - 本地构建流程、安装包产物、GitHub Actions 打包与 Release 发布
- [operations/DEPENDENCY_BOOTSTRAP.md](operations/DEPENDENCY_BOOTSTRAP.md) - 从克隆到可构建的引导顺序与选项（首次克隆必看）
- [operations/DEPENDENCY_LAYOUT.md](operations/DEPENDENCY_LAYOUT.md) - third_party 目标结构、legacy 假设
- [operations/PATCH_MAINTENANCE.md](operations/PATCH_MAINTENANCE.md) - 补丁与依赖维护、SDK 升级检查清单
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - 构建、运行和调试中的常见问题

## 接入与功能专题

- [integration/INTEGRATION_GUIDE.md](integration/INTEGRATION_GUIDE.md) - 客户端接入 Tim2Tox 的最小实现与初始化流程
- [reference/CALLING_AND_EXTENSIONS.md](reference/CALLING_AND_EXTENSIONS.md) - 通话、插件、局域网 Bootstrap 与 IRC 扩展能力
- [reference/GROUP_CHAT_GUIDE.md](reference/GROUP_CHAT_GUIDE.md) - 群聊生命周期、持久化与常见问题
- [reference/PLATFORM_SUPPORT.md](reference/PLATFORM_SUPPORT.md) - 各平台支持范围与平台差异点

## 跨项目联动

- [主 README](../README.zh-CN.md)
- **Tim2Tox**（上游仓库 [https://github.com/agentx-icu/tim2tox](https://github.com/agentx-icu/tim2tox)）：[文档索引](../third_party/tim2tox/doc/README.md)、[Bootstrap 与轮询](../third_party/tim2tox/doc/integration/BOOTSTRAP_AND_POLLING.md)、[API 参考](../third_party/tim2tox/doc/api/API_REFERENCE.md)

实施计划（面向 agent/开发者）见 [docs/plans/](../docs/plans/)。历史/一次性文档归档见 [doc/archive/](archive/README.md)。
