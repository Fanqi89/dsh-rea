# 变更日志

本项目遵循语义化版本：`vMAJOR.MINOR.PATCH`。
所有版本都可按标签锁装，互不冲突：

```powershell
dsh plugin --profile "$env:DSH_PROFILE" add github:Fanqi89/dsh-rea#v1.1.0
```

---

## v1.2.0 — 2026-10-21

**主题：按 DeepSeek Harness 的插件规范做完整适配（兼容性声明 + 注册表清单 + 卡片图标）。**

> 桥接补丁仍与 v1.0.1 一致（单行 `dsh-mcp-client` + 平台自适应 Node 启动器），
> 这一版补的是「让 DSH 能识别、校验、展示这个插件」的元数据层。

### 新增

- **`package.json` 增加 DSH 兼容性声明**：
  `peerDependencies: { "@deepseek-ai/dsh-mcp-client": ">=0.2.0-rc.2" }` +
  `peerDependenciesMeta` 标记为可选（避免 pnpm 去 registry 拉 Harness 内置包）。
  DSH 的 `evaluatePluginCompatibility` 会用运行时版本校验这条 peer：低于 `0.2.0-rc.2`
  时安装/激活明确报 `incompatible-version`，而不是「装上了却没有 `mcp__rea__*` 工具」。
- **`dsh.plugin.json`**：DSH 插件注册表清单 —— `id`、`version`、`engines.dsh: ">=0.2.0-rc.2"`、
  `contributes.skills: ["reverse-engineer-anything"]`，供插件市场 / 插件库存页读取。
- **`icon.svg`**：64×64 插件卡片图标（716 字节，圆角深色底 + 放大镜 + 二进制点），
  经 `package.json.icon` 与 `exports['./icon.svg']` 暴露。
- **`keywords`**：`dsh-plugin`、`deepseek-harness`、`mcp`、`reverse-engineering`、`decompiler`。

### 变更

- `exports` / `files` 增加 `icon.svg`，保证安装后卡片图标可用。

### 兼容性验证（本机 DSH 0.2.0-rc.2）

- `plugin_manager list_bundles` → `dsh-rea v1.2.0`，`enabled: true`，**无 incompatible 标记**，
  组件仍是单行 `rea-mcp`；
- 4 个 JSON（`package.json` / `dsh.plugin.json` / `locale/*.json`）均可解析，图标 716 B。

### 升级提示

- 从 ≤ v1.1.0 升级：同一 spec 重装会返回 `ambiguous-install`，先卸载再装，然后重启 Harness。
- DSH 低于 `0.2.0-rc.2` 的用户请继续用 v1.0.1（该版本不声明 peer）。

---

## v1.1.0 — 2026-10-21

**主题：把「能反编译一切」变成可复现、可验证的一条命令。**

> 桥接补丁与 v1.0.1 **完全相同**（单行 `dsh-mcp-client` + 平台自适应 Node 启动器），
> 所以从 v1.0.1 升级不需要改任何配置；这一版补的是「插件之外的能力层」。

### 新增

- **`docs/CAPABILITIES.md`** — 反编译能力全览：
  - 零依赖可用族（JS/Electron/ASAR、.NET、归档、PE 资源、EVM、证据体系）
  - 需外部工具族（原生 Ghidra/IDA/Hopper、APK JADX、APK 资源 apktool、设备 adb、浏览器、JEB、Linux 专属）
  - 平台边界（Windows 上 10 个 macOS 专属操作、Linux-only 工具链）
  - REA 上游本身不支持项（AAB/split APK/签名校验/资源表完整语义/运行时抓取/MCP prompt 模板）
  - 逐项验证方法与本机实测证据
- **`docs/SETUP.md`** — 依赖配置手册：Ghidra 12.1.4、JADX 0.7.1、apktool 3.0.3、platform-tools(adb)、浏览器路径；
  含 SHA-256 钉扎、macOS/Linux 手动步骤、**GitHub 直连超时的镜像方案**。
- **`scripts/setup-rea-tools.ps1`** — Windows 一键配置（9 步）：
  Node/JDK 探测 → Ghidra 下载校验解压 → 浏览器路径 → adb → JADX → apktool → 技能 → `rea doctor` 复核。
  支持 `-DryRun`、`-SkipGhidra/-SkipAdb/-SkipJadx/-SkipSkill`、`-WithApktool`、`-ToolsRoot`。
- **`scripts/apktool-shim.cs`** — `apktool.exe` 启动器模板：REA 用 shell-free `execFile` 启动 launcher，
  Windows 上 `.bat` 无法被直接执行，故编译一个小 exe 转发到 `java -jar apktool.jar` 并透传输出。

### 修复

- **`package.json` 的 UTF-8 BOM**：pnpm 处理 git 依赖时对 `package.json` 直接 `JSON.parse`，
  BOM 会让所有 `dsh plugin add github:…` 安装失败（`Unexpected token '﻿'`）。已剥离；
  仅 `setup-rea-tools.ps1` 保留 BOM（Windows PowerShell 5.1 解析中文必需）。

### 变更

- README 增加「反编译能力全览」摘要表、能力依赖行、v1.1.0 版本历史与按标签锁装说明。
- `locale/{en,zh}.json` 卡片描述补充「反编译 / APK 类与方法 Java 源码」。

### 本机实测（Windows x64 · DSH 0.2.0-rc.2 · rea-agents 6.4.0）

| 能力 | 结果 |
|---|---|
| 原生反编译 | Ghidra 12.1.4 分析 `notepad.exe`：9 段 / **794 函数** / 557 字符串；`entry` 返回伪代码 + 反汇编 + 调用关系 |
| APK 代码 | JADX 0.7.1：`com.llw` 包信息、`MainActivity.onCreate` 完整 Java 源码 |
| APK 资源 | apktool 3.0.3：完整 Manifest、字符串 `app_name=纳西妲送你的礼物`、14 个解码文件、coverage=complete |
| Android 设备 | adb `37.0.1-15733141` 被 `inspect_adb_client` 识别 |
| 工具注册 | 170 个 `mcp__rea__*`；doctor 中 Ghidra 全项绿灯（含 native decompiler / JDK 21 / native authority） |

### 升级提示

- 从 v1.0.1 升级：`install_bundle` 对同一 spec 重装会返回 `ambiguous-install`，
  先卸载再装（或 UI 里重装），然后**重启 Harness**。
- 新增的环境变量（`GHIDRA_INSTALL_DIR`、`REA_JADX_MCP_JAR`、`REA_APKTOOL_COMMAND`、`REA_ADB_PATH`、
  `REA_BROWSER_EXECUTABLE`）只在 Harness 启动时读入，必须重启。

---

## v1.0.1 — 2026-10-13

**主题：修复插件面板「共 2 个组件 · 1 运行中 · 1 异常」。**

### 修复

- v1.0.0 用「两行 + `disabled: !!js process.platform …`」挑选平台；部分 Harness 构建会忽略或误解析
  `disabled` 里的 `!!js`，导致第二条同 `serverName`（`rea`）的行真的尝试激活，撞上
  *duplicate server name* 规则后显示为**异常组件**。
- 改为**单行**：`command: node` + `args: ['-e', <~600 字节启动器>]`，启动器内部判断
  `process.platform`：Windows 走 `cmd.exe /d /c npx … mcp`，POSIX 走 `npx … mcp`；
  `stdio: 'inherit'` 直通 MCP 字节流，退出时用 `taskkill /T`（Windows）/ 进程组 `SIGTERM`（POSIX）清理子进程树。
- 不再依赖 `!!js`，也不会产生重复注册。

### 变更

- README 记录单行方案与「为什么不是两行」的原因，补充 `ambiguous-install` 升级路径。

### 验证

- 重启后插件面板只剩 1 个组件运行中；进程链为 `node -e → cmd.exe → npx → rea.mjs`；
  170 个 `mcp__rea__*` 注册正常。

---

## v1.0.0 — 2026-10-12

**主题：首个可用版本（把 REA 接进 DeepSeek Harness）。**

### 新增

- **configuration-only bundle**：不写插件代码，通过 Harness 自带的
  `@deepseek-ai/dsh-mcp-client` 以 stdio 方式拉起 `npx -y rea-agents@6.4.0 mcp`，
  REA 的 170 个工具注册为 `mcp__rea__<tool>`。
- `locale/en.json`、`locale/zh.json`：插件卡片标题与描述。
- 默认 `REA_MCP_INPUT_SCHEMA_PROFILE=compact`（模型可见 input schema 约 184 KB vs 全量 366 KB）。
- `toolCallTimeoutMs: 1200000`（Ghidra 首查默认 330 s 预算）、`maxInstructionBytes: 131072`、
  `failOnStartupError: false`。
- 双行插入（Windows / POSIX 各一条），由 `disabled: !!js` 按平台启用。

### 已知问题（v1.0.1 修复）

- 部分 Harness 构建下面板出现「1 运行中 / 1 异常」。

---

## 已知限制（所有版本通用）

- 需要 **Node.js 22.19+/24.11+/26+**（含 `npx`）；首次启动需联网拉取 `rea-agents`。
- 原生反编译需要 Ghidra / IDA / Hopper 之一（Windows 无 Hopper）。
- Windows 上不可用：10 个 macOS 专属操作、Linux-only 工具链（pwntools/binwalk/unblob/mitmdump/进程捕获）。
- REA 上游不支持：AAB、split APK、签名校验、完整资源表语义、Android 运行时抓取、MCP prompt 模板与资源订阅。
- 合规：仅用于你拥有或已获授权分析的软件，见上游 [DISCLAIMER.md](https://github.com/morluto/rea/blob/main/DISCLAIMER.md)。
