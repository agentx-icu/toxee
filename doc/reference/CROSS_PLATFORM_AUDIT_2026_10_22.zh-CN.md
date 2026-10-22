[English](CROSS_PLATFORM_AUDIT_2026_10_22.md)

# 2026-10-22 跨平台审计及修复

基线为 toxee `fde59b44`、UIKit `bae30b7`、tim2tox `beb6e6a`。先独立核验
静态审计，再实现修复。CONFIRMED/PARTLY/REJECTED 是对原发现的裁定，不代表
发布就绪。没有使用 Claude 评审或 RTK。debug 构建不能证明正式包、真机或商店合规。

| 项目 | 裁定 | 实现与尚需验证 |
|---|---|---|
| 1 Apple 隐私，提交 P0 | PARTLY | 添加 app/native framework required-reason manifests：磁盘 E174.1、文件时间 C617.1、应用 UserDefaults CA92.1。macOS 包已含清单；iOS archive/隐私报告、SDK 所有者及商店标签仍需审核。缺加密 key 只触发问卷，不是自动拒绝；未伪造豁免答案。 |
| 1b macOS 发布，P0 | PARTLY | 最后修改 dylib 后，自内向外重签所有 native image/framework，再签 app、installer，可配置公证和装订。严格模式缺凭据失败。ad-hoc fixture 已通过 strict codesign；正式 Developer ID、下载隔离和双架构待验证。 |
| 2 桌面独占，P1 | CONFIRMED | bootstrap 写入前获取内核锁，永不 unlink 锁 inode；独立原子 metadata 避开 Windows mandatory lock。第二进程让位/激活，早期激活排队到 shell ready。独立进程竞争、激活、kill 后释放测试通过；Windows/Linux 原生 UI 待主机。隔离 app-support 若手工共享外部 profile 根目录，仍需额外协调。 |
| 3 hidden 摄像头，macOS P1 | PARTLY | eligibility 和显式暂停分支共用桌面 hidden 策略；移动端 hidden/paused/detached 仍暂停，inactive 继续。Windows/Linux 无捕获能力门禁不变。策略测试、macOS 构建通过；真摄像头双端最小化/隐藏/恢复未测。 |
| 4 HomePage 快捷键，P1 | CONFIRMED | 四个命令改为 macOS Cmd、Windows/Linux Ctrl。8 个真实 widget 按键/动作测试验证错误修饰键不触发、正确键只触发一次；移动端菜单/硬件命令扩展另计。 |
| 5 退出保存，P1 | PARTLY | caption close/framework quit 共用等待式幂等协调；窗口状态保存失败可在账号销毁前取消/重试。不可逆账号 teardown 无超时完整等待；完成时即使失败也记录并退出，避免留在依赖已销毁账号的页面。这不代表失败写入已持久化。延迟真实 dispose、runtime hook 抛错回归覆盖两种边界；移动 detached 保留 best-effort 时限。Windows WM_ENDSESSION、Linux session-manager/SIGTERM 未实现；任意 kill 无最终回调保证。 |
| 6 Android 权限，提交 P0 | PARTLY | 移除未用 READ_MEDIA_IMAGES/VIDEO/AUDIO，保留有版本上限的旧权限。拒绝移除 MANAGE_OWN_CALLS 的误报：现有 phoneCall FGS 需要它。源声明/通话测试通过；合并 APK/AAB、API34+ 后台捕获及 Play Console 声明待验证。 |
| 7 macOS 目录访问，P1 | PARTLY | 保存/恢复/刷新 scoped bookmark，探测可写；保留全部已获 URL 至窗口/进程结束，切换目录不撤销异步/native 传输访问。失效时清除自定义路径并提示默认目录回退。通道/prefs 测试、Swift typecheck、app 构建通过；sandbox release 在 Downloads 外选目录、重启、移动/撤销权限及传输中切换未测。未新增不存在的 profile-root UI。 |
| 8 Windows 通知，P1 | CONFIRMED | 插件17.2.4→19.5.0，仅变5个锁定依赖；稳定 AUMID/GUID、普通通知、来电 attention/取消，由插件注册激活。Android 最低23不变。通知回归通过，测试补等价 registrant；Windows 安装后通知/点击/设置待主机。 |
| 9 举报/Nearby，提交 P0 | PARTLY | 未解决。举报需真实接收及处置运营；Nearby 临时密钥无法持久识别某个人。暴露稳定身份将改变隐私/协议，需产品决策；未添加虚假接收端或永久屏蔽宣称。 |
| 10 窗口离屏，P1 | CONFIRMED | 按现有工作区校验标题可操作区域、支持负坐标、约束大小/位置，并响应显示器变化。几何测试通过；外接屏拔插、Windows 混合 DPI、Wayland compositor placement 待主机。 |
| 11 最大化 bounds，P2 | CONFIRMED | 单独保存正常 bounds，跳过最大化/全屏/最小化及启动恢复状态。fake-window 退出测试通过；原生 snap/tiling/fullscreen/重启待验证。 |
| 12 Linux 装饰，P1 | PARTLY | Linux 保留原生装饰，关闭重复 Flutter caption/inset；拒绝“所有 snapping 丢失”的无证据断言。非 GNOME X11 的边缘缩放/菜单、GNOME Wayland 仍需真实 WM。 |
| 13 网络恢复，P2 | PARTLY | macOS 加入 NWPathMonitor 路径身份/唤醒，复用会话去抖/限频；Swift typecheck/build 通过。拒绝桌面从不 resume 的误报，原有共享恢复已存在。Windows/Linux watcher 未实现，Wi-Fi/睡眠恢复耗时未测。 |
| 14 Linux 身份，P2 | CONFIRMED | 安装 com.toxee.app.desktop，StartupWMClass 对齐 program identity，Icon=toxee 对应现有图标。拒绝无点的非法 GApplication ID 替代方案。元数据测试通过；真实 X11 class/Wayland 分组待 Linux。 |
| 15 可选硬件/ABI，P2 | PARTLY | camera/autofocus/microphone/location 声明可选，源测试通过；合并 badging、无硬件行为待包/设备。发布仍仅 arm64，新增架构需完整 native 库及支持决策；不暗示支持 Android TV。 |
| 16 release 日志，P2 | CONFIRMED | 隐式 CWD/build 日志仅 debug 启用，保留既有编译期 harness 策略，release 运行时覆盖仍禁止。移动端原本已排除；正式包从可写/只读 CWD 启动仍需 smoke。 |
| 17 Linux 包/基线，P1 | PARTLY | DEB 启用 shlibdeps/private-library lookup，保留 RPM 自动依赖；文档修正为实际 Ubuntu24.04、Android23、iOS15.5。源配置测试通过；真实 DEB/RPM 依赖、GLIBC/GLIBCXX/CXXABI、干净安装启动未测；macOS 捆绑库有效最低版本未证。 |
| 18 Windows 发布，P1 | PARTLY | MSI 前二进制 Authenticode，MSI 后签名/校验，保留有效 vendor 签名；CI 添加真实安装/启动/关闭/修复/卸载。Mac 未执行 PowerShell；证书、跨版本升级、下载/SmartScreen 待验，同版本 repair 不算升级测试。 |
| B7 history，P1 | CONFIRMED | 独立 tim2tox 5341e64 在持久化源保护主文件/备份/未读直接保存/批量读/合并，未来版本字节原地保存，类型化升级错误传至 service 启动。unsupported 不重试，普通磁盘重试保留。34项 schema/写失败/rebind/并发/恢复测试通过。明确整账号/存储删除仍属单独授权删除；共享 Dart 覆盖移动端。 |
| B7 account prefs，P1 | CONFIRMED | 拒绝未来账号 schema；migration/LAN recovery 写入前预检全局及账号版本，复用本地化升级页。迁移/bootstrap 测试确认数据及版本不变，共享 Dart 覆盖全平台。 |

## 全部清单和移动端对等

英文文档的 **Full checklist disposition** 逐组列出 L1–X9 全部 ID，与本镜像共用。
既有 [MOBILE_DEVICE_FEATURES](MOBILE_DEVICE_FEATURES.md) 证据保留日期和设备限制。
尚未实现：折叠铰链/tabletop、全量触摸目标/布局扫描、iPad 菜单/指针、上游 reduced-motion
高亮及桌面 composer 竞态复核、OS share/tox: handlers、敏感导出截屏/切换保护、Windows badge、
Low Power/thermal、release 启动/体积/frame budget、Apple-silicon iPad/visionOS 发布与数据连续性。
桌面2秒状态轮询仍存在；联系人轮询已跳过 hidden/paused，列表不变不再重建。

耳机/Bluetooth、真实摄像头隐私指示、iPad 浮动键盘、Dynamic Type、混合/分数 DPI、
无 Secret Service 的 Linux、真实网络实验室、全平台已安装 release、符号/崩溃验证均待验。
Tox 无服务端版本冲突协调，B8 不适用；无购买 P8、无屏幕/系统音频捕获 M8 不适用。
所有共享 Dart 修改覆盖 iOS/Android；桌面窗口/锁没有对应移动窗口，原 Android engine-owner
保护保留。没有把模拟器证据或“待设备”写成新真机验证。

## 本地验证及发布边界

macOS debug 整包构建、新 Swift 独立 typecheck、ad-hoc Mach-O 签名 fixture strict 校验通过。
plist/Xcode 工程、shell 语法、最终回归、analyzer、复杂度门禁由交接摘要记录。
既有 plugin/Xcode warning 不等于 release 验证。未宣称正式包、公证、商店、真实摄像头/耳机、
Windows/Linux 安装运行已验证。

正式签名/公证凭据、UGC 运营/隐私决策、新 ABI、Windows/Linux 网络/系统退出集成及设备矩阵
仍是未解决项；配置好的 CI step 不能计作已执行成功。

最终本地回归：核心跨平台/通知/bootstrap/通话/schema/history/network/WinRT 共328项通过；追加本地化/快捷键/退出39项通过；tim2tox独立相关34项通过。`flutter analyze lib tool --no-fatal-warnings --no-fatal-infos` 无error（既有warning/info仍存在）；`dart run tool/check_complexity.dart`通过。

macOS 最后窗口自动终止已禁用，避免 Cocoa 抢在 Dart preventClose/checkpoint 前退出；成功保存后的 windowManager.destroy 仍调用 NSApp.terminate。此对等修复有源声明回归，仍须真实 Cmd+Q/关闭验证。

退出补充回归：窗口状态/session-shutdown/账号生命周期共25项通过，包括超过旧10秒时限的
延迟销毁、不可逆销毁后异常。修改的4个Dart文件分析无问题，复杂度门禁通过；这些测试
不代表失败写入已持久化。

macOS 打包 CI 补充：job 119902022028 已构建 release app，但直接执行 Git 模式644的
签名 helper 时失败。改为与其他CI helper一致的显式Bash调用；回归实际执行打包入口，
强制helper644，并确认签名失败时停止打包。SDK26.4真实Mach-O fixture通过ad-hoc
strict校验和PKG生成；正式Developer ID/公证、干净系统安装验证仍需独立完成。
移动签名使用独立打包路径，不受此问题影响。

PR首轮CI在x86_64暴露第二个签名顺序错误（job119912161238）：直接签CFBundleExecutable时，
codesign会检查所在bundle，而同级未签名库尚未就绪；arm64链接器自带的ad-hoc签名曾掩盖
此情况。现在先延后声明的bundle入口，签loose native文件，再自内向外签nested bundle，
最后用release entitlements签外层app。按inode匹配framework Versions/Current符号链接；
缺失executable key时不猜测入口。保留最终deep/strict校验，签名不使用--deep。

4项真实macOS fixture先移除全部已有签名，覆盖两种CPU架构、nested app/framework、
可选executable key、独立helper和含空格路径。旧脚本4项均失败，修复后通过；组合打包
回归共10项通过。可重复命令见英文镜像，两架构Mac打包job均在app构建前运行这些回归。
线上证据必须来自最终PR head，不能引用被替代的首轮CI作为合并依据。

Linux全量coverage随后发现1项旧测试仍将桌面宿主按移动端hidden摄像头策略断言
（3110项通过、1项失败）。测试现在显式覆盖完整mobile/desktop状态表，相邻controller
测试也显式指定desktop。生产摄像头行为未变，函数文档同步说明两种策略。

Windows ARM64还在Chocolatey附带的DotNet3.5部署停滞，旧job119912160586一直停留至
新提交取消。provision现在复用已安装可运行工具，否则有界重试获取
[官方WiX3.14.1 portable release](https://github.com/wixtoolset/wix3/releases/tag/wix3141rtm)，
并校验固定SHA256。旧asset的GitHub API未提供digest；固定值由官方ZIP独立计算并复核，
完整hash见英文镜像。工具含CLR4 metadata，但仍必须在两架构Windows实际通过有界
candle/light帮助探针及后续MSI/安装smoke。7项provision回归覆盖archive完整性、缺工具、
路径解析、exit失败和进程超时，不能替代真实Windows运行；移动打包不受该helper影响。

provision通过后，Windows ARM64 job119945606703暴露通知FFI插件的STL1011。已审阅的
1.0.3 archive指定C++17并包含WinRT；既有普通插件兼容逻辑未覆盖FFI target。仅此target
改用C++20。真实CMake/编译器fixture先复现C++17失败，再验证标准coroutine编译通过，
同时无关target仍为C++17；缺target硬错误和artifact到期检查避免兼容逻辑悄然失效。
新增4项fixture/artifact及既有6项WinRT回归本地通过，MSVC通知编译仍须线上CI实证。

同一日志明确报告Dart回退x64。2026-10-22核验：3.41.9对应engine的Windows ARM64
Dart/release archive均404；3.44.0对应文件均200，官方链接及
[Flutter上游讨论](https://github.com/flutter/flutter/issues/186730)见英文镜像。
因此仅ARM64 job使用3.44.0，并在执行前核对framework commit
`559ffa3f75e7402d65a8def9c28389a9b2e6fe42`；其他job及业务依赖pin保留现有版本。
LUCI_CONTEXT用于浅克隆stable checkout保留固定release的engine.version。
流式读取PE header门禁拒绝非ARM64 Dart，并在打包前检查app、Flutter engine、Tim2Tox
三者与目标架构一致。11项PE/MSI回归覆盖合法x64/ARM64、混合架构、坏签名、越界offset、
截断、缺文件和MSI Template不匹配。安装工程显式映射WiX machine和64位文件语义，
不依赖无编译器项目的默认值；3项真实生成CPackConfig的fixture先失败再通过，覆盖两种
架构及未知架构拒绝。安装smoke读取实际MSI SummaryInformation Template，并在启动/
关闭/repair/uninstall前核对已安装二进制的PE machine。
最终head仍须真实ARM64构建、MSI生成和安装smoke通过；PR按原条件跳过仅供tag/
手动发布的GitHub Release job。
