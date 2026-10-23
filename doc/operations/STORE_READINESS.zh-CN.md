[English](STORE_READINESS.md)

# 商店上架准备与检查记录

复核日期：**2026-10-23（Asia/Shanghai）**。使用更新后的
[cross-platform-app-checklist](https://github.com/agentx-icu/cross-platform-app-checklist)，
重点为 P4 隐私权限、P8 条件性商业规则、P9 商店政策、W4 桌面分发和 X6 发布证据。
这是[此前 65 项审计](../reference/CROSS_PLATFORM_AUDIT_2026_10_22.zh-CN.md)的专项补充。
CI 和制品检查只能证明下表列出的内容；上架还需要负责人声明与真机证据。

## macOS 既有 Preferences 动作（I2）

MainMenu.xib 原本有 Preferences… 项却未连接 action；Flutter 既有 Cmd+, 已能打开设置页。本次 native 项通过 toxee/desktop_menu 调用同一个动作，仅在账户初始化完成且 Home 为当前 route 时启用，被覆盖或 dispose 时禁用；附带 route-owner token，排队的旧命令不能跨账户切换。四条真实 widget/channel 生命周期回归及原八条快捷键回归通过，真实 macOS debug app 已编译 Swift 和接线 XIB。这不代表 iPadOS 26 native 命令或 installed release 的无障碍/菜单巡检完成，后者分别保留。

## 本地生产诊断（X9，部分完成）

Framework/dispatcher 钩子现早于 session ownership 和 bootstrap 安装；外层 guarded zone 也覆盖 binding 初始化失败。生产 Dart 日志仅接收固定 origin、异常 runtime type、受限的真实 VM package/dart 位置或 AOT build ID/地址；任意正文、异常原值、framework context/collector、SDK print 正文均丢弃，console 和 logger 自身失败出口也遵守此边界。Debug binding 错误缓冲、呈现和 harness 正文保留。早期最多缓冲 32 条记录，每条最多 24 行允许的栈；sink 可用后写入，失败回退不重入 logger。

沿用既定十个 app 日志文件、每段 10 MB。显式 canonical app_<timestamp>.log 路径现与隐式默认路径一样轮转；任意 custom fixture 名称保留已说明的 append 行为。`test/util/production_diagnostics_test.dart` 覆盖边界与留存；`python3 tool/ci/test_production_diagnostics.py` 检查真实子进程 stdout/stderr 的 marker secret，并以精确符号还原真实 stripped Dart AOT 栈。这些共享代码证据不代表每个 OS 已安装 release 的真实崩溃验收。

**仍有工程项：** Tim2Tox 的 V2TIMLog 持有独立 mutex 保护的 std::ofstream，FFI 仅有 set-log-file；SDK OnLog listener 并非 V2TIMLog writer。Dart rename/reopen 不能轮转仍持有的原生 descriptor，周期 stat 也不能对并发原生写入建立硬上限。原生 sink ownership/有界留存、独立 worker 错误转发、原生崩溃捕获、完整精确构建符号归档及 installed release 故障/符号还原仍待完成；这些不必然依赖远端服务。本次未增加上传或遥测服务。

## Linux 账户目录（W3）

相对 XDG_DATA_HOME 按 XDG 规范忽略，沿用 HOME/.local/share 默认目录；没有 HOME 时沿用平台 Application Support。保留绝对 XDG override、用户自选目录、既有账户和一次性 legacy 迁移。`python3 tool/ci/test_linux_profile_paths.py` 在真实 Linux 子进程中分别设置四组环境，核对账户字节、重复调用及 CWD 无迁移文件；这是独立的硬 CI 步骤。本机 macOS 路径回归不能代替 Linux 实际执行。

## 已补齐的仓库检查

| 范围 | 状态与证据 | 尚需完成 |
| --- | --- | --- |
| Android 最终 APK/AAB | **自动检查已验证**：逐个原生库 ELF ABI/加载段对齐、每 ABI 必需 app/Flutter/Tim2Tox 库、未压缩 APK 库的 16 KB ZIP 偏移；最终 APK 合并后的 ID、target SDK、权限、debuggable；真实 APK 签名与 AAB 每个条目的 JAR 签名。保留制品及库 SHA-256。 | AAB ZIP 偏移不能证明 Play 交付 APK 对齐。用 bundletool/Play 检查交付 APK、设备过滤和合并声明，在关闭兼容回退的真实 16 KB 设备验证原生加载。 |
| Android 分发模式 | **门禁已验证**：Gradle、本地打包入口和 CI 均拒绝缺失上传证书 SHA-256、debug signer、APK/AAB 签名不一致或签名输入不完整。损坏 ZIP、未签名/被篡改条目、错误证书均失败。 | 负责人提供上传密钥及控制台身份；Play App Signing 的交付证书另行记录。 |
| Windows MSI | 保留最终 staging 架构和发布者门禁，新增 app-local MSVC CRT 原厂签名、运行库导入闭包、安装目录实际加载检查；须由两个机器目标的最终 Windows CI 验证。MSI smoke 覆盖 installed PE、启动、修复和卸载。 | 可信发布者证书、运行库再分发权利、终包信任、上一版升级/数据保留及商店资料。开发包可不签自有代码，内含 Microsoft CRT 仍须保留有效原厂签名。 |
| macOS PKG / 已构建 iOS app | **检查已验证**：逐个原生文件架构、最终包自有与 SDK 隐私清单、源码声明的权限用途文案和 bundle ID；核验最终 macOS 签名、功能性 sandbox 权限并拒绝 get-task-allow。带签名但损坏的 iOS app 不会降级为 unsigned 成功。报告保留实际 SDK 元数据。 | API reason/收集行为审计、正式发布者身份、archive/export、profile、隐私报告、真机测试。Ad-hoc 签名仅证明完整性。 |
| Linux DEB/RPM | **inventory 门禁已验证**：原生架构和链接；新增干净 Ubuntu 24.04 容器 DEB gate，在安装测试工具前检查依赖，核对 installed 字节/mode，以 nobody 启动并观察同 PID 的 X11 窗口、engine/FFI maps，优雅关闭、卸载。最终 CI 须逐原生架构验证。 | RPM/其他发行版、Wayland、硬件、旧版升级、签名及渠道沙箱仍分别验收。 |
| iOS 分发入口 | **限制已验证**：TOXEE_REQUIRE_SIGNING=1 会拒绝开发 IPA 打包入口。另有仅本地 archive/export 入口，检查显式手工导出策略及导出包签名/profile 身份。 | 负责人真实签名导出和真机安装仍待验收。Unsigned archive 或 zip-based IPA 不是 App Store 导出包。 |

回归覆盖真实 aapt2/apksigner/JDK 签名操作、真实编译的 macOS 签名，以及损坏/错误架构负例。
合成 ELF/JAR 仅测试检查器，不证明应用可安装。对应 CI artifact 保留
native-inventory.json、android-preflight.json、apple-preflight.json。

## Android 分发复现

普通 PR 构建明确属于开发验证。手动 workflow 的 android_distribution=true 要求：

- secrets：ANDROID_KEYSTORE_BASE64、ANDROID_KEYSTORE_PASSWORD、ANDROID_KEY_ALIAS、ANDROID_KEY_PASSWORD。
- repository variable：ANDROID_SIGNING_CERT_SHA256，预期上传证书 SHA-256，64 位十六进制或冒号分隔格式。不要将私钥或密码写入报告、issue、PR。

最终签名 APK/AAB 构建完后，本地等效入口：

```bash
export ANDROID_HOME=/path/to/android-sdk
export ANDROID_SIGNING_CERT_SHA256=负责人提供的上传证书SHA256
TOXEE_REQUIRE_SIGNING=1 bash tool/ci/package_artifacts.sh --target android --mode release
```

当前默认检查 com.toxee.app、arm64-v8a、target SDK >=36。本地显式调整
TOXEE_ANDROID_ABIS（空格分隔）或 TOXEE_ANDROID_MIN_TARGET_SDK 时，应同时复核渠道政策；
CI 参数独立固定。按本次复核，常规手机 Play 提交要求 API 36，延期须以负责人控制台条件为准；
当前 16 KB 官方页面列出的更新阻断日期为 2027-02-01。未来提交前重新查阅官方政策。

Windows 使用 WINDOWS_SIGN_CERT_SHA1、已安装的私钥证书和 signtool；
TOXEE_REQUIRE_SIGNING=1 拒绝缺少签名身份。macOS 直接分发使用现有
MACOS_DEVELOPER_ID_APPLICATION_CERT、MACOS_DEVELOPER_ID_INSTALLER_CERT、
MACOS_NOTARYTOOL_PROFILE，strict 模式要求签名及公证。Developer ID 直接分发与
Mac App Store 签名/profile 是不同流程。

## 渠道选择和负责人交接

### 桌面原生依赖与 installed 证据

#140 的 ARM64 终包清单有 23 个原生文件，但没有 MSVC CRT。真实 PE 导入需要
MSVCP140/VCRUNTIME140，Tim2Tox 还需要 MSVCP140_ATOMIC_WAIT；hosted runner 预装的
工具链掩盖了 app-local 依赖缺失。CMake 现从所选工具链的目标架构 VCToolsRedistDir
或官方 InstallRequiredSystemLibraries 取 release CRT，拒绝缺失、debug、歧义或错误 CPU，
并安装再分发提示。签名前后均检查原始 Microsoft Authenticode 签名和全部 PE 的 runtime import
闭包；installed smoke 检查已加载 CRT 真实来自 app 目录，不用发布者证书重签微软文件。
独立本地签名入口也在查找签名工具前拒绝损坏/未签名/非微软 CRT，CRT 永不进入重签分支。
Windows CI 会修改真实已签运行库副本的字节，验证其在调用 signer 前被拒绝。
只读提取微软官方 redist 的 PKCS7 确认两个明确 CN：ARM64 的 `Microsoft Corporation`、
x64 的 `Microsoft Windows Software Compatibility Publisher`；均还须精确 Microsoft Corporation
组织及 Windows Authenticode Valid。参考 x64 安装器 SHA-256 为
`cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b`。
离线提取证书本身不证明签名可信。
安装后关窗必须 exit 0。runner 在 COM 退出前显式通过 OnDestroy 销毁 controller，
先清空 client 指针，避免 native 子窗口销毁回调重入已失效的 Flutter controller；
字体变化消息也容许该指针已清空。两个 Windows 目标均须在最新 PR head CI 证明实际正常退出。

ARM64 单独处理：2026-10-23 只读检查的微软官方 ARM64 redistributable 中，
MSVCP/VCRUNTIME/atomic-wait DLL 为 ARM64X，vcruntime140_1.dll 仅 ARM64EC。
旧版 native ARM64 制品导入不引用后者，因此不带入；x64 仍要求 Flutter 列出的三个 DLL。
这些 ARM64X CRT 的 raw PE Machine 仍为 AA64，EC-only 补充库的 raw Machine 为 8664。
保持原严格 AA64 架构门禁，不增加通用混合架构例外；CRT 使用经过审查的文件名，全部须保留有效 Microsoft 签名。
参考安装器 SHA-256 为 `5139e1440c3a20b92153a4db561c069a0175aaf76c276c3e5b6f56099edcf4b0`，
CI 使用自己编译器选择的 redist，不使用该下载安装器；Windows 10/11 提供 Universal CRT。
依据：[Flutter Windows 分发](https://docs.flutter.dev/platform-integration/windows/building#building-your-own-zip-file-for-windows)、
[Microsoft 再分发说明](https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files)、
[ARM64X 兼容性](https://learn.microsoft.com/en-us/windows/arm/arm64x-pe)。
负责人仍需确认适用的 Visual Studio 再分发权利；复制成功/签名有效不等于取得许可。

两个 Linux package job 分别在 native x86_64/aarch64 宿主运行干净容器 DEB gate，
不挂载 SDK 或宿主桌面/数据。JSON/log 记录精确 DEB/image 身份、依赖、installed hash、
窗口/PID/maps、卸载结果，失败也保留。Xvfb 软件渲染仅证明此 Ubuntu/X11 启动路径，
不代表 RPM/Wayland、真实 GPU/音频/相机/网络或旧版升级通过。
DSO 依赖检查仅可使用已安装 app 的私有库目录，模拟 engine 已加载 companion 的上下文；
真实 GUI 启动不覆盖 LD_LIBRARY_PATH，仍须映射已安装的 engine/FFI。
首次干净安装暴露 libEGL loader 缺失：两个架构都在窗口出现前 abort。
DEB 现显式依赖 libegl1/libgl1/libgles2，RPM 声明对应 SONAME；libepoxy 使用 dlopen，
静态 shlibdeps 无法发现这些依赖。修正后的终包仍须最终 native DEB gate 验证；
RPM 依赖声明不等于已完成 RPM 安装验收。
gate 在安装 harness 前解析这三个准确 SONAME，核对实际文件、native 架构与依赖闭包并留证，
测试设施带入的图形包不能补足此前缺项。
Linux 关窗仍先等待应用窗口/账号 checkpoint，成功后使用 Flutter SystemNavigator.pop 的
application-quit 路径，避免 window_manager 在 engine 退出中同步销毁 GTK/GL view
（[上游报告](https://github.com/leanflutter/window_manager/issues/585)）。MethodChannel 回归检查
保存等待、取消后重试及重复关窗合并；最终 native DEB smoke 仍须实测 exit 0。

### 本地 iOS archive 与手工导出

按正常流程 bootstrap 依赖并暂存无 test-hook 的真机 Tim2Tox framework 后，运行
`python3 tool/ci/ios_store_export.py --unsigned-archive` 生成 unsigned Xcode archive。
iOS package job 同样运行此路径，将 archive、dSYM 和检查报告保存七天；它**不是正式签名或可提交商店的 IPA**。
负责人须在 CI 保留期结束前自行归档拟发布构建。

在负责人安全环境中，已有 Apple Distribution 证书/私钥和 App Store profile 时，提供批准的
ExportOptions.plist，再运行：

```bash
python3 tool/ci/ios_store_export.py --team-id ABCDE12345 \
  --certificate-sha1 OWNER_CERTIFICATE_SHA1 \
  --export-options /secure/local/ExportOptions.plist
```

替换示例公开 ID/指纹；文档未批准任何示例团队、profile 或法律主体。plist 必须显式设置
`method=app-store-connect`、`destination=export`、`signingStyle=manual`、一致的 `teamID`，
`signingCertificate` 为该证书准确的 40 位 SHA-1，`provisioningProfiles` 仅将
`com.toxee.app` 映射到已有 profile 名称或 UUID。入口先保存策略快照，拒绝已存在的输出目录，
防止失败后复用旧 IPA；检查 archive/导出包原生库和声明、签名完整性、profile 到期、明确的
app/team entitlement、禁用调试，以及 profile 绑定的真实 app signer 证书。
设备/ad-hoc/enterprise profile 与仅内部 TestFlight 的导出均拒绝。
archive 仅允许预期应用；声明的可执行文件必须是 bundle 内具备执行权限的实际文件。
原生 inventory 继续检查其真实 Mach-O header 与架构。
archive 根必须是实际目录；包括 dSYM 在内的所有链接必须使用有效的内部相对目标，保证 tar 换目录解压后仍可使用。

入口先以 `flutter build ios --config-only --no-codesign` 生成配置，再直接调用 Xcode archive/export；
不传自动 provisioning/设备注册参数，不上传。直接使用 signed `flutter build ipa` 会传这些自动参数，
不能用来执行本任务“不修改账号”的边界。检查 `archive-evidence` 和
`export-evidence/distribution.json`；fixture 策略测试不等于真实签名或 App Store 审核通过。
导出键依据本机 Xcode 26.4.1 的 `xcodebuild -help`，核验日期 2026-10-23。

此商店准备入口对 unsigned archive 和实际导出 app 均要求 built `DTXcode` 为 Xcode 26+，
`DTSDKName` 为 `iphoneos26+`，两个最低版本要求独立核验。缺失、畸形、模拟器或旧版本元数据
会在导出命令或分发证据成功前失败。CI 使用 `macos-26`，通过 `DEVELOPER_DIR` 显式选择
已经安装的 Xcode 26+，构建前核验实际 iPhoneOS SDK；不改变全局 Xcode 选择或安装工具链。
此前 hosted 兼容性 archive 实际为 Xcode 16.4 / iPhoneOS 18.5，不满足当前商店最低要求。
普通开发 IPA 路径独立保留。此最低要求依据 2026-10-23 复核的
[Apple 提交要求](https://developer.apple.com/news/upcoming-requirements/)，未来提交仍须重新复核政策。
新版 hosted Xcode 也拒绝了生成 framework 标识符中的下划线。构建现输出合法的
`org.toxee.tim2tox-ffi`；framework/可执行文件名和运行时加载路径仍为 `tim2tox_ffi`。

2026-10-23 本地真实 unsigned archive 验证：Flutter 3.41.9、Xcode 26.4.1（17E202）、
iphoneos26.4（23E252）、应用 0.1.0+1、最低 iOS 15.5。真实 Xcode archive 成功，45 个 arm64
原生文件、built 声明/隐私清单、嵌入 Tim2Tox 无 test-hook 检查通过。本地复用了已有真机 FFI，
CI 从锁定源码重建。导出策略/失败传播及 bundle 边界回归 19 项、Apple metadata 回归 5 项、native payload
回归 11 项通过。没有执行负责人正式签名导出、商店上传或真机安装。

原 advisory analyzer 实际以 exit 1 结束，含 62 warnings、189 infos，却被 GitHub 显示为成功。
251 条 normalized 诊断与已合并 #140 完全相同，无原生变更新增项。源代码修正 async 错误归属、
生命周期/context 守卫及其余诊断，依赖保留既有版本。同范围严格命令
`flutter analyze lib tool test integration_test` 现为 CI 硬门禁，移除 continue-on-error，
没有忽略规则或缩减范围。本地零诊断不能替代最终 head CI、行为回归和真机测试。
coverage job 在暂存真实 FFI 后设置 `TOXEE_TESTS_NEED_NATIVE=1`，强制执行加密密码取消
案例，不能走可选 native 测试的 skip。仅适用 macOS 的签名案例仍在 macOS 执行，
Linux coverage 不代表这些平台检查通过。

| Checklist ID | 状态 | 证据和仍需验收 |
| --- | --- | --- |
| P1、P4 | 检查门禁 verified；负责人审计 to do | archive/导出包检查 built Apple metadata/原生库；SDK/API reason、数据声明和后台答案仍由负责人复核。 |
| W4、X6 | unsigned archive/策略门禁 verified；正式分发 to do | 上述真实 unsigned archive；负例拒绝上传、自动签名、错误团队/profile/证书、到期、开发/设备/企业身份和旧输出复用。真实手工签名导出/安装尚未验证。 |
| X9 | to do | archive/dSYM 保留七天；仅归档不能证明 native reporter 覆盖、符号匹配或受控 release crash 解析。 |
| X4 | needs device | 负责人签名导出后在 iPhone/iPad 安装/升级，验证权限、网络/媒体和用户数据保留。 |
| X5 | verified（变更范围）；平台差异验收保留 | 平台打包门禁和 analyzer 要求的 async/生命周期修正由回归及最终 native CI 验证。Android 保留既有终包门禁，不据此宣称通用功能等价。 |
| L*、D*、I*、B*、M*、F* | 保留既有审计状态 | async/生命周期安全修正不等于布局、输入、媒体、性能或真机验收。原完整审计限制保留；移动端第 12 项新增 archive 证据，不等于正式分发验收。 |

### 需要负责人提供的材料

公开 ID、URL、证书指纹可以写入发布证据。私钥、密码、token 和审核凭据仅保留在负责人安全环境
或商店指定的秘密字段，不在仓库、PR 或报告中收集/提交。

| 平台/渠道 | 材料及用途 | 获取/核实位置 | 阻塞步骤 |
| --- | --- | --- | --- |
| Apple iOS/iPadOS、MAS | 法定发布者、Team ID、app record、bundle ID；公开 ID 绑定发行身份 | Apple Developer **Account → Membership details**、**Certificates, Identifiers & Profiles → Identifiers**；App Store Connect **My Apps → 应用 → App Information** | 真实发行身份、导出和后台配置 |
| Apple iOS/iPadOS | 已有 Apple Distribution 证书 SHA-1、匹配的 App Store profile、批准的手工 ExportOptions | Apple Developer **Certificates, Identifiers & Profiles → Certificates / Profiles**；钥匙串访问 **我的证书**读取已安装私钥对应证书指纹；负责人管理的 Xcode archive 导出选项 | 正式本地导出、真机安装升级；私钥/密码仅安全环境配置 |
| macOS 直接分发 | 已有 Developer ID Application/Installer identity、notarytool profile | Apple Developer **Certificates**、钥匙串访问 **我的证书**、负责人已经配置的 notarytool keychain profile | 可信 PKG 签名、公证、带 quarantine 下载测试 |
| Google Play/其他 Android 商店 | 永久 package 记录、批准的上传证书 SHA-256、独立的交付证书 SHA-256 | Play Console **应用 → Test and release → Setup → App signing**；其他所选商店签名/应用后台；负责人保管的上传 keystore | 严格分发 APK/AAB 与签名升级；keystore/密码仅在安全环境或已有 GitHub Actions secret 字段配置 |
| Microsoft 托管 MSI/EXE | 发布者/product、已有可信代码签名 identity 指纹、不可变 HTTPS 安装 URL | Partner Center **Apps and games → product**；负责人证书提供方/证书管理器；已批准下载托管位置 | 可信 PE/MSI 签名和 hosted-installer 认证；密钥/token 只留安全签名环境 |
| Windows CRT 再分发 | 适用的工具链许可/再分发权利，批准原版 Microsoft release runtime 分发 | 负责人 Visual Studio 许可记录和适用的 [2022](https://learn.microsoft.com/en-us/visualstudio/releases/2022/redistribution) / [2026](https://learn.microsoft.com/en-us/visualstudio/releases/2026/redistribution) 再分发清单 | 正式发布法律验收；代码/签名门禁不授予权利、不代为接受协议 |
| Microsoft MSIX（可选） | 选定 package Identity Name、Publisher、商店记录 | Partner Center **product → Product identity** | 独立 MSIX 工程与验收；Store 重签不要求为此购买私有分发证书 |
| 实际选定的所有商店 | 批准的隐私/支持/适用删除 URL、SDK 数据流声明、版权法律文本、年龄/受众答案、本地化介绍/截图、审核说明、UGC 联系/响应机制 | 负责人公开政策页及法律/运营记录；App Store Connect **App Privacy / App Information / App Review**；Play Console **Policy and programs → App content / Store presence**；Partner Center submission **Properties / Age ratings / Store listings / Certification notes** | 负责人声明、审核可达性和政策复核；审核凭据只填商店安全字段 |
| 中国 Android 渠道（条件适用） | 地区、主体认证、适用的 APP 备案/行业材料 | 所选渠道开发者后台、负责人备案/法律记录 | 渠道准入；不由其他商店要求推断本渠道适用性 |
| Flathub/Snap/软件源（可选） | 渠道决定、名称/app ID 归属、人工维护的提交资料和沙箱证据 | 对应发布者后台与官方提交流程 | 独立打包审核；Flathub manifest 和提交 PR 仍由人负责 |
| 每个实际发布版本 | 准确包 hash/版本、地区/track、上一签名版本、真机结果 | CI artifacts、负责人发布归档、商店测试轨道/设备实验室 | 安装升级/数据保留、权限网络媒体、真实 16 KB 设备检查；账号材料不能替代 |

下列渠道均未标记为“可提交”。对实际选择的渠道，负责人须保留控制台导出/截图、精确提交包哈希、
复核日期及批准人。可选渠道先做产品决定，再补该渠道工程；没有配置不代表合规。

| 渠道 | 当前状态 | 下一步及验收证据 |
| --- | --- | --- |
| iOS / iPadOS App Store | **待办 / 需真机**。已有 built 声明与原生 inventory；CI IPA 用于开发/设备验证。 | 法定发布者、team、app record/bundle ID；archive/export 与 distribution profile、当前 Xcode/SDK 接受情况、隐私标签和 reason 报告、年龄/内容分级、加密分类、审核说明及可用的审核/demo/bootstrap 路径。iPhone/iPad 上安装、旧版升级、删除及拒绝权限实测。不能由使用 Tox 直接推断加密豁免。 |
| Mac App Store | **待办**。当前 PKG 属于直接分发。 | 选择 MAS 签名/profile；核对 sandbox/entitlements 和商店包安装、Apple 元数据/隐私/审核证据。负责人用批准的法律文本替换 com.example 版权占位符。 |
| Google Play | **待办 / 需真机**。已有严格上传签名及原生检查。 | 发布者/package、上传和交付两套证书、Data safety/隐私 URL、适用的外部账号删除资源、受众/评级、app access 和权限声明；bundletool/Play 交付 APK、16 KB 原生加载、后台通话和旧版本升级实测。 |
| 华为 AppGallery / 小米 / OPPO 等 Android 商店 | **条件适用 / 待办**。可复用签名 APK 预检。 | 明确商店和地区，按该渠道当前规则核对签名/更新身份、SDK/权限清单、隐私入口、截图评级/审核访问，以及适用的主体/备案要求。保留控制台决定；Play 审核不证明其他商店通过。 |
| Microsoft Store 托管非游戏 MSI/EXE | **待办**。已有 MSI、签名及安装 smoke。 | 明确选择该路径；不可变、版本化 HTTPS 离线安装 URL，可信 CA 的安装包和所含代码签名、静默参数、干净安装/升级/卸载、商店隐私/支持资料，并复核当前 hosted installer 政策。 |
| Microsoft Store MSIX | **条件适用 / 待办**。没有 MSIX 打包提交流程。 | 决定是否增加 MSIX；验证 package identity、manifest/capabilities、架构、安装更新和商店资料。Store 重签要求与托管 MSI 不同，不因 Store 签名的 MSIX 直接要求购买私有分发证书。 |
| macOS / Windows / Linux 直接分发 | **开发制品，负责人验收待办**。已有 PKG/MSI/DEB/RPM。 | 保留适用的签名/公证/信任检查、包哈希、最低 OS/架构、干净机器安装、上一版本升级和卸载结果。 |
| Flathub / Snap | **条件适用 / 待办**。DEB/RPM 不等于商店 manifest 或沙箱审核。 | 负责人选择渠道并维护提交、AppStream/snap 元数据、桌面集成、runtime/base、权限及沙箱测试。按当前 Flathub 政策，提交 manifest 和提交 PR 由人负责；本次不生成二者。 |
| WinGet / Homebrew / F-Droid | **条件适用 / 待办**。没有新增 feed。 | 先确定分发模式，再按官方资格、可复现/源码规则、安装校验和及更新归属验证实际包。 |

## 隐私、通信与审核访问缺项

项目已有账号删除与联系人屏蔽实现。本次不将 P2P 视为政策豁免；负责人仍须验证完整删除路径、
对端/备份剩余数据及适用的外部删除资源，验证应用内和商店中的隐私/支持 URL 与本地化，
用实际 SDK 和收集/传输路径审批隐私声明。

用户通信应明确并验证适用的举报/屏蔽/过滤、响应与联系流程、条款接受、年龄受众控制和审核访问。
已有屏蔽功能不等于完整审核/处置机制；不要虚构举报接口、法律主体、政策 URL 或审核账号。
P8 的计费、广告和第三方主登录规则对当前功能集**不适用**（未提供这些功能）；新增功能或地区时重评。

移动端审查 1–11 保留既有验收状态及真机限制；第 12 项同时检查 Android/iOS 制品路径。
见 [MOBILE_DEVICE_FEATURES.zh-CN.md](../reference/MOBILE_DEVICE_FEATURES.zh-CN.md) 的本次记录。
未受影响的 checklist ID 保留此前状态，不因本次变为全部已验证。

## 官方来源与验证命令

- [Android 16 KB 要求](https://developer.android.com/guide/practices/page-sizes)
- [Play target API](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en)
- [Apple 审核指南](https://developer.apple.com/app-store/review/guidelines/)
- [Microsoft Store 政策](https://learn.microsoft.com/en-us/windows/apps/publish/store-policies)
- [Checklist 渠道资料](https://github.com/agentx-icu/cross-platform-app-checklist/blob/master/references/stores.md)

```bash
python3 -m unittest discover -s test/ci -p 'test_android*.py'  # 需要 SDK/JDK 17
python3 -m unittest discover -s test/ci -p 'test_desktop_native_payload.py'
python3 -m unittest discover -s test/ci -p 'test_apple_release_preflight.py'
python3 -m unittest discover -s test/ci -p 'test_ios_store_export.py'
python3 -m unittest discover -s test/ci -p 'test_msvc_runtime.py'
python3 -m unittest discover -s test/ci -p 'test_linux_installed_smoke.py'
pwsh -NoProfile -File tool/ci/test_windows_runtime_policy.ps1
pwsh -NoProfile -File tool/ci/test_windows_signing_policy.ps1
flutter test test/ci/macos_signing_native_test.dart test/ci/macos_packaging_test.dart test/cross_platform_packaging_test.dart
```

CI 兼容性补充：使用 Android build-tools 35 和 37 的真实签名 fixture 均已验证；新版 scheme 标签不改变预期上传证书门禁。Flutter Windows 的 `data/app.so` 是由引擎加载的 ELF AOT snapshot，仅此固定路径显式允许该格式，仍须匹配目标 CPU；EXE/DLL 继续要求 PE。检查器也在真实 Flutter Windows x64 CI 制品的全部 17 个原生文件上通过。

原生链接修正：此前 PR 提交的最终 APK 检查拒绝了 CI 用 NDK 27.3 构建的真实 libtim2tox_ffi.so，其 PT_LOAD 仍为 4 KB。两个原生构建入口现在都启用 flexible page sizes，并显式将 max-page-size/common-page-size 设为 16384；新构建和外部 staged FFI 在 Gradle 打包前均检查 ELF、ABI 和对齐。缓存中的 4 KB 预编译库须从源码重建，调整 ZIP 偏移不能修复 ELF 对齐。本地重建入口为 `ABIS=arm64-v8a NDK=/path/to/complete/ndk bash tool/build_android_ffi.sh`。

本地以 NDK 27.0 验证：默认共享库被门禁拒绝，加入上述参数的同一 CMake fixture 通过。完整 release Tim2Tox/ToxAV 重编译后的三个 PT_LOAD 均为 16384，真实 ToxAV marker 和无 test-hook 门禁通过（staged SHA-256 `951d0a7fbb4a2d1cdc0612a88bd11be102cbac4c37e2143b8fbff1b3d62fab8e`）。这属于原生制品证据，最终 APK/AAB CI 与真实 16 KB 设备测试仍分别验收。Android 回归现为 33 项，包含 staged ELF 拒绝；原打包回归也覆盖 calling-stub opt-out 不能绕过 4 KB 预编译库拒绝。

Android ABI 选择：最终 CI APK 在指定 arm64 Flutter target 后仍带入了没有对应 FFI 的 armeabi-v7a 第三方库。Flutter 3.41 会预设 build-type ABI filters，覆盖 defaultConfig 中按 staged FFI 设置的范围。项目现[关闭 Flutter 自动 ABI 过滤](https://docs.flutter.dev/release/breaking-changes/default-abi-filters-android)，自行清空并按已构建 FFI 设置 filters。仅暂存请求的 ABI；最终 APK/AAB 清单仍拒绝额外 ABI 或缺少 app/engine/FFI 库的情况。当前发行路径为单个 APK 和 AAB，本次不宣称已验证 split APK。

修正后已在本地重建 release APK（52.9 MB）和 AAB（40.2 MB）。两包均恰含九个 arm64-v8a 原生库，使用 JDK 17.0.20 与 build-tools 37 的完整原生库/对齐及 APK/AAB 签名验证通过。最终 APK 为非 debuggable，标识 com.toxee.app，version code 1、minSdk 24、targetSdk 36；两包使用相同开发证书，不代表所有者批准的商店签名身份。APK SHA-256：`2207fe90f23b52a1f4263be7c4537a25426666c8f5023375e5dcf204d50b3b5e`；AAB SHA-256：`a8f1e0188d9fbea0ef9abb304d670377fdb7560996345abb10387436c4163054`。

Windows Tox 运行时：完整终包检查发现 ARM64 包中的 ImSDK.dll、dart_native_imsdk.dll 实为仅 x64。AppBootstrap 会等待 LoggingBootstrap 在 SDK 使用前将 Dart 原生库名称固定为 tim2tox_ffi；已审查的 vendor Windows 插件仅有空注册入口。应用自有 CMake 策略在两个 Windows 目标上保留编译后的注册插件与其他插件制品，移除未使用的 vendor 运行库/import 库，并清理增量安装中的旧副本。策略记录原生源码和构建定义的 hash，SDK 更新（包括未来动态加载）须显式复核。宿主机 CMake fixture 真实编译该插件源码，安装、加载并调用其 C 注册入口，全程不含两份 vendor DLL。原生 Windows 构建与完整终包架构门禁仍须在 CI 通过；宿主机 fixture 不替代 Windows 设备和安装器验收。
