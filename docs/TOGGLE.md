# 图形开关：`dsh-rea-toggle` × `dsh-rea`

> 给 REA 的 207 个工具一个 ON/OFF 开关。开关本身是**第三方独立插件**
> [`dsh-rea-toggle`](https://github.com/phoushen/dsh-rea-toggle) ——
> 上游仓库 **https://github.com/phoushen/dsh-rea-toggle**，作者 **phoushen**，许可 **MIT**
> （`Copyright (c) 2026 phoushen`），本插件接入的是上游 **v1.0.0**，**不包含它的任何代码**。
> 完整的来源/作者核对见第 9 节。本页讲的是**它和 dsh-rea 怎么接**，以及接歪了怎么排。

## 1. 为什么值得关

REA 的工具定义属于**每次请求**的系统提示，不管你调不调它。本机实测（rea-agents **6.7.0**，
默认 `REA_MCP_INPUT_SCHEMA_PROFILE=compact`，Electron as Node 24.21.0）：

| 测量项 | 数值 | 粗估 token（÷3.5） |
|---|---|---|
| 工具数 | 207 | — |
| 工具名 + 描述（同一口径：`name` + `description` 字符数） | 96,343 字符 | **≈ 2.75 万** |
| inputSchema 合计（compact） | 85,705 B | **≈ 2.4 万** |
| inputSchema 合计（full，可选） | 667,642 B | ≈ 19 万 |
| `instructions` | 952 B | ≈ 270 |

也就是默认档下一轮请求里约有 **5 万 token 量级**的工具面。做逆向时值，写脚本/聊天时是死重。
开关关掉后是 0。

> 上游 README 里的 229 / 14 万字符 / 4 万 token 是他们按 `rea-agents@6.8.0` 量的；
> 本插件现在钉 6.7.0（原因见 [COMPAT-VERSIONS.md](COMPAT-VERSIONS.md) §8），所以这里用 207 的数字。

## 2. 接线（3 步）

### 1) 装开关插件

```powershell
dsh plugin --profile "$env:DSH_PROFILE" add github:phoushen/dsh-rea-toggle
```

装完 profile 的 `dependencies` 里会多一行 `dsh-rea-toggle`，`dsh.profile.bundles` 里也会多它。

### 2) 给开关一个抓手（dsh-rea 特有的一步）

开关的实现只干一件事：读 `<DSH_HOME>/profiles/<profile>/cordis.patch.yml`，把目标行里的
`disabled:` 改成 `true`/`false`。而 **dsh-rea 的 `rea-mcp` 行是 bundle 层插入的**，不在 profile patch 里，
所以它找不到行、开关显示 `REA ?`。补一个**按 id 覆盖**的条目即可（不是 `insert`，是覆盖）：

```yaml
# <DSH_HOME>/profiles/<profile>/cordis.patch.yml
- id: rea-mcp
  disabled: false
```

三种做法任选：

```powershell
# A. 脚本（幂等，会备份原文件并把结果校验一遍）
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-rea-tools.ps1 -WithToggle
bash scripts/setup-rea-tools.sh --with-toggle

# B. 手动：把上面两行追加到 profile patch 末尾

# C. 不想装开关：什么都不做，dsh-rea 一切照旧（REA 常开）
```

### 3) 重启

**完全退出** DeepSeek Harness（含托盘）再启动。客户端 chunk 只在启动时扫描，Host 侧的开关行也要挂上。
之后输入框下方会出现 `REA ON` / `REA OFF` 小开关（所在槽位 `conversation.composer.dock`，order 90）。

## 3. 生效时机（别误解）

| 动作 | 立刻发生 | 下次启动才发生 |
|---|---|---|
| 点开关 / 调端点 | profile patch 里的 `disabled:` 被改写（写盘） | 工具集合变化：ON = 207 个，OFF = 0 个 |

开关**不做**热卸载：MCP server 无法在运行时注销自己，`dsh-mcp-client` 也没有工具过滤字段。
所以那 5 万 token 是"下次启动才真正消失"。

## 4. 验证

```powershell
# Host 端点（端口 = 你的 DSH Web 端口）
Invoke-RestMethod http://127.0.0.1:<PORT>/rea-toggle/status
# {"ok":true,"path":"…\\cordis.patch.yml","rowLine":101,"disabled":false,"enabled":true}

# 关 / 开
Invoke-RestMethod http://127.0.0.1:<PORT>/rea-toggle/set -Method POST `
  -ContentType 'application/json' -Body '{"enabled":false}'
Invoke-RestMethod http://127.0.0.1:<PORT>/rea-toggle/set -Method POST `
  -ContentType 'application/json' -Body '{"enabled":true}'
```

判断"关掉有没有真的省下工具"：重启后看 `~/.rea/dsh/launcher.log` 有没有新的 `launch …` 行 ——
OFF 时**不会**有新行、也没有 `rea.mjs` 子进程；ON 时会有。

## 5. 本机实测（2026-11-18，Windows + DSH 0.2.1-rc.5 + rea-agents 6.7.0）

- 隔离 `DSH_HOME` 下的探针 profile（`dsh-rea` + `dsh-rea-toggle` + 覆盖行）：
  - `GET /rea-toggle/status` → `{"ok":true,"rowLine":4,"enabled":true}`
  - `POST /set {"enabled":false}` → 文件变成 `disabled: true`，status `enabled:false`
  - **重启探针** → `launcher.log` 行数不变（73 → 73），没有新的 REA 进程 = 真的没启动
  - `POST /set {"enabled":true}` → 重启 → `launcher.log` 73 → 75，新 REA 进程出现
- 真实 desktop profile 接入后：
  - `include:dsh-rea-toggle` 已加载（`cordis_inspect_query host/Config` 可见）
  - `GET http://127.0.0.1:56557/rea-toggle/status` → `{"ok":true,"rowLine":101,"enabled":true}`
  - `POST set false` → patch 里 `disabled: true`；`set true` → 还原
  - 跨域写（`Origin: https://evil.example`）→ **403**
  - 客户端槽位 `conversation.composer.dock` 的 occupant 里有 `dsh-rea-toggle`（order 90，active）

## 6. 排错

| 现象 | 原因 | 处理 |
|---|---|---|
| 输入框旁没有开关 | 客户端 chunk 启动时才扫描 | 完全退出（含托盘）再开；确认 profile 的 `bundles` 里有 `dsh-rea-toggle` |
| 显示 `REA ?`，悬停提示 `row "rea-mcp" not found` | profile patch 里没有覆盖行 | 做第 2 步（或 `-WithToggle`） |
| 显示 `REA ?`，提示 `cordis.patch.yml not found` + 路径里是别的 profile 名 | 开关按 `DSH_PROFILE` 找 profile，未设时默认 `desktop` | 设 `DSH_PROFILE=<你的 profile>` 后重启，或把开关那行加到你自己的 profile patch |
| 关了之后工具还在 | 工具注册发生在启动时 | 重启 Host |
| 改了 `disabled` 没反应 | 那一行不是 dsh-rea 的 `rea-mcp`（id 被改过） | 给开关插件配 `targetId`（见其 README） |

## 7. 撤销

1. 从 profile patch 里删掉那段 `- id: rea-mcp / disabled: …`（或恢复
   `cordis.patch.yml.dsh-rea-toggle.bak` 备份）→ REA 回到"常开"；
2. 不需要开关了就 `dsh plugin --profile "$env:DSH_PROFILE" remove dsh-rea-toggle`；
3. 重启 Host。

开关只写 profile patch 的那一个键：不碰 `~/.rea/dsh`、不卸载 REA、不改任何二进制。

## 8. 它做不到的

- **不是工具过滤器**：`dsh-mcp-client` 没有包含性字段，所以只有"207 个"或"0 个"两种状态。
- **不是热切换**：见第 3 节。
- **不是安全边界**：它翻的是你自己本来就拥有的一个 YAML 键；端点只监听宿主回环端口，
  `POST` 的 `Origin` 与 `Host` 不一致直接 403。

## 9. 上游来源与作者

| 项目 | 内容 |
|---|---|
| 上游项目 | `dsh-rea-toggle` —— 给 DeepSeek Harness 里的 REA MCP 服务器一个图形开关 |
| **上游仓库** | **https://github.com/phoushen/dsh-rea-toggle**（`git clone https://github.com/phoushen/dsh-rea-toggle.git`） |
| **作者** | **phoushen**（GitHub 用户 `phoushen`；上游 `package.json` 的 `"author": "phoushen"`，`LICENSE` 版权行 `Copyright (c) 2026 phoushen`，仓库创建者与全部提交者都是该账号） |
| **许可** | **MIT**（Copyright (c) 2026 phoushen），全文见上游仓库 `LICENSE` |
| 本插件接入的版本 | **v1.0.0**（`dsh plugin --profile <p> add github:phoushen/dsh-rea-toggle` 装入时为 1.0.0） |
| 上游时间线 | 仓库创建 2026-10-27T12:14Z，同日收敛到 HEAD `2ef56ba`（`docs: add GUI screenshots (on/off) and a video walkthrough link`） |
| dsh-rea 对上游的改动 | **零改动**：不 vendor、不 fork、不打 patch；只补 profile patch 的接线条目、脚本与文档 |
| 升级方式 | 上游更新后重跑一次 `dsh plugin --profile <p> add github:phoushen/dsh-rea-toggle` 并重启 Harness |
| 本机出处核对 | `%USERPROFILE%\.dsh\profiles\<p>\node_modules\dsh-rea-toggle\package.json` 的 `repository.url` / `author`，同目录 `LICENSE` 首行 |
| 免责声明 | 非官方：与 REA（[morluto/rea](https://github.com/morluto/rea)，MIT）和 DeepSeek Harness 均无隶属关系 |

- REA 本体：`morluto/rea`，MIT —— dsh-rea 只是它的 MCP 桥。
- 开关插件：`phoushen/dsh-rea-toggle`，MIT，作者 **phoushen** —— 本插件**不包含它的代码**，只做接线与文档。
- 若上游仓库迁移/改名，请以上游 `package.json` 的 `repository` 字段为准；本页链接指向 2026-10-27 时的上游地址。
