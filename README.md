<p align="center">
  <img src="icon.svg" alt="dsh-rea 图标：REA 逆向桥" width="96" height="96">
</p>

# dsh-rea

<p align="center">
  <a href="https://dshopen.org/zh/plugins/dsh-rea/"><img alt="开放插件市场 · 已收录" src="https://img.shields.io/endpoint?url=https%3A%2F%2Fdshopen.org%2Fbadge%2Fdsh-rea.json"></a>
  <a href="https://dpharness.com/plugin/Fanqi89/dsh-rea"><img alt="dsh install · 安装验证" src="https://dpharness.com/badge/install/Fanqi89/dsh-rea.svg"></a>
  <a href="https://github.com/AIshihzong/awesome-reverse-engineer-anything"><img alt="Featured in Awesome REA" src="https://img.shields.io/badge/Featured%20in-Awesome%20REA-f0b429"></a>
</p>

**REA（Reverse Engineer Anything）→ DeepSeek Harness 插件** · https://github.com/morluto/rea

一个 **configuration-only bundle**：不写一行插件代码，通过 DeepSeek Harness 自带的
`@deepseek-ai/dsh-mcp-client` 把本地 REA 的 stdio MCP 服务器接入 Harness。
接入后 REA 的全部工具（`open_binary`、`analyze_javascript_application`、
`inspect_managed_artifact`、反编译 / 伪代码 / 字符串 / 引用追踪等，rea-agents 6.9.0 实测 **255 个**）会以

```text
mcp__rea__<tool_name>
```

的形式注册给模型，配合已安装的 `reverse-engineer-anything` 技能即可开展逆向调查。

> **收录情况**：本插件已收录于 [开放插件市场 dshopen.org](https://dshopen.org/zh/plugins/dsh-rea/)
> （站点标注 `已审查`，并显示收藏数）、[dpharness.com](https://dpharness.com/plugin/Fanqi89/dsh-rea)
> （安装验证 L4 passed）与 [Awesome REA](https://github.com/AIshihzong/awesome-reverse-engineer-anything)
> 的「Plugins and integrations」条目。徽章显示各站点的实时数据（版本、收藏数、验证等级会随扫描更新），
> 点进去就是对应页面。

> **合规提示**：REA 仅用于你拥有或已获授权分析的软件（研究、教育、互操作性、软件保存）。
> 使用前请阅读上游 [DISCLAIMER.md](https://github.com/morluto/rea/blob/main/DISCLAIMER.md)。

## 文件结构

```text
dsh-rea/
├── package.json        # bundle 清单 + engines.dsh + 图标入口
├── cordis.patch.yml    # 插入 dsh-mcp-client 行（单行；平台差异在 Node 启动器里）
├── dsh.plugin.json     # DSH 插件注册表清单（id/version/engines.dsh/contributes）
├── .gitattributes      # 冻结行尾：*.sh 恒 LF，其余文件字节不变（JSON 无 BOM、.ps1 带 BOM）
├── icon.svg            # 插件卡片图标（64×64）
├── locale/en.json      # 插件卡片标题与描述
├── locale/zh.json
├── docs/
│   ├── CAPABILITIES.md    # 能反编译什么、还差什么、各平台边界
│   ├── SETUP.md           # Ghidra / JADX / apktool / adb / 浏览器 依赖配置（Windows）
│   ├── SETUP-POSIX.md     # macOS / Linux 同一件事的做法 + 环境变量可见性
│   └── COMPAT-VERSIONS.md # DSH 0.2.1-rc.2 → 0.2.2-rc.1 的逐版本兼容性审计（含证据）
├── scripts/
│   ├── setup-rea-tools.ps1  # Windows 一键配置（含 rea-agents 本地固定安装）
│   ├── setup-rea-tools.sh   # macOS / Linux 一键配置（bash 3.2 兼容）
│   ├── apktool-shim.cs      # Windows 上 apktool.exe 启动器模板
│   ├── setup-wsl-linux-toolchain.ps1  # WSL 2 + Linux 工具链（Linux 专属能力）
│   └── linux-tools-setup.sh           # WSL 内安装 pwntools/binwalk/unblob/mitmproxy
├── CHANGELOG.md        # 每个版本的变更说明
└── README.md
```

## 环境要求

| 项目 | 要求 |
|---|---|
| DeepSeek Harness | **≥ 0.2.1-rc.2**（`package.json` / `dsh.plugin.json` 的 `engines.dsh` 声明，DSH 用 `includePrerelease` 校验；低于此版本明确报 incompatible 而不是静默无工具）。0.2.1-rc.2 / rc.3 / rc.4 / rc.5 / 0.2.2-rc.1 已逐版本审计，见 [docs/COMPAT-VERSIONS.md](docs/COMPAT-VERSIONS.md)。仍在 0.2.0-rc.2 上的话请装 v1.3.0 |
| Node.js | **不需要**自己装：DSH 自带 Node 24.21.0，而 rea-agents **6.9.0** 要求 `^22.23.4 \|\| ^24.22.1 \|\| ≥26.12.1` —— 差一点点，REA 就会拒绝启动。所以 `scripts/setup-rea-tools.{ps1,sh}` 会往 `~/.rea/dsh/node` 放一份 **Node 24.22.3**（SHA-256 钉扎），启动器**优先用它**；没装也能跑：检测到 Node 太旧就自动回退到 `~/.rea/dsh/agents/6.7.0`（207 工具）并在 `launcher.log` 记 `fallback-from=6.9.0-node-too-old`。顺序：`REA_MCP_NODE` > `~/.rea/dsh/node` > Harness 自带；`REA_MCP_VERSION` 可显式锁版本（锁了就不回退）。走 `npx` 兜底层时才需要 PATH 上有可用的 `npx` |
| 网络 | 首次启动只经 `npx -y rea-agents@6.9.0` 兜底拉包；跑过 `scripts/setup-rea-tools.{ps1,sh}` 后走**本地固定安装**（`~/.rea/dsh/agents/6.9.0`），离线可用、冷启动更快 |
| 深度原生分析 | 需要本机已有的 Ghidra / IDA（Windows 无 Hopper）；Ghidra 需 `GHIDRA_INSTALL_DIR` |
| 静态 JS / .NET 分析 | 无需任何反汇编引擎 |
| APK 代码反编译 | 完整 JDK 17+（含 `jdk.compiler`）+ `jadx-headless-mcp 0.7.1` + `REA_JADX_MCP_JAR` |
| APK 资源解码 | apktool + `REA_APKTOOL_COMMAND` |
| Android 设备 | adb（platform-tools）+ `REA_ADB_PATH` |
| 浏览器 CDP | Chrome / Edge + `REA_BROWSER_EXECUTABLE` |
| **Linux 专属能力**（ELF 布局 / 崩溃 core / 固件 / mitmproxy / `.deb`） | WSL 2 + Ubuntu 24.04 + pwntools / binwalk / unblob / mitmproxy，由 `scripts/setup-wsl-linux-toolchain.ps1` 准备，再启用补丁里的 `rea-linux` 行 |
| 调查工作流技能 | `npx skills add morluto/rea --skill reverse-engineer-anything`，或 `npx -y rea-agents@6.9.0 setup --skill --yes`（装与包版本一致的技能） |

> 后四项都用一条命令补齐（Windows）：
> `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-rea-tools.ps1 -WithApktool`
> macOS / Linux 用 `bash scripts/setup-rea-tools.sh`（可先加 `--dry-run` 只看计划）。
> 详细步骤见 [docs/SETUP.md](docs/SETUP.md)（Windows）与 [docs/SETUP-POSIX.md](docs/SETUP-POSIX.md)（macOS/Linux），
> 能力边界见 [docs/CAPABILITIES.md](docs/CAPABILITIES.md)。

## 安装

方式零（从 GitHub 直接装，推荐给其他人）：

```powershell
dsh plugin --profile "$env:DSH_PROFILE" add github:Fanqi89/dsh-rea
```

方式一（推荐，UI）：**设置 → 插件 → 安装 bundle**，选择本目录的绝对路径。

方式二（本地 CLI）：

```powershell
dsh plugin --profile "$env:DSH_PROFILE" add "X:\path\to\dsh-rea"
```

`install_bundle` 会自动完成 profile 的 `package.json` / `cordis.patch.yml` 修改与依赖安装，
**不要**手工编辑 profile 文件。装完后重载/重启 Harness 使工具生效。

## 图形开关（可选，推荐）：配合 `dsh-rea-toggle`

> **上游来源与作者**：开关是第三方插件 **`dsh-rea-toggle`** ——
> 上游仓库 **<https://github.com/phoushen/dsh-rea-toggle>**，作者 **phoushen**，
> 许可 **MIT**（`Copyright (c) 2026 phoushen`），本插件接入的是上游 **v1.0.0**。
> dsh-rea **不包含它的任何代码**（不 vendor / 不 fork / 不打 patch），只负责接线、脚本与文档；
> 完整核对表见 [docs/TOGGLE.md](docs/TOGGLE.md) 第 9 节。

REA 的 255 个工具在**每一轮请求**里都要带 schema。实测（rea-agents 6.9.0、Node 24.22.3、默认 compact）：
工具名 + 描述 **128,880 字符 ≈ 3.7 万 token**，inputSchema 另 **186,256 B ≈ 5.3 万 token** ——
也就是一轮请求里约 **9 万 token 量级**的工具面。做逆向时这笔开销很值，写脚本、聊天时就是死重。

上游插件 [`phoushen/dsh-rea-toggle`](https://github.com/phoushen/dsh-rea-toggle)（作者 phoushen，MIT）
在输入框下方加一枚 `REA ON / REA OFF` 开关，翻的就是我们这行 `rea-mcp` 的 `disabled` 标志：

```powershell
# 1) 装开关插件
dsh plugin --profile "$env:DSH_PROFILE" add github:phoushen/dsh-rea-toggle

# 2) 给开关一个抓手：它只改写 profile patch，而 rea-mcp 这一行是 dsh-rea 的 bundle 层插入的，
#    所以要在 <DSH_HOME>/profiles/<profile>/cordis.patch.yml 里放一个按 id 覆盖的条目
#    （下面这条等价于跑 scripts/setup-rea-tools.ps1 -WithToggle / setup-rea-tools.sh --with-toggle）
# - id: rea-mcp
#   disabled: false

# 3) 完全退出 DeepSeek Harness（含托盘）再开 —— 客户端 chunk 只在启动时扫描
```

开关**立刻写盘**，工具集合在**下次启动**才变（关了就是 0 个工具、0 开销）。细节、端点、排错与
撤销方法见 **[docs/TOGGLE.md](docs/TOGGLE.md)**。

> 为什么需要第 2 步：开关的实现只读 `<DSH_HOME>/profiles/<profile>/cordis.patch.yml`，
> 找不到 `- id: rea-mcp` 就显示 `REA ?`。这是上游插件的设计（它假设 REA 行写在 profile patch 里），
> 我们不改它的代码，只补上这行覆盖；删掉这行即"解除开关"，REA 恢复为常开。
> 另外它按 `DSH_PROFILE` 找 profile（未设时默认 `desktop`）——profile 不叫 `desktop` 时请设该变量。


## 反编译能力全览

装好外部依赖后，这套组合可以覆盖「从网页到二进制、从 APK 到固件」的全部静态 / 被动运行时分析。
完整矩阵（含本机实测证据）见 **[docs/CAPABILITIES.md](docs/CAPABILITIES.md)**，摘要：

| 目标 | 能拿到什么 | 依赖 |
|---|---|---|
| 原生二进制（exe/dll/elf/macho） | 伪代码、汇编、函数清单、xref、调用图、字符串/名称搜索、DWARF 类型 | Ghidra / IDA / Hopper |
| **APK 代码** | 包信息、AndroidManifest、类清单、**方法级 Java 源码**、smali 回退、引用追踪（含 DEX invoke 偏移） | JDK + JADX |
| APK 资源 | 资源表、资源解码 | apktool |
| Android 设备 | 设备/包/进程/日志/截图、装拉 APK | adb |
| JS / Electron / ASAR | 模块图、导入关系、路由、IPC、source map、版本对比 | 无 |
| .NET (PE/CLI) | 元数据、CIL 指令、成员签名、原生边界声明 | 无 |
| 打包文件 | ZIP/APK/IPA/MSIX/AppX/DMG 清单与摘要、解包 | 无 |
| 网站 / 浏览器 | 页面结构、脚本、网络观测、截图、场景回放 | Chrome / Edge |
| 进程行为 | 终端输出、交互、退出码、文件系统观测与对比 | Linux/macOS |
| 固件 / ELF / core | 签名区域、解包、布局、崩溃寄存器 | Linux 工具链 |
| 证据包 | 导出/导入/比对/重建义务清单/残差未知 | 无 |

## Linux 专属能力（ELF / 固件 / `.deb` / mitmproxy）

REA 有 6 类能力在 Windows 上会被明确拒绝（`unsupported_host`）：ELF 布局（pwntools）、崩溃 core、
固件（binwalk/unblob）、原生 mitmproxy 抓包、进程捕获（PTY）、历史源码导入；`.deb` / Linux 应用
目标也只能在 Linux 主机上直接打开。本插件用「**WSL 2 里跑第二个 REA 实例**」补齐：

```powershell
# 1) 准备 WSL 2 + Ubuntu 24.04 + 工具链（首次启用 WSL 需重启一次，重启后再跑一遍）
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-wsl-linux-toolchain.ps1

# 2) 把 cordis.patch.yml 里 rea-linux 那行的 disabled: true 改成 false，然后重启 Harness
```

启用后这些工具以 `mcp__rea-linux__*` 出现（约 255 个，token 成本翻倍，建议仅在需要时开）。
WSL 内会装好：`pwntools`、`binwalk`、`unblob`、`mitmproxy`、`gdb`、`binutils`、`xz`、`Node.js 24.22.3`、`rea-agents 6.9.0`。

> 只想先拆 `.deb` 不装 WSL：用 7-Zip 独立版即可（`C:\tools\7zip\7zr.exe x pkg.deb` → `7zr x data.tar.xz`），
> 但 ELF 的反编译仍需 Linux 实例。

## 验证

安装成功后，向 Agent 提一句例如「列出你的 mcp__rea__ 工具」，或直接调用
`mcp__rea__binary_session`（输入 `{}`）查看 `result.tool_availability`。
REA 服务端自身冷启动约 **1–15 秒**（6.9.0 实测：自带 Node 24.22.3 + 本地固定安装 **~1.1 s**；6.7.0 走 Harness 自带 Node 是 3.1–7.6 s；npx 冷/热 14.3–16.8 s），
这段时间里工具还没注册，属正常，等它连上或触发一次 reconnect 即可。

本机实测（2026-10-12/21/11-07，DSH 0.2.0-rc.2 → 0.2.1-rc.5 + rea-agents 6.9.0 + Windows）：

- `plugin_manager install_bundle` → `application: applied`；
- `cordis_inspect_query Tool.listTools` 确认 **255 个 `mcp__rea__*` 工具**已注册在线；
- stdio 握手实测：启动器拉起的 `rea mcp` →
  `initialize` 返回 `rea@6.9.0`，`tools/list` 返回 255 个工具；
- 补丁合入验证：在**独立的 `DSH_HOME`** 里建临时 profile（`bundles: [dsh-base, dsh-web-app, dsh-rea]`），
  `dsh --profile probe --dump-config` 能看到 `# == dsh-rea` 层贡献的 `rea-mcp` 行
  （`command: !!js process.execPath` + `args: ['-e', …]`）与默认禁用的 `rea-linux` 行，stderr 无告警；
- **端到端**：`dsh --profile probe --no-open --port 46124` 真启动一个 Harness 宿主 → 进程树实测为
  `DeepSeek Harness.exe`（cli host）→ `DeepSeek Harness.exe -e "<启动器>"` → `DeepSeek Harness.exe …/rea.mjs mcp`，
  `~/.rea/dsh/launcher.log` 记录 `launch local-install`，服务进程保持存活（连接成功才会保留），无 stderr 告警；
- **配置 schema**：两条 row 用真实 `dsh-mcp-client` Config（schemastery 3.18.5 / 3.19.0 各跑一遍）校验通过，
  `reconnect` 解析为 `{enabled:true, initialDelayMs:500, maxDelayMs:60000, maxAttempts:60}`；
- **原生反编译**：Ghidra 12.1.4 分析 `notepad.exe` → 9 段 / 794 函数 / 557 字符串；
  `entry` 函数返回伪代码 + 反汇编 + 调用关系；
- **APK 代码**：JADX 0.7.1 解出 `com.llw` 包信息、`MainActivity.onCreate` 完整 Java 源码；
- **APK 资源**：apktool 3.0.3 解出完整 Manifest、字符串表、14 个解码文件；
- **Android 设备**：`inspect_adb_client` 识别 adb 37.0.1；
- **DSH 适配**（v1.2.0）：`plugin_manager list_bundles` 显示 `dsh-rea v1.2.0`、`enabled: true`、
  **无 incompatible 标记**（peer `@deepseek-ai/dsh-mcp-client >= 0.2.0-rc.2` 对运行时 0.2.0-rc.2 校验通过），
  组件仍为单行 `rea-mcp`；
- GitHub 源码安装路径实测：`pnpm add github:Fanqi89/dsh-rea#v1.2.0` → 装出 `dsh-rea@1.2.0`。

> 已知边界：Windows（桌面版 + 无头 CLI 宿主）已端到端验证；macOS / Linux 走同一启动器里的 POSIX 分支
> （`detached` + 进程组 `SIGTERM`→`SIGKILL`，`npx` 兜底），逻辑同构，并有 `scripts/setup-rea-tools.sh`
> 的 dry-run / `bash -n` / 假 uname 行为测试，但**没有在真实 macOS 或 Linux 桌面上跑过端到端**。

## 配置项（`cordis.patch.yml`）

**只插入一个 `dsh-mcp-client` 行**（`id: rea-mcp`，`serverName: rea`），
`command: !!js process.execPath`、`args: ['-e', <启动器>]`。`!!js` 表达式由 Loader 在激活时求值，
得到 Harness 自己的运行时可执行文件（桌面版即 Electron 二进制 + `env.ELECTRON_RUN_AS_NODE=1`，
npm/CLI 安装则是 node 本身），所以不依赖用户 PATH 上的 `node`/`npx`——这正是 macOS 从 Finder 启动、
以及 Windows 没装 Node 时最容易断的一环。

> **为什么用 `process.execPath` 而不是 `node`？** 三个理由：① PATH 上可能没有 node（macOS Dock 启动的
> app 环境变量极简）；② 即使有也可能是 Node 18/20，而 REA 要求 `^22.19 || ^24.11 || >=26`，版本不够是
> 静默失败；③ DSH 自带的 Node 一定满足要求（实测 Electron 44.7.0 as Node 24.21.0），并且它加载 REA 的原生
> `@lydell/node-pty`（N-API，ABI 稳定）与完整 MCP 握手都已实测通过。DSH 自己的无头启动器
> `resources/runtime/cli/bin/dsh.cmd` 用的就是同一机制，所以 `ELECTRON_RUN_AS_NODE` 一定可用。

启动器（~1.9 KB 的 Node 脚本）按顺序解析 REA 服务器入口：

| 层 | 位置 | 需要什么 |
|---|---|---|
| 1 | `$REA_MCP_ENTRY` | 你自己指定的入口文件（`…/scripts/rea.mjs`） |
| 2 | `$REA_MCP_HOME/agents/<ver>/node_modules/rea-agents/scripts/rea.mjs`，默认 `~/.rea/dsh`、`6.9.0` | 跑过一次 `setup-rea-tools.{ps1,sh}`：离线、无需 npm/npx、冷启动更快 |
| 3 | `npx -y rea-agents@<ver> mcp` | 网络 + PATH 上有可用的 `npx`（Windows 经 `cmd.exe /d /s /c`） |

命中哪一层、用的什么命令、子进程怎么退出，都会追加到 **`~/.rea/dsh/launcher.log`**（上限 64 KiB）——
排查「工具没出现」时先看这个文件。`stdio: 'inherit'` 让 MCP 字节流直通；
Harness 关闭时 Windows 用 `taskkill /T /F`、POSIX 用进程组 `SIGTERM`（1.2 s 后 `SIGKILL`）清理整棵子进程树。

> **为什么不是"两行 + `disabled: !!js`"？** 单行的真实理由是**同一作用域内 `serverName` 只能注册一次**：
> 两条都叫 `rea` 的行只要有两条同时激活就会撞车。v1.0.0 曾靠 `disabled: !!js process.platform …` 二选一，
> 在部分较旧构建上被判成「共 2 个组件 · 1 运行中 · 1 异常」。顺带说明：在 **DSH ≥ 0.2.1-rc.2** 上
> `!!js` 出现在 `disabled` 与 patch `config` 值里都是官方支持的（app-boot 的 entry-list schema 明确写了
> `boolean|null|loaderExpression`），所以现在不需要再为它绕路——单行只是为了身份唯一。

可调字段：

| 字段 | 当前值 | 说明 |
|---|---|---|
| `command` | `!!js process.execPath` | 用 Harness 自带的 Node（桌面版是 Electron + `ELECTRON_RUN_AS_NODE=1`），不依赖 PATH |
| `env.ELECTRON_RUN_AS_NODE` | `1` | 缺了它，Electron 子进程会**再开一个 Harness 窗口**而不是执行脚本 |
| `env.REA_MCP_INPUT_SCHEMA_PROFILE` | `compact` | **token 成本开关**。本机对 **6.9.0（255 工具，Node 24.22.3）** 实测：inputSchema 合计 **compact 186,256 B / full 1,021,510 B**（工具描述另 123,790 B），粗估每轮 **5.3 万 vs 29 万** token 的差别。**6.9.0 起 compact 已是 REA 自己的默认**，这里显式写死以免上游改默认 |
| `toolCallTimeoutMs` | `1200000`（20 分钟） | 单次 `tools/call` 上限。Ghidra 首查默认 330 s 启动预算，故高于默认 60 s |
| `failOnStartupError` | `false` | `false`：REA 起不来时 Harness 照常启动、只是没有 REA 工具（激活会 `await` 首连且**没有内部超时**，所以这一项必须是 `false`）；`true` 便于排查但会把 3–15 s 冷启动抖动变成启动失败 |
| `reconnect` | `maxAttempts: 60`、`maxDelayMs: 60000` | 默认只有 10 次 / 30 s 上限（约 2 分钟就放弃并**注销工具**）。放宽到约 1 小时，覆盖「先开 Harness、后连网 / 后启 WSL / 本地安装还没装完」这类顺序问题。**只写这四个官方子键**（`enabled/initialDelayMs/maxDelayMs/maxAttempts`）——写了未知子键会让整行加载失败 |
| `maxInstructionBytes` | 不设置（= 默认 32768） | REA 6.9.0 的 instructions 实测 **2,604 B**（含归属头 2,625 B），默认上限仍有 12 倍余量；注意超限不是截断而是**判成连接失败并重试**，即整个服务器消失 |
| `REA_MCP_VERSION`（环境变量） | 不设置（= `6.9.0`） | 启动器第 2/3 层共用的版本号；**显式设置时不再自动回退**（锁什么就是什么），第 2 层要按新版本号重新安装 |
| `REA_MCP_NODE`（环境变量） | 不设置（= 用 Harness 自带 Node） | 指定第 2 层用哪个 node 可执行文件。**只有想跑 REA 6.8.0+ 时才需要**：从 6.8.0 起 REA 要求 Node `^22.23.4 \|\| ^24.22.1 \|\| >=26.12.1`，而本机 Harness 自带的是 24.21.0，会被 REA 直接拒绝启动（实测报 `REA requires Node.js … this process runs Node.js 24.21.0`）。有 ≥24.22.1 的 Node 时设 `REA_MCP_NODE` + `REA_MCP_VERSION=6.9.0` 即可 |

修改补丁后需要重启 Harness 生效；**不要**为同一服务器再复制第二个条目
（同 `serverName` 的第二条会加载失败）。

## 升级 / 版本历史

完整的「每个版本做了什么、修了什么、怎么验证」见 **[CHANGELOG.md](CHANGELOG.md)**；摘要：

- **v1.6.0**（当前）：跟上上游 **rea-agents 6.9.0**（工具 **207 → 255 个**，+48，无删除）——
  但 6.9.0 要求 Node `^22.23.4 || ^24.22.1 || >=26.12.1`，而 Harness 自带 **24.21.0**，
  所以本版**自带一份 Node 24.22.3**（`~/.rea/dsh/node`，SHA-256 钉扎；setup 脚本第 1c / 8c 步），
  启动器优先用它；没有这份 Node 时**自动回退到 6.7.0**（207 工具）并在 `launcher.log` 记录
  `fallback-from=6.9.0-node-too-old`，不会让老环境丢工具。实测：`initialize` **1.1 s**、
  `tools/list` **255**、`instructions` **2,604 B**、默认 compact inputSchema **186,256 B**（full 1,021,510 B）。
  工具可用 `REA_MCP_NODE` / `REA_MCP_VERSION` 覆盖。
- **v1.5.2**：把上游开关插件 **`dsh-rea-toggle`** 的来源与作者写清楚——
  上游仓库 <https://github.com/phoushen/dsh-rea-toggle>、作者 **phoushen**、MIT（`Copyright (c) 2026 phoushen`）、
  接入版本 **v1.0.0**，dsh-rea **不含其代码**；README / [docs/TOGGLE.md](docs/TOGGLE.md) / 补丁注释三处标注。
  **运行时与 v1.5.1 完全一致**。
- **v1.5.1**：接入图形开关 [`phoushen/dsh-rea-toggle`](https://github.com/phoushen/dsh-rea-toggle)
  （MIT，独立插件）——输入框下方一枚 `REA ON/OFF`，关掉就是 0 个工具、不再付每轮约 5 万 token 的
  工具面开销。dsh-rea 这边补上它缺的那一环：`rea-mcp` 行来自 bundle 层，开关只改用户 patch 层，
  所以要有 `- id: rea-mcp` 覆盖条目（新增 `-WithToggle` / `--with-toggle` 一键写、会备份并回读校验）。
  新增 [docs/TOGGLE.md](docs/TOGGLE.md)。**不含上游代码**，运行时与 v1.5.0 一致。
- **v1.5.0**：上游 REA 跟进到 **rea-agents 6.7.0**（工具 **170 → 207 个**，+37，无删除）——
  新增动态分析线（Frida 10 个工具、GDB 4 个、rizin/cutter 6 个）与一批静态检查器
  （Go / Rust / WASM / SQLite / PCAP & 抓包 / 信号解码 / Dart AOT & Flutter / Harmony 应用图 /
  Electron hardened fuses / objdump / `search_bytes` / `compare_wasm_interfaces`）。
  上游最新是 6.9.0，但 **6.8.0 起把 Node 下限提到 `^24.22.1`**，Harness 自带 24.21.0 会被 REA 直接拒绝
  （实测报 `REA requires Node.js … this process runs Node.js 24.21.0`），所以钉在**能跑的最新版 6.7.0**；
  想跑 6.8/6.9 可设 `REA_MCP_NODE` 指向 ≥24.22.1 的 node 再设 `REA_MCP_VERSION`。
  同步更新了补丁里的版本号、`rea-linux` 行、Windows/macOS/Linux 三个配置脚本的固定安装版本。
- **v1.4.1**：文档层小版本——README 顶部加上仓库图标 `icon.svg`（96×96）、三个
  **收录徽章**（开放插件市场 dshopen.org 的「已收录 · ♥ N」实时徽章、dpharness.com 的安装验证徽章、
  Awesome REA 的 Featured 徽章，逐个 curl 验过 200 且链接指向对应页面）、新增「收录情况」小节；
  处理 issue #1（Awesome REA 条目核对无误，已回复并关闭）。**运行时与 v1.4.0 完全一致**
  （补丁 / 启动器 / 脚本逐字节相同），只是版本号与文档更新。
- **v1.4.0**：跨版本 / 跨平台稳定性版本——
  ① 启动器改为 `command: !!js process.execPath` + `ELECTRON_RUN_AS_NODE=1`，用 Harness 自带 Node，
  不再依赖 PATH 上的 `node`/`npx`（修 macOS Finder 启动、Windows 无 Node、PATH 上是 Node 18/20 三种静默失败）；
  ② 三层入口解析（`$REA_MCP_ENTRY` → `~/.rea/dsh` 本地固定安装 → `npx` 兜底），本地层离线可用、启动从
  16.8 s 降到 ~4.9–6.9 s；③ `~/.rea/dsh/launcher.log` 诊断日志（解析到了哪一层、退出码）；
  ④ `reconnect` 放宽到 60 次 / 60 s 上限（默认 2 分钟就注销工具）；⑤ `engines.dsh` 显式声明 `>=0.2.1-rc.2`
  并与 `peerDependencies` 解耦（此前 peer 会被当成 DSH 版本约束）；⑥ 新增 macOS/Linux 一键脚本
  `scripts/setup-rea-tools.sh` 与 [docs/SETUP-POSIX.md](docs/SETUP-POSIX.md)；⑦ 新增
  [docs/COMPAT-VERSIONS.md](docs/COMPAT-VERSIONS.md)（0.2.1-rc.2 → 0.2.2-rc.1 逐版本审计：mcp-client 配置面
  逐字节相同、`!!js` 全版本可用、semver 依赖 `includePrerelease`）；⑧ `.gitattributes` 冻结行尾
  （防止 Windows 上 CRLF 检出把 `.sh` 弄坏）。
- **v1.3.0**：补齐 Linux 专属线——`scripts/setup-wsl-linux-toolchain.ps1`（WSL 2 + Ubuntu 24.04 +
  pwntools/binwalk/unblob/mitmproxy/Node 22）、`scripts/linux-tools-setup.sh`，并在补丁里新增默认禁用的
  `rea-linux` 行（`wsl.exe -d Ubuntu-24.04 … npx rea-agents@6.7.0 mcp`），按需开启即可获得
  `mcp__rea-linux__*`（ELF 布局 / 崩溃 core / 固件 / `.deb` / mitmproxy / PTY 捕获）。
- **v1.2.0**：按 DSH 插件规范适配——`peerDependencies` 声明 `@deepseek-ai/dsh-mcp-client >= 0.2.0-rc.2`
  （DSH 加载时校验，旧版本明确报 `incompatible-version`）、新增 `dsh.plugin.json` 注册表清单、
  `icon.svg` 插件卡片图标、`keywords`。桥接补丁与 v1.1.0 相同。
- **v1.1.0**：补齐「可反编译一切」的依赖链路文档与工具——`docs/CAPABILITIES.md`、
  `docs/SETUP.md`、`scripts/setup-rea-tools.ps1`（Ghidra / JADX / apktool / adb / 浏览器，SHA-256 钉扎）、
  `scripts/apktool-shim.cs`（Windows 上 apktool 的 exe 启动器）；修复 `package.json` 的 UTF-8 BOM
  （会让 `dsh plugin add github:…` 全部安装失败）。
- **v1.0.1**：单行 + Node 启动器；修复旧构建下第二条平台行显示「异常」的问题。
- **v1.0.0**：双行 + `disabled: !!js`（在较旧 Harness 上可能出现 1 运行中 / 1 异常）。

十一个标签可共存、互不冲突；任意版本都能按标签锁装：

```powershell
dsh plugin --profile "$env:DSH_PROFILE" add github:Fanqi89/dsh-rea#v1.6.0   # 最新（REA 6.9.0，255 工具，自带 Node 24.22.3）
dsh plugin --profile "$env:DSH_PROFILE" add github:Fanqi89/dsh-rea#v1.5.2   # 上游开关来源/作者标注
dsh plugin --profile "$env:DSH_PROFILE" add github:Fanqi89/dsh-rea#v1.5.1   # 图形开关接线 + 文档
dsh plugin --profile "$env:DSH_PROFILE" add github:Fanqi89/dsh-rea#v1.5.0   # REA 6.7.0，207 工具
dsh plugin --profile "$env:DSH_PROFILE" add github:Fanqi89/dsh-rea#v1.4.1   # 文档/徽章；运行时同 v1.4.0（REA 6.4.0，170 工具）
dsh plugin --profile "$env:DSH_PROFILE" add github:Fanqi89/dsh-rea#v1.4.0   # 跨版本/跨平台稳定性
dsh plugin --profile "$env:DSH_PROFILE" add github:Fanqi89/dsh-rea#v1.3.0   # Linux 路线（WSL 2）
dsh plugin --profile "$env:DSH_PROFILE" add github:Fanqi89/dsh-rea#v1.2.0   # DSH 适配层（0.2.0-rc.2 可用）
dsh plugin --profile "$env:DSH_PROFILE" add github:Fanqi89/dsh-rea#v1.1.0   # 能力层文档
dsh plugin --profile "$env:DSH_PROFILE" add github:Fanqi89/dsh-rea#v1.0.1   # 纯桥接，无 peer 声明（旧版 Harness 可用）
dsh plugin --profile "$env:DSH_PROFILE" add github:Fanqi89/dsh-rea#v1.0.0   # 旧行为（不推荐）
```

从 v1.0.0 升级：`install_bundle` 对**同一路径/同一 spec** 重复安装会返回
`ambiguous-install`（它靠"安装前后依赖差异"识别装了什么，同 spec 重装没有差异）。
因此升级按"先卸载再装"走：

1. 在**设置 → 插件**里卸载 `dsh-rea`（或让 Agent 调 `plugin_manager` 的 `remove_bundle`）；
2. 再装新版本：`dsh plugin --profile "$env:DSH_PROFILE" add github:Fanqi89/dsh-rea#v1.0.1`，
   或 UI 里「安装 bundle」选新目录；
3. **重启 Harness** —— 补丁只在启动时合入，不重启仍是旧配置。

## 卸载 / 临时禁用

- 禁用：设置 → 插件中关闭本 bundle（或 `plugin_manager` 的 `set_bundle enabled: false`）。
- 移除：`plugin_manager` 的 `remove_bundle`，或 CLI `dsh plugin --profile <name> remove dsh-rea`。

本插件不改动任何客户端配置文件，卸载即净。

## 工作原理

```text
Harness 启动
  └─ loader 应用 bundle 补丁 cordis.patch.yml
       └─ 插入 @deepseek-ai/dsh-mcp-client 行
            └─ command: !!js process.execPath  args: ['-e', <启动器>]
                 └─ 启动器解析入口（launch.log 记录命中的层）
                      ├─ 1. $REA_MCP_ENTRY
                      ├─ 2. ~/.rea/dsh/agents/6.9.0/…/scripts/rea.mjs   （本地固定安装，离线）
                      │     └─ 用 ~/.rea/dsh/node/node.exe（Node 24.22.3；缺失且宿主 Node < 24.22.1 时回退 6.7.0）
                      └─ 3. npx -y rea-agents@6.9.0 mcp                  （兜底，Windows 经 cmd.exe）
                           └─ MCP 握手 + tools/list（6.9.0 实测 255 个工具）
                                └─ 注册为 ctx.tools：mcp__rea__open_binary、mcp__rea__analyze_function、…
```

选型依据来自 Harness 官方 `cordis-plugin-development` 技能的
「Connect an MCP server through a configuration-only bundle」路线，以及 REA 上游文档对
DeepSeek Harness 的官方接入说明（`rea setup --client dsh` 写入的正是同款
`dsh-mcp-client` stdio 条目；rea-agents 6.9.0 的 `rea mcp --help` 仍只有 `add`/`doctor`（无 `--client dsh`），故本插件手工内联了等价配置）。

## 故障排查

1. **没有 `mcp__rea__*` 工具**：先看 **`~/.rea/dsh/launcher.log`** 最后几行——它会写明命中了哪一层、
   用的命令和子进程退出码。`launch local-install` 但没工具 → REA 自己在启动时报错，手动跑
   `node "~/.rea/dsh/agents/6.9.0/node_modules/rea-agents/scripts/rea.mjs" mcp` 看 stderr；
   `launch npx` 且后面没有 exit 行 → npx 层在等网络（跑一次 setup 脚本装本地层即可离线）；
   完全没有新行 → 补丁没合入（要重启 Harness）。
2. **插件面板显示「共 2 个组件 · 1 运行中 · 1 异常」**：这是 v1.0.0 的双行补丁在部分
   Harness 构建上的残留（`disabled: !!js` 没被正确识别 → 第二条同 `serverName` 的行
   激活失败）。升级到 v1.0.1（单行 + 启动器）并**重启**即可；升级方式见上面「升级 / 版本历史」。
3. **首启超时 / 每次启动都慢十几秒**：跑 `setup-rea-tools.{ps1,sh}` 装本地层（离线 + 快），
   或在 `launcher.log` 里确认命中的是不是 `npx` 层。`failOnStartupError` 保持 `false`：
   激活会等首连且没有内部超时，设成 `true` 只会把冷启动抖动变成 Harness 启动失败。
4. **原生分析报 provider 缺失**：静态 JS/.NET 不需要引擎；原生需 Hopper/Ghidra/IDA，
   用 `npx -y rea-agents@6.9.0 doctor --json` 诊断（`rea doctor` 同理）。
5. **token 消耗过高**：确认 `env.REA_MCP_INPUT_SCHEMA_PROFILE: compact` 在配置里；
   仍嫌大就仅在逆向会话启用本插件。
6. **重装同一路径报 `ambiguous-install`**：属于预期——先卸载再安装（见上）。

## License

MIT。REA 本体 © morluto（MIT），第三方工具（Hopper/Ghidra/IDA/JEB 等）遵循各自许可。
