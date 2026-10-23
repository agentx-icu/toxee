[English](STORE_READINESS.md)

# 商店上架准备与检查记录

复核日期：**2026-10-23（Asia/Shanghai）**。使用更新后的
[cross-platform-app-checklist](https://github.com/agentx-icu/cross-platform-app-checklist)，
重点为 P4 隐私权限、P8 条件性商业规则、P9 商店政策、W4 桌面分发和 X6 发布证据。
这是[此前 65 项审计](../reference/CROSS_PLATFORM_AUDIT_2026_10_22.zh-CN.md)的专项补充。
CI 和制品检查只能证明下表列出的内容；上架还需要负责人声明与真机证据。

## 已补齐的仓库检查

| 范围 | 状态与证据 | 尚需完成 |
| --- | --- | --- |
| Android 最终 APK/AAB | **自动检查已验证**：逐个原生库 ELF ABI/加载段对齐、每 ABI 必需 app/Flutter/Tim2Tox 库、未压缩 APK 库的 16 KB ZIP 偏移；最终 APK 合并后的 ID、target SDK、权限、debuggable；真实 APK 签名与 AAB 每个条目的 JAR 签名。保留制品及库 SHA-256。 | AAB ZIP 偏移不能证明 Play 交付 APK 对齐。用 bundletool/Play 检查交付 APK、设备过滤和合并声明，在关闭兼容回退的真实 16 KB 设备验证原生加载。 |
| Android 分发模式 | **门禁已验证**：Gradle、本地打包入口和 CI 均拒绝缺失上传证书 SHA-256、debug signer、APK/AAB 签名不一致或签名输入不完整。损坏 ZIP、未签名/被篡改条目、错误证书均失败。 | 负责人提供上传密钥及控制台身份；Play App Signing 的交付证书另行记录。 |
| Windows MSI | **门禁已验证**：最终 staging 中所有 EXE/DLL 均复核架构，包含 Flutter 构建后追加的库；启用签名时，自有代码和 MSI 必须匹配预期发布者指纹，保留有效第三方签名。安装 smoke 检查所有 PE、启动、修复、卸载。 | 可信发布者证书、最终安装包信任证据、从上一版本升级和数据保留、商店资料。普通开发构建仍可未签名。 |
| macOS PKG / 已构建 iOS app | **检查已验证**：逐个原生文件架构、最终包自有与 SDK 隐私清单、源码声明的权限用途文案和 bundle ID；核验最终 macOS 签名、功能性 sandbox 权限并拒绝 get-task-allow。带签名但损坏的 iOS app 不会降级为 unsigned 成功。报告保留实际 SDK 元数据。 | API reason/收集行为审计、正式发布者身份、archive/export、profile、隐私报告、真机测试。Ad-hoc 签名仅证明完整性。 |
| Linux DEB/RPM | **门禁已验证**：所有 staged 原生文件架构；损坏库、悬空或指向开发机外部的符号链接失败。 | 干净发行版安装、升级/卸载、签名/元数据、所选渠道沙箱测试。 |
| iOS 分发入口 | **限制已验证**：TOXEE_REQUIRE_SIGNING=1 会拒绝现有开发 IPA 打包入口。 | 先实现并验证负责人批准的 Xcode archive/export。仅配置证书不能使现有 zip-based IPA 变成 App Store 导出包。 |

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

移动端审查 1–11 沿用现有行为及真机限制；第 12 项同时检查 Android/iOS 制品路径。
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
pwsh -NoProfile -File tool/ci/test_windows_signing_policy.ps1
flutter test test/ci/macos_signing_native_test.dart test/ci/macos_packaging_test.dart test/cross_platform_packaging_test.dart
```

CI 兼容性补充：使用 Android build-tools 35 和 37 的真实签名 fixture 均已验证；新版 scheme 标签不改变预期上传证书门禁。Flutter Windows 的 `data/app.so` 是由引擎加载的 ELF AOT snapshot，仅此固定路径显式允许该格式，仍须匹配目标 CPU；EXE/DLL 继续要求 PE。检查器也在真实 Flutter Windows x64 CI 制品的全部 17 个原生文件上通过。

原生链接修正：此前 PR 提交的最终 APK 检查拒绝了 CI 用 NDK 27.3 构建的真实 libtim2tox_ffi.so，其 PT_LOAD 仍为 4 KB。两个原生构建入口现在都启用 flexible page sizes，并显式将 max-page-size/common-page-size 设为 16384；新构建和外部 staged FFI 在 Gradle 打包前均检查 ELF、ABI 和对齐。缓存中的 4 KB 预编译库须从源码重建，调整 ZIP 偏移不能修复 ELF 对齐。本地重建入口为 `ABIS=arm64-v8a NDK=/path/to/complete/ndk bash tool/build_android_ffi.sh`。

本地以 NDK 27.0 验证：默认共享库被门禁拒绝，加入上述参数的同一 CMake fixture 通过。完整 release Tim2Tox/ToxAV 重编译后的三个 PT_LOAD 均为 16384，真实 ToxAV marker 和无 test-hook 门禁通过（staged SHA-256 `951d0a7fbb4a2d1cdc0612a88bd11be102cbac4c37e2143b8fbff1b3d62fab8e`）。这属于原生制品证据，最终 APK/AAB CI 与真实 16 KB 设备测试仍分别验收。Android 回归现为 33 项，包含 staged ELF 拒绝；原打包回归也覆盖 calling-stub opt-out 不能绕过 4 KB 预编译库拒绝。
