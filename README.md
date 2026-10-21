# dsh-rea

**REA（Reverse Engineer Anything）→ DeepSeek Harness 插件** · https://github.com/morluto/rea

一个 **configuration-only bundle**：不写一行插件代码，通过 DeepSeek Harness 自带的
`@deepseek-ai/dsh-mcp-client` 把本地 REA 的 stdio MCP 服务器接入 Harness。
接入后 REA 的全部工具（`open_binary`、`analyze_javascript_application`、
`inspect_managed_artifact`、反编译 / 伪代码 / 字符串 / 引用追踪等，rea-agents 6.4.0 实测 **170 个**）会以

```text
mcp__rea__<tool_name>
```

的形式注册给模型，配合已安装的 `reverse-engineer-anything` 技能即可开展逆向调查。

> **合规提示**：REA 仅用于你拥有或已获授权分析的软件（研究、教育、互操作性、软件保存）。
> 使用前请阅读上游 [DISCLAIMER.md](https://github.com/morluto/rea/blob/main/DISCLAIMER.md)。

## 文件结构

```text
dsh-rea/
├── package.json        # bundle 清单 + DSH peer 兼容性声明 + 图标入口
├── cordis.patch.yml    # 插入 dsh-mcp-client 行（单行；平台在 Node 启动器里选择）
├── dsh.plugin.json     # DSH 插件注册表清单（id/version/engines.dsh/contributes）
├── icon.svg            # 插件卡片图标（64×64）
├── locale/en.json      # 插件卡片标题与描述
├── locale/zh.json
├── docs/
│   ├── CAPABILITIES.md # 能反编译什么、还差什么、各平台边界
│   └── SETUP.md        # Ghidra / JADX / apktool / adb / 浏览器 依赖配置
├── scripts/
│   ├── setup-rea-tools.ps1  # Windows 一键配置可选依赖
│   └── apktool-shim.cs      # Windows 上 apktool.exe 启动器模板
├── CHANGELOG.md        # 每个版本的变更说明
└── README.md
```

## 环境要求

| 项目 | 要求 |
|---|---|
| DeepSeek Harness | **≥ 0.2.0-rc.2**（`peerDependencies` + `dsh.plugin.json` 的 `engines.dsh` 声明；DSH 会做运行时校验，低于此版本明确报 `incompatible-version` 而不是静默无工具）。0.2.0-rc.2 实测通过 |
| Node.js | 22.x (≥22.19)、24.x (≥24.11) 或 26+，且 `npx` 可用（REA 官方要求）；缺 Node 时 Harness 照常启动，但不会出现 `mcp__rea__*` 工具 |
| 网络 | 首次启动经 `npx -y rea-agents@6.4.0` 拉取 npm 包（之后走 npx 缓存） |
| 深度原生分析 | 需要本机已有的 Ghidra / IDA（Windows 无 Hopper）；Ghidra 需 `GHIDRA_INSTALL_DIR` |
| 静态 JS / .NET 分析 | 无需任何反汇编引擎 |
| APK 代码反编译 | 完整 JDK 17+（含 `jdk.compiler`）+ `jadx-headless-mcp 0.7.1` + `REA_JADX_MCP_JAR` |
| APK 资源解码 | apktool + `REA_APKTOOL_COMMAND` |
| Android 设备 | adb（platform-tools）+ `REA_ADB_PATH` |
| 浏览器 CDP | Chrome / Edge + `REA_BROWSER_EXECUTABLE` |
| 调查工作流技能 | `npx skills add morluto/rea --skill reverse-engineer-anything`，或 `npx -y rea-agents@6.4.0 setup --skill --yes`（装与包版本一致的技能） |

> 后四项都用一条命令补齐（Windows）：`powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-rea-tools.ps1 -WithApktool`
> 详细步骤见 [docs/SETUP.md](docs/SETUP.md)，能力边界见 [docs/CAPABILITIES.md](docs/CAPABILITIES.md)。

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

## 验证

安装成功后，向 Agent 提一句例如「列出你的 mcp__rea__ 工具」，或直接调用
`mcp__rea__binary_session`（输入 `{}`）查看 `result.tool_availability`。
REA 服务器首次冷启动要跑 npx 下载，若几秒内没出工具属正常，稍等重试。

本机实测（2026-10-12/21，DSH 0.2.0-rc.2 + rea-agents 6.4.0 + Windows）：

- `plugin_manager install_bundle` → `application: applied`；
- `cordis_inspect_query Tool.listTools` 确认 **170 个 `mcp__rea__*` 工具**已注册在线；
- stdio 握手实测：启动器拉起的 `rea mcp` →
  `initialize` 返回 `rea@6.4.0`，`tools/list` 返回 170 个工具；
- 补丁合入验证：`dsh --profile <临时 profile> --patch ./cordis.patch.yml --dump-config`
  能看到 `rea-mcp` 行（`command: node` + `args: ['-e', …]`）正确合成；
- **原生反编译**：Ghidra 12.1.4 分析 `notepad.exe` → 9 段 / 794 函数 / 557 字符串；
  `entry` 函数返回伪代码 + 反汇编 + 调用关系；
- **APK 代码**：JADX 0.7.1 解出 `com.llw` 包信息、`MainActivity.onCreate` 完整 Java 源码；
- **APK 资源**：apktool 3.0.3 解出完整 Manifest、字符串表、14 个解码文件；
- **Android 设备**：`inspect_adb_client` 识别 adb 37.0.1；
- **DSH 适配**（v1.2.0）：`plugin_manager list_bundles` 显示 `dsh-rea v1.2.0`、`enabled: true`、
  **无 incompatible 标记**（peer `@deepseek-ai/dsh-mcp-client >= 0.2.0-rc.2` 对运行时 0.2.0-rc.2 校验通过），
  组件仍为单行 `rea-mcp`；
- GitHub 源码安装路径实测：`pnpm add github:Fanqi89/dsh-rea#v1.2.0` → 装出 `dsh-rea@1.2.0`。

> 已知边界：Windows 路径已端到端验证；macOS / Linux 走同一启动器里的 POSIX 分支
> （`npx` 直启），逻辑同构但未在真实机器上端到端验证过。

## 配置项（`cordis.patch.yml`）

**只插入一个 `dsh-mcp-client` 行**（`id: rea-mcp`，`serverName: rea`），`command: node`
`args: ['-e', <启动器>]`。启动器是一行 ~600 字节的 Node 脚本，在进程内判断
`process.platform`：Windows 用 `cmd.exe /d /c npx … mcp`，POSIX 用 `npx … mcp`，
`stdio: 'inherit'` 让 MCP 字节流直通，并在 Harness 关闭时用 `taskkill /T`（Windows）
或进程组 `SIGTERM`（POSIX）清理整棵子进程树。

> **为什么不是"两行 + `disabled: !!js`"？** v1.0.0 曾用两行（Windows / POSIX 各一条，
> 由 `disabled: !!js process.platform …` 挑选）。部分较旧的 Harness 构建会忽略或误解析
> `disabled` 里的 `!!js`，于是第二条同 `serverName` 的行真的会尝试激活、撞上
> "duplicate server name" 规则，在插件面板里显示成 **「共 2 个组件 · 1 运行中 · 1 异常」**。
> v1.0.1 起改成单行 + 启动器，不再依赖 `!!js`、也不会再有重复注册。

可调字段：

| 字段 | 当前值 | 说明 |
|---|---|---|
| `env.REA_MCP_INPUT_SCHEMA_PROFILE` | `compact` | **token 成本开关**。本机对 6.4.0（170 工具）实测：模型可见的 input schema 合计 **compact ≈ 184 KB / full ≈ 366 KB**（描述另 ≈ 59 KB），即每轮请求约 **6 万 vs 11 万+ token** 的差别。想要完整嵌套 schema 就删掉整个 `env` 块 |
| `toolCallTimeoutMs` | `1200000`（20 分钟） | 单次 `tools/call` 上限。Ghidra 首查默认 330 s 启动预算，故高于默认 60 s |
| `maxInstructionBytes` | `131072` | 服务器 instructions 上限，超限会拒绝连接 |
| `failOnStartupError` | `false` | `false`：REA 起不来时 Harness 照常启动、只是没有 REA 工具；`true`：激活失败会报错（便于排查） |
| `args` 中的 `rea-agents@6.4.0` | 版本钉扎 | 上游迭代快，升级时改版本号重装即可（启动器脚本里也有同一处版本号，需一起改） |

修改补丁后需要重启 Harness 生效；**不要**为同一服务器再复制第二个条目
（同 `serverName` 的第二条会加载失败）。

## 升级 / 版本历史

完整的「每个版本做了什么、修了什么、怎么验证」见 **[CHANGELOG.md](CHANGELOG.md)**；摘要：

- **v1.2.0**（当前）：按 DSH 插件规范适配——`peerDependencies` 声明 `@deepseek-ai/dsh-mcp-client >= 0.2.0-rc.2`
  （DSH 加载时校验，旧版本明确报 `incompatible-version`）、新增 `dsh.plugin.json` 注册表清单、
  `icon.svg` 插件卡片图标、`keywords`。桥接补丁与 v1.1.0 相同。
- **v1.1.0**：补齐「可反编译一切」的依赖链路文档与工具——`docs/CAPABILITIES.md`、
  `docs/SETUP.md`、`scripts/setup-rea-tools.ps1`（Ghidra / JADX / apktool / adb / 浏览器，SHA-256 钉扎）、
  `scripts/apktool-shim.cs`（Windows 上 apktool 的 exe 启动器）；修复 `package.json` 的 UTF-8 BOM
  （会让 `dsh plugin add github:…` 全部安装失败）。
- **v1.0.1**：单行 + Node 启动器；修复旧构建下第二条平台行显示「异常」的问题。
- **v1.0.0**：双行 + `disabled: !!js`（在较旧 Harness 上可能出现 1 运行中 / 1 异常）。

四个标签可共存、互不冲突；任意版本都能按标签锁装：

```powershell
dsh plugin --profile "$env:DSH_PROFILE" add github:Fanqi89/dsh-rea#v1.2.0   # 最新（DSH ≥ 0.2.0-rc.2）
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
            └─ command: node  args: ['-e', <平台启动器>]
                 ├─ Windows: cmd.exe /d /c npx -y rea-agents@6.4.0 mcp
                 └─ POSIX  : npx -y rea-agents@6.4.0 mcp
                      └─ MCP 握手 + tools/list（6.4.0 实测 170 个工具）
                           └─ 注册为 ctx.tools：mcp__rea__open_binary、mcp__rea__analyze_function、…
```

选型依据来自 Harness 官方 `cordis-plugin-development` 技能的
「Connect an MCP server through a configuration-only bundle」路线，以及 REA 上游文档对
DeepSeek Harness 的官方接入说明（`rea setup --client dsh` 写入的正是同款
`dsh-mcp-client` stdio 条目；npm 6.4.0 尚未包含 `--client dsh`，故本插件手工内联了等价配置）。

## 故障排查

1. **没有 `mcp__rea__*` 工具**：先看 Harness 日志里 dsh-mcp-client 的连接报错；
   手动跑 `npx -y rea-agents@6.4.0 mcp` 确认 Node/npx 正常（Windows 可试
   `cmd.exe /d /c npx -y rea-agents@6.4.0 mcp`）。
2. **插件面板显示「共 2 个组件 · 1 运行中 · 1 异常」**：这是 v1.0.0 的双行补丁在部分
   Harness 构建上的残留（`disabled: !!js` 没被正确识别 → 第二条同 `serverName` 的行
   激活失败）。升级到 v1.0.1（单行 + 启动器）并**重启**即可；升级方式见上面「升级 / 版本历史」。
3. **首启超时**：预热缓存 `npx -y rea-agents@6.4.0 --help`，或把 `failOnStartupError` 设为 `true` 让错误显性化。
4. **原生分析报 provider 缺失**：静态 JS/.NET 不需要引擎；原生需 Hopper/Ghidra/IDA，
   用 `npx -y rea-agents@6.4.0 doctor --json` 诊断（`rea doctor` 同理）。
5. **token 消耗过高**：确认 `env.REA_MCP_INPUT_SCHEMA_PROFILE: compact` 在配置里；
   仍嫌大就仅在逆向会话启用本插件。
6. **重装同一路径报 `ambiguous-install`**：属于预期——先卸载再安装（见上）。

## License

MIT。REA 本体 © morluto（MIT），第三方工具（Hopper/Ghidra/IDA/JEB 等）遵循各自许可。
