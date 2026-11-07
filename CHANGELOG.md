# 变更日志

本项目遵循语义化版本：`vMAJOR.MINOR.PATCH`。
所有版本都可按标签锁装，互不冲突：

```powershell
dsh plugin --profile "$env:DSH_PROFILE" add github:Fanqi89/dsh-rea#v1.1.0
```

---

## v1.4.0 — 2026-11-07

**主题：把「装完就能用」做成跨 DSH 版本、跨平台的可靠启动链（Windows 桌面版 / 无头 CLI，macOS / Linux）。**

这一版不新增逆向能力，只修启动可靠性：**在一个没有 node 的环境、一个 PATH 上 Node 太旧的环境、
一个从 Finder 启动的 macOS app、一个先开 Harness 后连网的环境里，都不再静默丢工具**，
并且给「工具为什么没出现」留下可读的证据。全部结论来自对 5 个 DSH 版本的发布产物审计 +
本机端到端实测（证据见 `docs/COMPAT-VERSIONS.md`）。

### 修复（现象 → 根因 → 修法）

1. **macOS 从 Finder/Dock 启动的 Harness 里没有 `mcp__rea__*` 工具**
   → Finder 启动的 app 环境变量极简（`PATH=/usr/bin:/bin:/usr/sbin:/sbin`），启动器里的 `node`/`npx`
   根本不在 PATH 上，子进程直接 ENOENT。
   → `command: node` 改为 `command: !!js process.execPath` + `env.ELECTRON_RUN_AS_NODE: '1'`：
   用 Harness 自己的运行时可执行文件（桌面版是 Electron 二进制以 Node 模式运行，npm/CLI 安装则是 node），
   与 PATH 无关。DSH 自己的无头启动器 `resources/runtime/cli/bin/dsh.cmd` 用的就是同一机制，故一定可用。
2. **Windows 没装 Node、或 PATH 上是 Node 18/20 时同样没有工具（或 REA 起来就崩）**
   → REA 的 `engines` 是 `^22.19.0 || ^24.11.0 || >=26.0.0`；旧 Node 上不是报错而是各种静默失败。
   → 同上改用 Harness 自带 Node（本机实测 Electron 44.7.0 as Node **24.21.0**，`modules=149`），
   并实测它加载 REA 的原生依赖 `@lydell/node-pty`（N-API，ABI 稳定）与完成完整 MCP 握手都正常。
3. **每次启动都要 14–17 秒才出工具，离线/代理不通时干脆没有**
   → 启动器每次都走 `npx -y rea-agents@6.4.0`：npx 要解析 registry、要 PATH 上有 node。
   → 启动器改为**三层解析**：`$REA_MCP_ENTRY` → `~/.rea/dsh/agents/6.4.0/…/scripts/rea.mjs`（本地固定安装）
   → `npx` 兜底。命中本地层时用 Harness 的 Node 直接跑入口，**离线可用**；实测 `initialize` 从
   16.8 s（npx 冷）降到 **4.9–6.9 s**。本地层由 `scripts/setup-rea-tools.ps1` 新增的 1b 步
   （`npm install --prefix`）或 `scripts/setup-rea-tools.sh` 第 8 步准备。
4. **一次启动期失败就永久没有工具**（要重启 Harness 才能恢复）
   → `dsh-mcp-client` 默认 reconnect 只有 10 次、30 s 上限（约 2 分钟后**注销工具并停止**），
   而「先开 Harness、后连网 / 后启 WSL / 本地安装还没装完」是极常见的顺序。
   → 显式放宽为 `maxAttempts: 60` / `maxDelayMs: 60000`（约 1 小时自愈窗口）。
5. **`peerDependencies` 被当成 DSH 版本约束**（DSH 版本不满足时报 incompatible）
   → `dsh-app-boot` 的规则是：有 `engines.dsh` 时**只用它**判定 DSH 版本，否则拿所有 `@deepseek-ai/dsh*`
   peer 去和运行时版本比对；v1.3.0 只有 `peerDependencies["@deepseek-ai/dsh-mcp-client"]`，语义被错用。
   → `package.json` 与 `dsh.plugin.json` 都写 `engines: { "dsh": ">=0.2.1-rc.2" }`，peer 归位为
   「mcp-client 包版本」；已用 semver + `includePrerelease` 实算确认对 0.2.1-rc.2 / rc.3 / rc.4 / rc.5 /
   0.2.2-rc.1 全部满足（**去掉 includePrerelease 会全部不满足**——这是预发布版本能互相兼容的关键，不要“修正”范围）。
6. **「工具没出现」没有任何可查证据**
   → 启动器每次启动追加一行到 **`~/.rea/dsh/launcher.log`**（上限 64 KiB）：时间、`node`/`electron` 版本、
   命中的层、完整命令行、以及子进程退出码。
7. **Windows 上以 CRLF 检出仓库会让 `.sh` 直接坏掉**（`set -euo pipefail` 报 invalid option name）
   → 新增 `.gitattributes`：`* -text`（其余文件字节不变，保住 JSON 无 BOM / `.ps1` 有 BOM）+ `*.sh text eol=lf`。
8. **`rea-linux` 行首次启动可能被 WSL 的 UTF-16 状态文本污染 JSON-RPC**
   → 该行 `env` 增加 `WSL_UTF8: '1'`。
9. **v1.0.1 起注释里的理由写错了**（“旧 Harness 会误解析 `disabled` 里的 `!!js`”）
   → 审计确认 0.2.1-rc.2 起 `!!js` 在 patch `config` 值与 `disabled` 上都受支持；
   保留单行的真实原因是**同一作用域内 `serverName` 只能注册一次**。注释按真实理由重写。

### 新增

- **`scripts/setup-rea-tools.sh`**（macOS / Linux 一键配置，1,047 行）：
  9 步（Node ≥22.19 校验 → JDK 21+ → Ghidra 12.1.4 下载/校验/解压 → JADX jar → adb → apktool 可执行
  wrapper → 浏览器 → **rea-agents 本地固定安装** → doctor 汇总），支持 `--dry-run`、`--skip-*`、
  `--tools-root`、`--apktool-jar`；刻意只用 bash 3.2 特性（macOS 自带 bash），输出纯 ASCII，
  从不自动装系统包、从不改 shell profile（缺失项打印 `[hint]` + 精确命令）。
- **`docs/SETUP-POSIX.md`**：macOS / Linux 的前置、产物路径、环境变量表、**Dock/Finder 启动的 app
  如何看到环境变量**（`launchctl setenv` / wrapper，并说明本地固定层根本不需要这些变量）、
  JSON-RPC 探针、Gatekeeper 隔离属性、卸载/回滚。
- **`docs/COMPAT-VERSIONS.md`**：DSH `0.2.1-rc.2 → 0.2.2-rc.1` × `dsh-mcp-client` / `dsh-app-boot` 的
  逐版本审计（10 个 npm tarball 全解包、逐字节 sha256、`!!js` 求值点、env 清洗、reconnect、
  启动等待、semver 矩阵、REA 服务端实测、未验证清单）。
- `$REA_MCP_ENTRY` / `$REA_MCP_HOME` / `$REA_MCP_VERSION` 三个环境变量（入口覆盖、安装根、版本钉扎）。
- `scripts/setup-rea-tools.ps1` 新增 **1b 步**「REA MCP 服务器本地固定安装」与 `-SkipAgents`；
- `.gitattributes`。

### 变更

- `cordis.patch.yml`：`command` 改 `!!js process.execPath`，`env` 增 `ELECTRON_RUN_AS_NODE`；
  启动器 616 B → 1,858 B（三层解析 + 日志 + 信号升级）；移除 `maxInstructionBytes: 131072`
  （REA 的 instructions 实测 304 B，默认 32768 有百倍余量；超限不是截断而是判成连接失败）；
  新增 `reconnect`；`rea-linux` 行加 `WSL_UTF8`。
- `engines.dsh` / `peerDependencies` 统一到 `>=0.2.1-rc.2`（0.2.0-rc.2 用户请继续用 v1.3.0）。
- README：环境要求、配置项表、工作原理图、故障排查按新启动链重写。

### 验证（本机 Windows 10 · DSH 0.2.1-rc.5 · rea-agents 6.4.0）

- **跨版本审计**：`dsh-mcp-client` rc.2==rc.3（`lib/index.js` sha256 `758d8fc4…`）、
  rc.4==rc.5==0.2.2-rc.1（`64dfc912…`），配置面逐字节相同；`dsh-app-boot` rc.2–rc.5 同一文件
  （`5135179a…`），0.2.2-rc.1 的改动（platform 门禁 / insert clone / 删 5 个导出）都不落在本 bundle 使用面上。
- **schema 实跑**：两条 row 用真实 Config（schemastery 3.18.5 与 3.19.0 各一遍）校验通过；
  `reconnect` 解析为 `{enabled:true, initialDelayMs:500, maxDelayMs:60000, maxAttempts:60}`；
  `maxInstructionBytes` 取默认 32768。
- **真实宿主端到端**（独立 `DSH_HOME` + 独立端口，不碰用户正在跑的桌面实例）：
  `dsh --profile probe --dump-config` 输出 `# == dsh-rea` 层 → `dsh --profile probe --no-open --port 46124`
  真启动 → 进程树实测 `cli host` → `DeepSeek Harness.exe -e "<启动器>"` → `…/rea.mjs mcp`，
  服务进程保持存活（连接失败会被回收），`launcher.log` 记录 `launch local-install`，stderr 无告警。
- **MCP 握手**（Electron 44.7.0 as Node 24.21.0，直接跑 YAML 里的启动器）：`initialize` 4.9–6.9 s，
  `serverInfo {rea, 6.4.0}`，`instructions` 304 B，`tools/list` **170 个**，全部公开名 ≤64 字符（最长 48）。
- **兜底层**：临时移走本地安装后重跑，`launcher.log` 记录 `launch npx`，握手仍成功（16.8 s）。
- 行尾卫生：`git check-attr` 确认 `scripts/*.sh → text: set, eol: lf`，其余 `text: unset`。

### 已知限制

- macOS / Linux 只有脚本级验证（`bash -n`、`--dry-run` 全流程、假 `uname` 下的 apktool wrapper 行为、
  POSIX 探针命令在本机 `~/.rea` 安装上实跑），**没有在真实 macOS / Linux 桌面上做过端到端**。
- 仓库审计范围是 0.2.1-rc.2 → 0.2.2-rc.1；更早版本（0.2.1-rc.1 及以下）未审计，`engines.dsh` 已把它们挡住。
- `@modelcontextprotocol/client@2.2.0` 内部（连接超时、`cwd: ''` 处理）未读源码，属于未验证面。
- JEB / Hopper / macOS 专属 10 个操作等平台边界与 v1.3.0 相同，没有变化。

---

## v1.3.0 — 2026-10-21

**主题：补齐 Linux 专属分析线（WSL 2 + Linux 工具链 + 可选 Linux REA 实例）。**

REA 有一部分能力被平台门禁到 Linux（Windows 上调用会返回 `unsupported_host`）：
ELF 布局（pwntools）、崩溃 core、固件（binwalk / unblob）、原生 mitmproxy 抓包，以及
`.deb` / Linux 应用程序这类只能在 Linux 主机上打开的目标。这一版把这条线做成「一条命令准备 + 按需启用」。

### 新增

- **`scripts/setup-wsl-linux-toolchain.ps1`**（Windows 侧）：
  启用 WSL 可选功能 → 装 WSL2 内核 → 用 Ubuntu 24.04 base rootfs `wsl --import`
  （默认 `C:\wsl\Ubuntu-24.04`）→ 在发行版内运行工具链脚本。支持 `-DryRun`、
  `-Distribution`、`-InstallPath`、`-SkipFeatureCheck`。首次启用 WSL 需重启一次，脚本会提示再跑一次。
- **`scripts/linux-tools-setup.sh`**（WSL 内）：
  apt 基础包（`binutils file gdb xz-utils p7zip-full dpkg-dev` 等）+ Node.js 22（NodeSource）+
  pipx 安装 `pwntools`、`binwalk`、`unblob`、`mitmproxy`，并把版本记录到 `/root/rea-linux-tools.txt`。
- **`cordis.patch.yml` 新增被禁用的第二行 `rea-linux`**：
  `command: wsl.exe args: ['-d','Ubuntu-24.04','-u','root','--','npx','-y','rea-agents@6.4.0','mcp']`，
  `serverName: rea-linux`。默认 `disabled: true`（**字面量**，不涉及 `!!js`），准备好 WSL 后改成
  `false` 并重启，即可得到 `mcp__rea-linux__*`（约 170 个工具，token 成本翻倍，按需开）。
- **Windows 侧 `.deb` 拆包**：仓库文档记录用 7-Zip 独立版 `7zr.exe`（`C:\tools\7zip\7zr.exe`）
  解 `ar` 包：`7zr x pkg.deb` → `7zr x data.tar.xz` → 得到 ELF/资源；进一步的 ELF 反编译走 WSL 里的 REA。

### 变更

- `docs/CAPABILITIES.md` / `docs/SETUP.md` 增加“Linux 专属线（WSL）”章节。
- README 增加 Linux 路线说明与 v1.3.0 版本记录；`dsh.plugin.json` 版本同步。

### 状态

- 工具安装脚本已在本机写好并通过 `-DryRun` 与 PowerShell 5.1 语法校验；
- WSL 可选功能已启用（`Microsoft-Windows-Subsystem-Linux` / `VirtualMachinePlatform` 均为 Enabled），
  **需要重启一次**后 `wsl --import` 与工具链安装才能完成；用户要求“只完成工具、不测试”，故未跑功能验证。

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
