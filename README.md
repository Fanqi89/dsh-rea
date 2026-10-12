# dsh-rea

**REA（Reverse Engineer Anything）→ DeepSeek Harness 插件** · https://github.com/morluto/rea

一个 **configuration-only bundle**：不写一行插件代码，通过 DeepSeek Harness 自带的
`@deepseek-ai/dsh-mcp-client` 把本地 REA 的 stdio MCP 服务器接入 Harness。
接入后 REA 的全部工具（`open_binary`、`analyze_javascript_application`、
`inspect_managed_artifact`、反编译 / 伪代码 / 字符串 / 引用追踪等 170 个，6.4.0 实测）会以

```text
mcp__rea__<tool_name>
```

的形式注册给模型（rea-agents 6.4.0 实测 **170 个**），配合已安装的 `reverse-engineer-anything` 技能即可开展逆向调查。

> **合规提示**：REA 仅用于你拥有或已获授权分析的软件（研究、教育、互操作性、软件保存）。
> 使用前请阅读上游 [DISCLAIMER.md](https://github.com/morluto/rea/blob/main/DISCLAIMER.md)。

## 文件结构

```text
dsh-rea/
├── package.json        # bundle 清单：dsh.bundle.patch 指向下面的补丁
├── cordis.patch.yml    # 插入 dsh-mcp-client 行（Windows / POSIX 各一行，按平台启用）
├── locale/en.json      # 插件卡片标题与描述
├── locale/zh.json
└── README.md
```

## 环境要求

| 项目 | 要求 |
|---|---|
| Node.js | 22.x (≥22.19)、24.x (≥24.11) 或 26+，且 `npx` 可用（REA 官方要求） |
| 网络 | 首次启动经 `npx -y rea-agents@6.4.0` 拉取 npm 包（之后走 npx 缓存） |
| 深度原生分析 | 需要本机已有的 Hopper / Ghidra / IDA 之一（Ghidra 需设置 `GHIDRA_INSTALL_DIR`） |
| 静态 JS / .NET 分析 | 无需任何反汇编引擎 |
| 调查工作流技能 | `npx skills add morluto/rea --skill reverse-engineer-anything`（本机已装可跳过） |

## 安装

方式零（从 GitHub 直接装，要求本仓库文件位于仓库根目录）：

```powershell
dsh plugin --profile "$env:DSH_PROFILE" add github:<你的GitHub用户名>/dsh-rea
```

方式一（推荐，UI）：**设置 → 插件 → 安装 bundle**，选择本目录的绝对路径。

方式二（本地 CLI）：

```powershell
dsh plugin --profile "$env:DSH_PROFILE" add "X:\path\to\dsh-rea"
```

`install_bundle` 会自动完成 profile 的 `package.json` / `cordis.patch.yml` 修改与依赖安装，
**不要**手工编辑 profile 文件。装完后重载/重启 Harness 使工具生效。

## 验证

安装成功后，向 Agent 提一句例如「列出你的 mcp__rea__ 工具」，或直接调用
`mcp__rea__binary_session`（输入 `{}`）查看 `result.tool_availability`。
REA 服务器首次冷启动要跑 npx 下载，若几秒内没出工具属正常，稍等重试。

本机实测（2026-10-12，DSH 0.2.0-rc.2 + rea-agents 6.4.0 + Windows）：

- `plugin_manager install_bundle` → `application: applied`，profile 条目 195 → 197
  （`rea-mcp` 挂载、`rea-mcp-posix` 按平台禁用，`!!js` 平台判断生效）；
- `cordis_inspect_query Tool.listTools` 确认 **170 个 `mcp__rea__*` 工具**已注册在线；
- stdio 握手实测：`cmd.exe /d /c npx -y rea-agents@6.4.0 mcp` →
  `initialize` 返回 `rea@6.4.0`，`tools/list` 返回 170 个工具。

## 配置项（`cordis.patch.yml`）

两行插入（`rea-mcp` 用于 Windows，`rea-mcp-posix` 用于 POSIX）由 `disabled: !!js`
按 `process.platform` 挑选，**只有其中一行会挂载**，两行的 `serverName` 同为 `rea`，
因此不会冲突。可调字段：

| 字段 | 当前值 | 说明 |
|---|---|---|
| `env.REA_MCP_INPUT_SCHEMA_PROFILE` | `compact` | **token 成本开关**。本机对 6.4.0（170 工具）实测：模型可见的 input schema 合计 **compact ≈ 184 KB / full ≈ 366 KB**（描述另 ≈ 59 KB），即每轮请求约 **6 万 vs 11 万+ token** 的差别。想要完整嵌套 schema 就删掉整个 `env` 块 |
| `toolCallTimeoutMs` | `1200000`（20 分钟） | 单次 `tools/call` 上限。Ghidra 首查默认 330 s 启动预算，故高于默认 60 s |
| `maxInstructionBytes` | `131072` | 服务器 instructions 上限，超限会拒绝连接 |
| `failOnStartupError` | `false` | `false`：REA 起不来时 Harness 照常启动、只是没有 REA 工具；`true`：激活失败会报错（便于排查） |
| `args` 中的 `rea-agents@6.4.0` | 版本钉扎 | 上游迭代快，升级时改版本号重装即可 |

修改补丁后重装 bundle（或重启）生效；**不要**为同一服务器复制第二个条目
（同 `serverName` 的第二条会加载失败）。

## 卸载 / 临时禁用

- 禁用：设置 → 插件中关闭本 bundle（或 `plugin_manager` 的 `set_bundle enabled: false`）。
- 移除：`plugin_manager` 的 `remove_bundle`，或 CLI `dsh plugin --profile <name> remove dsh-rea`。

本插件不改动任何客户端配置文件，卸载即净。

## 工作原理

```text
Harness 启动
  └─ loader 应用 bundle 补丁 cordis.patch.yml
       └─ 插入 @deepseek-ai/dsh-mcp-client 行（stdio: cmd.exe /d /c npx -y rea-agents@6.4.0 mcp）
            └─ MCP 握手 + tools/list（6.4.0 实测 170 个工具）
                 └─ 注册为 ctx.tools：mcp__rea__open_binary、mcp__rea__analyze_function、…
```

选型依据来自 Harness 官方 `cordis-plugin-development` 技能的
「Connect an MCP server through a configuration-only bundle」路线，以及 REA 上游文档对
DeepSeek Harness 的官方接入说明（`rea setup --client dsh` 写入的正是同款
`dsh-mcp-client` stdio 条目；npm 6.4.0 尚未包含 `--client dsh`，故本插件手工内联了等价配置）。

## 故障排查

1. **没有 `mcp__rea__*` 工具**：先看 Harness 日志里 dsh-mcp-client 的连接报错；
   手动跑 `cmd.exe /d /c npx -y rea-agents@6.4.0 mcp` 确认 Node/npx 正常。
2. **首启超时**：预热缓存 `npx -y rea-agents@6.4.0 --help`，或把 `failOnStartupError` 设为 `true` 让错误显性化。
3. **原生分析报 provider 缺失**：静态 JS/.NET 不需要引擎；原生需 Hopper/Ghidra/IDA，
   用 `npx -y rea-agents@6.4.0 doctor --json` 诊断（`rea doctor` 同理）。
4. **token 消耗过高**：确认 `env.REA_MCP_INPUT_SCHEMA_PROFILE: compact` 在配置里；
   仍嫌大就仅在逆向会话启用本插件。

## License

MIT。REA 本体 © morluto（MIT），第三方工具（Hopper/Ghidra/IDA/JEB 等）遵循各自许可。
