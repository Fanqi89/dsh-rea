# 反编译能力全览

> 插件把 REA（rea-agents 6.4.0，**170 个工具**）以 `mcp__rea__<tool>` 暴露给 Harness。
> 本页回答三个问题：**能反编译什么**、**还差什么**、**哪些永远做不到**。
> 依赖怎么装见 [SETUP.md](SETUP.md)。

## 1. 零依赖（装上插件立刻可用）

| 目标 | 能拿到什么 |
|---|---|
| JavaScript / Electron / ASAR | 模块图、导入关系、路由/端点候选、Electron 边界（BrowserWindow/IPC/contextBridge）、source map、版本对比、特性追踪 |
| .NET (PE/CLI) | 程序集身份、目标框架、CIL 指令、成员签名、P/Invoke 原生边界、成员/签名比对 |
| 打包文件 | ZIP / APK / IPA / MSIX / AppX / DMG 成员清单、SHA-256、plist、Apple bundle 剖析、安全解包 |
| PE 资源 | 类型/名称/语言资源树、payload 区间与哈希、RT_GROUP_ICON 候选 |
| EVM 字节码 | 分发 selector、参数字符串、可变性推断（不查链、不执行） |
| Keyed archive / Interface Builder | NSKeyedArchiver 对象图；storyboard/nib 归档对象与连接 |
| 证据体系 | Evidence 导入/导出/比对、重建义务清单、残差未知登记与校验、静态/运行时关联 |
| 进程捕获 | 终端输出、交互、退出码、文件系统观测与两次运行对比（仅 Linux/macOS） |

## 2. 需要外部工具（一条命令补齐）

| 能力 | 需要 | 环境变量 | 验收判据 |
|---|---|---|---|
| **原生二进制反编译**：伪代码、汇编、函数清单、xref、调用图、字符串/名称搜索、DWARF/结构 | Ghidra 12.1.x（或 IDA / Hopper） | `GHIDRA_INSTALL_DIR`（IDA: `REA_IDA_MCP_CONFIG`） | `open_binary` + `analyze_function` / `procedure_pseudo_code` 返回伪代码 |
| **APK 代码反编译**：包信息、Manifest、类清单、**方法级 Java 源码**、smali 回退、引用追踪 | 完整 JDK 17+（含 `jdk.compiler`）+ jadx-headless-mcp 0.7.1 | `REA_JADX_MCP_JAR`、`JAVA_HOME` | `inspect_android_method` 返回 Java 源码 |
| **APK 资源**：资源表与资源解码 | apktool | `REA_APKTOOL_COMMAND` | `inspect_apktool_client`、`decode_android_resources` |
| **Android 设备**：装/拉 APK、logcat、截图、进程、设置 | adb（platform-tools） | `REA_ADB_PATH` | `inspect_adb_client`、`list_adb_devices` |
| **网站/浏览器**：DOM、脚本、网络观测、截图、场景回放、WebMCP 工具发现 | Chrome / Edge | `REA_BROWSER_EXECUTABLE` | `list_browser_targets`、`inspect_web_page` |
| **JEB 项目**：单元列表、类型/方法伪代码 | 已启动的 JEB 客户端（MCP） | `REA_JEB_MCP_URL` | `inspect_jeb_client`、`list_jeb_units` |
| 固件：区域识别/解包/交给原生分析 | Linux + binwalk / Unblob | — | `inspect_firmware_regions`、`extract_firmware` |
| ELF 布局、崩溃 core、mitmproxy 抓包 | Linux + pwntools / GDB / mitmdump | — | `inspect_binary_layout`、`inspect_recorded_crash` |

## 3. 平台边界（不可绕过）

**Windows 上不可用**（REA 明确报 `unsupported_host`）：

- 10 个 macOS 专属 provider 操作：`inspect_macho`、`list_architectures`、`inspect_signature`、`inspect_plist`、`demangle_swift`、`inspect_asset_catalog`、`inspect_native_dispatch_metadata`、`observe_native_calls`、`observe_native_ui`、`capture_native_ui_scenario`
- Hopper（macOS 应用）；Linux 专属：pwntools/binwalk/unblob 链路、mitmproxy 原生抓包、进程捕获（PTY）

**macOS 上不可用**：Windows 专属的 Windows Ghidra P0 之外的差异较小；Hopper 可用。

**任意平台都不可用的平台专属项**：跨平台互斥的那些工具会返回结构化 `unsupported_host`，不会静默失败。

## 4. REA 上游本身不支持（与平台无关）

- MCP 协议：prompt 模板、资源订阅、task-based 执行扩展（相关调用会被拒绝）
- APK：AAB、split APK、签名校验（明确 `signature_verification: not_performed`）、完整资源表语义、APK 内原生库（需转 Ghidra）、Android 运行时行为抓取
- Android 设备：不提供设备服务/模拟器安装，只用调用方提供的 adb
- 历史源码导入 `import-reference-source`：Windows 返回 `unsupported_host`（需 Linux/macOS）
- 所有运行类操作都在**调用方给定的目标与动作范围内**执行，不做扩权

## 5. 在 Harness 里逐条验证

| 能力 | 试这一句 / 这个工具 | 期望 |
|---|---|---|
| 工具已接入 | 让 Agent「列出你的 mcp__rea__ 工具」 | 170 个 `mcp__rea__*` |
| 原生反编译 | 「用 REA 打开 `C:\Windows\System32\notepad.exe` 并分析 main 的伪代码」 | 伪代码 + Evidence |
| APK 代码 | 「反编译桌面上某个 apk 的 `com.xxx.MainActivity.onCreate`」 | Java 源码 |
| APK 资源 | 「解码这个 apk 的资源表」 | 资源清单 |
| Android 设备 | 「列出 adb 设备」 | 设备列表（或识别 adb 路径） |
| 浏览器 | 「列出当前浏览器页面」 | CDP 目标列表 |
| 引擎体检 | `npx -y rea-agents@6.4.0 doctor --json` | `ghidra`/`jadx`/`skil` 等检查项转绿 |

## 6. 本机实测记录（Windows 10/11 x64 + DSH 0.2.0-rc.2 + rea-agents 6.4.0）

| 日期 | 项目 | 结果 |
|---|---|---|
| 2026-10-21 | MCP 接入 | 170 个 `mcp__rea__*` 注册成功；`initialize → rea@6.4.0` |
| 2026-10-21 | **原生反编译** | Ghidra 12.1.4 分析 `notepad.exe`：9 段 / **794 个函数** / 557 字符串；`entry` 函数输出伪代码 `__security_init_cookie(); FUN_140023a50();` + 反汇编 + 调用者/被调者 |
| 2026-10-21 | APK 包信息 | `com.llw` / v1.0 / minSdk 16 / targetSdk 30 / 6 类 / 7 资源 |
| 2026-10-21 | APK 方法反编译 | `com.llw.MainActivity.onCreate` 输出完整 Java 源码（JADX 0.7.1 + JDK 21.0.11） |
| 2026-10-21 | APK 资源解码 | apktool 3.0.3（exe shim）：完整 Manifest、`app_name=纳西妲送你的礼物`、14 个解码文件、coverage complete |
| 2026-10-21 | Android 设备 | `inspect_adb_client` 识别 adb `37.0.1-15733141`（路径来自 `REA_ADB_PATH`） |
| 2026-10-21 | doctor | Ghidra 全项绿（version 12.1.4 / native decompiler win_x86_64 / JDK 21 64-bit / native authority） |
| 2026-10-21 | capabilities | 18 项 provider 操作：8 可用 / 10 macOS 专属不可用（Windows 预期） |
