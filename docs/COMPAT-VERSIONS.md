# DSH 版本兼容性审计：`dsh-rea` × `dsh-mcp-client` / `dsh-app-boot`

审计范围：DeepSeek Harness（下称 DSH）**0.2.1-rc.2 / rc.3 / rc.4 / rc.5 / 0.2.2-rc.1**。
证据来源：npm 上发布的两个包 `@deepseek-ai/dsh-mcp-client`、`@deepseek-ai/dsh-app-boot` 的 tarball（逐版本下载、解包、逐字节读源码），加上它们在本机 rc.5 安装件里的同版本副本作为交叉校验。
所有结论只描述**读过的代码**；没有读到的部分在第 7 节明确标为「未验证」。

---

## 0. 结论摘要（先看这段）

1. **`dsh-mcp-client` 在我们覆盖的 5 个版本里，配置 schema、env 清洗、重连策略、启动等待、`maxInstructionBytes`、`toolCallTimeoutMs`、工具名规范化全部逐字节相同。** 唯一的代码差异只有一处：rc.4 起在 `resources/list`、`resources/templates/list` 前加了「服务器是否声明 resources 能力」的判断。因此 `dsh-rea` 现在这套 `config:` 在 5 个版本上都能被接受。
2. **`dsh-app-boot` 的 rc.2/rc.3/rc.4/rc.5 是同一个文件（`lib/index.js` sha256 完全相同）**；`0.2.2-rc.1` 大改（+22 KB），新增 `dsh.bundle.platforms` 平台门禁、`optionalDependencies` 计入 profile 作用域、`tool-executor-native`/`tool-executor-ptc` 变为必需启动行，并删除了 5 个导出符号。
3. **`!!js` 在 5 个版本里都受支持**：YAML 侧 `tag:yaml.org,2002:js` → `{__jsExpr}`；patch 文件用同一套 schema 解析；`disabled` 字段的 schema 明确写了 `anyOf[boolean|null, loaderExpression]`；patch 的 `config` 值位置由 `expressions()` 包装成 `anyOf[字面值, loaderExpression]`。`cordis.patch.yml` 里「老版本可能忽略/误解析 `!!js`」这条注释，**对 0.2.1-rc.2 及以上不成立**（更老的版本不在本次审计范围）。
4. **`evaluatePluginCompatibility` 用 `semver.satisfies(runtime, range, { includePrerelease: true })`，且 `runtime` 是 app-boot 自己的版本号**。`engines.dsh: ">=0.2.0-rc.2"` 在 `0.2.2-rc.1` 上**判定为满足**（已用同款 semver 7.8.6 实算，见 4.4）。如果去掉 `includePrerelease`，同一个范围在 5 个版本上**全部为 false** —— 所以这个选项是这套预发布版本能互相兼容的关键，不要自己「修正」范围。
5. `dsh-rea` 的 `package.json` 在审计期间被并行从 v1.3.0 改成了 **v1.4.0**：新增 `engines: { "dsh": ">=0.2.1-rc.2" }`，peer 也从 `>=0.2.0-rc.2` 抬到 `>=0.2.1-rc.2`。这个改法与本次结论一致：`>=0.2.1-rc.2` 在 5 个运行时上**都为 true**（见 4.4 矩阵）；而且 `engines.dsh` 一旦存在就**独自**决定兼容性，`peerDependencies` 不再参与 DSH 版本判定 —— 这是对的，peer 的语义是「mcp-client 包版本」，不是 DSH 版本。审计前的 v1.3.0 没有 `engines.dsh`，那条 peer 会被**错当成 DSH 版本约束**使用（详见 4.4），v1.4.0 已修掉。
6. 实测 REA 服务端（`npx -y rea-agents@6.4.0 mcp`）：`instructions` **304 字节**、工具 **170 个**、冷启动到 `initialize` 响应 **14314 ms / 14745 ms**（两次），initialize→tools/list **1072 ms / 989 ms**。`dsh-rea` 配的 `maxInstructionBytes: 131072` 相对 304 字节有 400 倍余量，`failOnStartupError: false` 让这 14 秒不会变成启动失败。

---

## 1. 审计对象与方法

### 1.1 下载

Tarball URL 模板（直连 registry，`NO_PROXY=registry.npmjs.org,.npmjs.org`）：

```
https://registry.npmjs.org/@deepseek-ai/dsh-mcp-client/-/dsh-mcp-client-0.2.1-rc.2.tgz
https://registry.npmjs.org/@deepseek-ai/dsh-app-boot/-/dsh-app-boot-0.2.2-rc.1.tgz
```

10 个 tarball 全部 200 且 gzip magic 校验通过（`1f 8b`），`tar.exe -xzf` 解包成功。落盘位置（本次审计的 scratch，不在仓库内）：

```
C:\Users\fanqi\Documents\deepseek-harness\default-workspace\.rea-plugin-build\compat\tarballs\
C:\Users\fanqi\Documents\deepseek-harness\default-workspace\.rea-plugin-build\compat\dsh-mcp-client\<ver>\package\
C:\Users\fanqi\Documents\deepseek-harness\default-workspace\.rea-plugin-build\compat\dsh-app-boot\<ver>\package\
```

### 1.2 主证据：`lib/index.js` 逐字节指纹

| 包 | 版本 | `lib/index.js` 字节数 | sha256 |
|---|---|---|---|
| dsh-mcp-client | 0.2.1-rc.2 | 35041 | `758d8fc473b700b5d351158d06ce9f9e92c16e8b25497b08bb7bd2122a87f5dd` |
| dsh-mcp-client | 0.2.1-rc.3 | 35041 | `758d8fc473b700b5d351158d06ce9f9e92c16e8b25497b08bb7bd2122a87f5dd` |
| dsh-mcp-client | 0.2.1-rc.4 | 35189 | `64dfc9127a47d9d453d72022b47d3b8d8a5c82cad756ac1114b09faf1a956120` |
| dsh-mcp-client | 0.2.1-rc.5 | 35189 | `64dfc9127a47d9d453d72022b47d3b8d8a5c82cad756ac1114b09faf1a956120` |
| dsh-mcp-client | 0.2.2-rc.1 | 35189 | `64dfc9127a47d9d453d72022b47d3b8d8a5c82cad756ac1114b09faf1a956120` |
| dsh-app-boot | 0.2.1-rc.2 | 203572 | `5135179ac810e4f626f32ec3bdc3293dc7d2028e8aa92e5e0c006f1a33b78e76` |
| dsh-app-boot | 0.2.1-rc.3 | 203572 | `5135179ac810e4f626f32ec3bdc3293dc7d2028e8aa92e5e0c006f1a33b78e76` |
| dsh-app-boot | 0.2.1-rc.4 | 203572 | `5135179ac810e4f626f32ec3bdc3293dc7d2028e8aa92e5e0c006f1a33b78e76` |
| dsh-app-boot | 0.2.1-rc.5 | 203572 | `5135179ac810e4f626f32ec3bdc3293dc7d2028e8aa92e5e0c006f1a33b78e76` |
| dsh-app-boot | 0.2.2-rc.1 | 225678 | `346f832224737cd9ab1b5e37d111ae232fdd78b5ab892fa3179c112baf6f0a22` |

tarball 本身的 sha256 在不同版本之间会变（README/metadata 不同），但**代码文件相同**就是相同。例如 rc.2 与 rc.3 的 tgz sha256 不同（`0d7091b3…` / `70deb6a5…`），`lib/index.js` 却完全一致。

### 1.3 交叉校验 rc.5 基线

本机已从 DSH 0.2.1-rc.5 桌面版 `app.asar` 提取过一份 rc.5 源码；与本次从 npm 下载的 rc.5 tarball 比对：

```
mcp-dump\dsh\node_modules\@deepseek-ai\dsh-mcp-client\lib\index.js  sha256=64dfc9127a47d9d4…  ←→ tarball 相同
mcp-dump\dsh\node_modules\@deepseek-ai\dsh-app-boot\lib\index.js    sha256=5135179ac810e4f6…  ←→ tarball 相同
mcp-dump\dsh\package.json  version=0.2.1-rc.5
```

两者一致 → 用本地提取件当 rc.5 基线是可信的，且 npm 产物与安装件同源。

### 1.4 辅助包（为了回答具体机制，必须读的实现）

以下不是任务要求的主包，但被主包 import，不读就只能猜；全部单独下载并记录 sha256：

| 包 | 版本 | 用途 | `lib/index.js`(或 `.mjs`) sha256 |
|---|---|---|---|
| `@deepseek-ai/dsh-subprocess` | 0.2.1-rc.2 / rc.5 / 0.2.2-rc.1 | 定义 `scrubbedParentEnv()`（env 清洗） | 三个版本全部 `0ea9e95a73639f9e69b48aa48f373f34881adffa2ee2ac2acd4702728da9592b`（5354 B） |
| `@deepseek-ai/dsh-http-proxy` | 0.2.1-rc.2 / rc.5 / 0.2.2-rc.1 | 定义 `proxyEnvironmentForChild()`（代理注入） | 三个版本全部 `5310861bc89788ea24be82a3b323e34cbd42b9e6214e2a179b2e6f92a8758cd5`（22860 B） |
| `@deepseek-ai/cordis-plugin-loader` | 1.0.6（rc 系列 peer `~1.0.6`）、1.1.0（0.2.2-rc.1 peer `~1.1.0`） | 真正执行 `!!js` 求值的地方 | 1.0.6 `638b9ad360e01236…`；1.1.0 `4f0a93a1ef5bb09b…` |
| `@deepseek-ai/schemastery` | 3.18.5（mcp-client rc 系列 `~3.18.5`）、3.19.0（0.2.2-rc.1 `~3.19.0`） | Config 校验对象语义（未知 key 行为） | 两者 `lib/index.mjs` 均为 `cfcbe46c7416bdb3…`（22988 B，逐字节相同） |
| `semver` | 7.8.6（满足 app-boot `^7.8.5`） | 实算 `satisfies(…, {includePrerelease:true})` | 用于第 4.4 节矩阵 |

> `dsh-subprocess` 与 `dsh-http-proxy` 在这 5 个 DSH 版本之间**代码零变化**，所以第 2 节里 env 清洗、代理注入两行可以直接写成「5 个版本一致」，这不是推断，是哈希相同。

### 1.5 方法限制

- 只读 npm 发布的 JS 产物，**没有**在 5 个 DSH 版本上分别实机启动 `dsh-rea`（那需要 5 份安装件 + profile，超出本次授权）。凡涉及「运行时是否真的这样」的地方，都回到源码里找到对应执行点再下结论。
- 未审计 0.2.1-rc.2 之前的版本。
- **审计期间仓库被并行修改**：`package.json` 于 12:21:32 从 v1.3.0（无 `engines.dsh`、peer `>=0.2.0-rc.2`）变成 v1.4.0（`engines.dsh: ">=0.2.1-rc.2"`、peer `>=0.2.1-rc.2`），`dsh.plugin.json` 同步加了同样的 `engines`。本文以**现行 v1.4.0** 为判断对象，同时保留「无 `engines.dsh` 时回退 peers」的机制说明（第 4.4 节）——那是 app-boot 的行为，与插件当前写不写无关。`cordis.patch.yml` 未被改动（mtime 与 git 状态均干净）。

---

## 2. 版本矩阵

`dsh-rea` 只用到两个包，所以拆成两张表更好读；第一张是任务要求的核心能力矩阵。

### 2.1 核心能力矩阵

| 能力 | 0.2.1-rc.2 | 0.2.1-rc.3 | 0.2.1-rc.4 | 0.2.1-rc.5 | 0.2.2-rc.1 |
|---|---|---|---|---|---|
| **mcp-client 接受的 config 键** | stdio 支路：`serverName` `command` `args` `env` `cwd` `toolCallTimeoutMs` `failOnStartupError` `maxInstructionBytes` `reconnect` `transport`；http 支路：`serverName` `url` `headers` + 同 4 个通用键 | 同左 | 同左 | 同左 | 同左（schema 逐字节相同） |
| **未知 config 键** | 不拒绝（保留、忽略） | 同左 | 同左 | 同左 | 同左 |
| **子进程 env 清洗** | `scrubbedParentEnv()`：丢 `/KEY\|PASSWORD\|SECRET\|TOKEN/i`、丢 `DSH_*`（大小写不敏感），显式 `env:` 在清洗之后合并 | 同左 | 同左 | 同左 | 同左（`dsh-subprocess` 代码哈希相同） |
| **代理注入** | 有活动代理时覆盖 `http_proxy/HTTP_PROXY`、`https_proxy/HTTPS_PROXY`、`no_proxy/NO_PROXY`，并置 `NODE_USE_ENV_PROXY=1` | 同左 | 同左 | 同左 | 同左（`dsh-http-proxy` 代码哈希相同） |
| **reconnect 默认** | `enabled:true`、`initialDelayMs:500`、`maxDelayMs:30000`、`maxAttempts:10`；`reconnect` 键**存在** | 同左 | 同左 | 同左 | 同左 |
| **reconnect 校验** | 未知子键直接抛错；`initialDelayMs/maxDelayMs` 必须 >0 且 ≤`MAX_TIMER_DELAY_MS`；`initialDelayMs ≤ maxDelayMs`；`maxAttempts` 正整数 | 同左 | 同左 | 同左 | 同左 |
| **启动是否 await 首连** | 是（`apply` 为 async，`await connection.ready`，ready 覆盖 connect + 首次 tools 同步） | 同左 | 同左 | 同左 | 同左 |
| **启动超时（`failOnStartupError:false`）** | mcp-client 自身**无**启动超时；失败被吞掉，插件照常激活、工具缺席，转由 reconnect 退避重试 | 同左 | 同左 | 同左 | 同左 |
| **`maxInstructionBytes` 默认** | 32768 字节（UTF-8，含 `### MCP server: <name>\n\n` 头）；超出=抛错（算一次连接失败） | 同左 | 同左 | 同左 | 同左 |
| **`toolCallTimeoutMs` 默认** | 60000 ms（单次 `tools/call` 与 resources 请求） | 同左 | 同左 | 同左 | 同左 |
| **工具名规范化** | `mcp__<server>__<raw>`；超 64 字符或含 `[^A-Za-z0-9_-]` → 截断到 51 + `_` + 12 位 sha256 | 同左 | 同左 | 同左 | 同左 |
| **resources 能力判断** | 无（直接调 `listResources`） | 无（同 rc.2，代码相同） | 有（未声明 resources 时返回空列表） | 有 | 有 |
| **`!!js` YAML 方言** | 支持（`tag:yaml.org,2002:js` → `{__jsExpr}`，patch 文件同 schema） | 支持 | 支持 | 支持 | 支持 |
| **`!!js` 在 patch `config` 值** | 支持（`expressions()` 给每个值位置加 `loaderExpression` 分支） | 支持 | 支持 | 支持 | 支持 |
| **`!!js` 在 `disabled`** | 支持（schema `anyOf[boolean\|null, loaderExpression]`，Loader 里 `disabledOf()` 求值） | 支持 | 支持 | 支持 | 支持 |
| **compat 检查 semver** | `semver.satisfies(runtime, range, {includePrerelease:true})`；`engines.dsh` 单独决定，否则看 `@deepseek-ai/dsh*` peers | 同左 | 同左 | 同左 | 同左 |
| **`engines.dsh:">=0.2.0-rc.2"` 在 0.2.2-rc.1** | — | — | — | — | **满足（true）** |
| **`dsh.bundle.platforms`** | 不存在该字段/无门禁 | 无 | 无 | 无 | **新增**：load 时不匹配→跳过；`plugin add`/reconcile 时不匹配→抛错 |
| **app-boot peer 生态** | `cordis ~4.0.5`、`cordis-plugin-loader ~1.0.6`、`include ~1.0.10`、`group ~1.0.5` | 同左 | 同左 | 同左 | `cordis ~4.1.0`、loader/include/group 全部 `~1.1.0` |

### 2.2 app-boot 导出面变化（如果插件 import 了它）

`0.2.2-rc.1` 删除了这些导出（rc.2–rc.5 有）：`DEFAULT_PROFILE_BUNDLES`、`OPTIONAL_BUNDLES`、`ON_DEMAND_BUNDLES`、`OFFICIAL_ON_DEMAND_CATALOG`、`PROFILE_TEMPLATES`。
新增导出：`assertBundlePlatform`、`UnsupportedBundlePlatformError`。
→ **`dsh-rea` 是 configuration-only bundle，不 import app-boot，所以无影响**；但这条对任何 import 了 app-boot 的插件是 breaking。

---

## 3. `dsh-mcp-client` 详解

以下代码位置引自 rc.5 `lib/index.js`（= rc.4 = 0.2.2-rc.1 的同名文件；rc.2/rc.3 仅在 3.7 那一处不同）。

### 3.1 完整 config schema

`z.union([...])` 两支，`transport` 是 `z.const(...)`（有默认值，所以可省略，省略即 `stdio`）。

**stdio 支路**

| 键 | 类型 | 默认/必填 | 说明 |
|---|---|---|---|
| `transport` | 常量 `"stdio"` | 默认 `"stdio"` | — |
| `serverName` | string | **required**，`/^[A-Za-z0-9_-]{1,32}$/` | 决定工具前缀 `mcp__<serverName>__`；同一作用域内不可重复 |
| `command` | string | **required** | 无 PATH 解析（交给 SDK） |
| `args` | string[] | `[]` | — |
| `env` | map<string,string> | `{}` | **在 `scrubbedParentEnv()` 之后合并**，所以显式声明的键不会被清洗掉 |
| `cwd` | string | `""`（空串） | 空串会原样传给 `StdioClientTransport`（本机 Node v24.19.0 实测 `spawn` 接受 `cwd:''`，等同继承当前目录） |
| `toolCallTimeoutMs` | number | `60000` | 无上下界校验 |
| `failOnStartupError` | boolean | `false` | 见 3.4 |
| `maxInstructionBytes` | number，`step(1)`，`min(1)` | `32768` | 见 3.5 |
| `reconnect` | object | 四个子键都有默认值 | 见 3.3 |

**streamable-http 支路**：`transport` + `serverName`（同样正则/必填）+ `url`（required）+ `headers`（默认 `{}`）+ `toolCallTimeoutMs`/`failOnStartupError`/`maxInstructionBytes`/`reconnect`（同默认）。

**未知键**：Schemastery 的 `object()` 不拒绝也不删除未知键。用 mcp-client 的真实 schema（原样转写）+ schemastery 3.18.5 / 3.19.0 实跑：

```
OK  unknown top-level key   →  {…, bogusKey:1, another:"x"}   // 保留，插件忽略
FAIL serverName with dot     // 正则不允许 '.'
FAIL serverName 33 chars     // 上限 32
FAIL maxInstructionBytes 0   // min(1)
FAIL reconnect.maxAttempts:0 // min(1)
FAIL transport:"sse"         // 只接受 stdio / streamable-http
FAIL missing command         // required
```

**`dsh-rea` 实际两个 row 的 config 都通过校验**（schemastery 3.18.5 与 3.19.0 结果一致，`reconnect` 被填成默认四值、`cwd` 变 `""`）。

### 3.2 子进程 env 组成

```js
function buildChildEnv(extra) {
  return { ...scrubbedParentEnv(), ...extra };
}
```

`scrubbedParentEnv()`（`@deepseek-ai/dsh-subprocess`，5 个版本同一份代码）：

```js
const SENSITIVE_ENV_PATTERN = /KEY|PASSWORD|SECRET|TOKEN/i;
const DSH_ENV_PREFIX = "DSH_";

function scrubbedParentEnv() {
  const env = {};
  for (const [key, value] of Object.entries(process.env))
    if (value !== void 0 && !SENSITIVE_ENV_PATTERN.test(key) && !key.toUpperCase().startsWith("DSH_"))
      env[key] = value;
  for (const [name, value] of Object.entries(proxyEnvironmentForChild()))
    if (value === void 0) Reflect.deleteProperty(env, name); else env[name] = value;
  return env;
}
```

逐条含义：

- **丢弃凭据形状的名字**：名字里含 `KEY` / `PASSWORD` / `SECRET` / `TOKEN`（大小写不敏感，子串匹配）。所以 `DEEPSEEK_API_KEY`、`GITHUB_TOKEN`、`FOO_PASSWORD` 都不会隐式传给 REA 子进程。
- **丢弃所有 `DSH_*`**：`key.toUpperCase().startsWith("DSH_")`，Windows 下大小写不敏感也统一处理。
- **保留** `PATH`、`HOME`、locale、以及**代理变量**。
- **代理注入**（`@deepseek-ai/dsh-http-proxy`）：当进程里有生效的代理策略时，覆盖 `http_proxy`/`HTTP_PROXY`、`https_proxy`/`HTTPS_PROXY`、`no_proxy`/`NO_PROXY`，并加 `NODE_USE_ENV_PROXY=1`；如果解析出的代理 URL 不是 `http:`/`https:`（例如 SOCKS），会**撤掉** `NODE_USE_ENV_PROXY`（否则 Node 22.21+/24+ 的子进程会因为不认识 scheme 直接退出）。没有活动代理时返回 `{}`，即不改动。
- **显式 `env:` 在清洗之后合并** → 你要给子进程传 `*_TOKEN`、`DSH_*` 这类名字，**必须写进 config 的 `env:`**，否则会被静默丢掉。

### 3.3 reconnect 策略

```js
const RECONNECT_DEFAULTS = Object.freeze({ enabled: true, initialDelayMs: 500, maxDelayMs: 3e4, maxAttempts: 10 });
```

- `reconnect` 键**在 schema 里存在**，可以只写部分子键，缺的用默认值。
- `resolveReconnectPolicy()` 会**再校验一遍**（绕开 Schemastery 直接构造也拦得住）：
  - `for (const key of Object.keys(config)) if (!Object.hasOwn(RECONNECT_DEFAULTS, key)) throw` → **未知子键直接抛错**；
  - `initialDelayMs`/`maxDelayMs`：有限、>0、≤ `MAX_TIMER_DELAY_MS`；且 `initialDelayMs ≤ maxDelayMs`；
  - `maxAttempts`：正整数（≥1）。
- 运行语义：一次「中断」共用一份预算，延迟按 `initialDelayMs * 2^(n-1)` 翻倍、封顶 `maxDelayMs`；连接稳定存活超过 `maxDelayMs`（默认 30 s）才清零预算 —— 也就是说**稳定窗口就等于 `maxDelayMs`，没有单独开关**。
- 预算耗尽（`failedAttempts > maxAttempts`）→ 注销该 server 的全部工具并停止重连；只有 HMR 重载或重启 Host 才会恢复。
- 另一条硬规则：失败的一代如果**无法确认 transport 已关闭**，重连会直接停止并报错（防止重叠的服务器进程）。所以子进程卡死时不会无限重拉。
- `reconnect.enabled:false` 时：连接失败=没有工具、给出「reload the plugin or restart the Host」日志；已建立的连接断开=已注册工具会持续失败。

### 3.4 启动是否等待首连 / 有没有启动超时

```js
async function apply(ctx, config) {
  const reconnect = resolveReconnectPolicy(...);
  ...
  const connection = startConnection(ctx, config, reconnect);
  registerServerContext(ctx, config.serverName, connection);
  ...
  const outcome = await connection.ready;              // ← 激活 await 首连
  if (outcome.error !== void 0 && config.failOnStartupError) throw new Error(...);
}
```

- `apply` 显式 `async`，注释写明「Cordis 会把带 prototype 的普通函数当构造函数，返回的 Promise 不算启动工作」，所以这里一定是**真 await**。
- `connection.ready` 在「connect + 首次 `enqueueSync`」都落定后 resolve；`connectGeneration` 注释明确写了 **Never rejects**。
- `failOnStartupError: false`（默认，也是 `dsh-rea` 的选择）→ 首连失败只是 `ctx.logger.warn`，`apply` 正常 resolve，插件处于「已加载但零工具」状态，之后由 reconnect 退避重试。
- **mcp-client 自己没有启动/连接超时**。这文件里只有三处定时：`toolCallTimeoutMs`（工具调用/资源请求）、`GENERATION_CLOSE_TIMEOUT_MS = 5000`（关闭确认）、reconnect 退避。所以「首连要不要有上限」取决于 `@modelcontextprotocol/client@2.2.0`（SDK）内部 —— **未验证**（不在本次审计的 tarball 里）。可观测后果：REA 冷启动实测 14.3 s 是发生在 `apply` await 期间的，也就是 DSH 启动会等这段。

### 3.5 `maxInstructionBytes` / `toolCallTimeoutMs` 语义

```js
const maxInstructionBytes = config.maxInstructionBytes ?? 32768;
const serverText = generation.getInstructions()?.trimEnd() ?? "";
instructions = serverText ? `### MCP server: ${config.serverName}\n\n${serverText}` : "";
if (Buffer.byteLength(instructions) > maxInstructionBytes) throw new Error(...);
```

- 计量对象 = **服务端 `instructions` 原文 + 头部 `### MCP server: <serverName>\n\n`**，按 UTF-8 字节数（`trimEnd()` 之后）。
- 超限是**抛错**，位置在 connect 之后、`enqueueSync` 之前 → 被 `catch` 当作「连接尝试失败」→ 走 reconnect 退避重试，最后耗尽预算、零工具。也就是说 `maxInstructionBytes` 设小了不会「截断」，而是**整个 server 不可用 + 重试噪音**。
- 该文本随后经 `systemPrompt.section({ name: "mcp:<serverName>", order: getSectionOrder("MCP_SERVERS"), interpolate: false })` 注入系统提示词。
- `toolCallTimeoutMs` 同时用于 `client.callTool(..., { timeout })` 与 resources 三类请求（`listResources`/`listResourceTemplates`/`readResource`）的 `options.timeout`。schema 是裸 `z.number()`：无上下界，**负数/0 也能通过校验**（语义交给 SDK，未验证）。

### 3.6 工具公开名规范化

```js
const MAX_PUBLIC_NAME_LENGTH = 64;
const INVALID_NAME_CHARS = /[^A-Za-z0-9_-]/g;
const HASH_LENGTH = 12;

function publicToolName(serverName, rawName) {
  const joined = `mcp__${serverName}__${rawName}`;
  const normalized = joined.replace(INVALID_NAME_CHARS, "_");
  if (normalized === joined && normalized.length <= MAX_PUBLIC_NAME_LENGTH) return normalized;
  const hash = createHash("sha256").update(`${serverName}\0${rawName}`).digest("hex").slice(0, 12);
  return `${normalized.slice(0, 64 - 12 - 1)}_${hash}`;
}
```

- 干净路径：`mcp__<server>__<raw>` 原样返回（≤64 字符且未替换任何字符）。
- 触发替换/截断时：截到 **51 字符 + `_` + 12 位十六进制** = 64 字符封顶；hash 输入是 `serverName\0rawName`，所以不同 MCP 身份不会撞名。
- 重名（同一 server 列出两个同名 raw 工具）直接抛错，工具列表整体不注册。
- `serverName` 上限 32（正则），这也是为了给 `mcp__`+`__` 留预算。

用真实 REA 工具列表实算（170 个工具名）：

```
serverName=rea        → 170 clean / 0 hashed，最长 joined = 48 字符
serverName=rea-linux  → 170 clean / 0 hashed，最长 joined = 54 字符
最长 raw 名：build_reconstruction_obligation_ledger (38)
```

→ **无论启用哪个 row，都不会出现带 hash 后缀的工具名**，工具名可预测、可写进提示词。

### 3.7 版本 diff（对照 rc.5）

`git diff --no-index --unified=6` 的结果：**只有 1 个 hunk**。

```
@@ -689,9 +689,10 @@ function startConnection(ctx, config, policy) {
 			const options = { signal: exec.signal, timeout: config.toolCallTimeoutMs };
+			const listable = generation.getServerCapabilities()?.resources !== void 0;
 			switch (request.method) {
-				case "resources/list": return await generation.listResources(...);
-				case "resources/templates/list": return await generation.listResourceTemplates(...);
+				case "resources/list": return listable ? await generation.listResources(...) : { resources: [] };
+				case "resources/templates/list": return listable ? await generation.listResourceTemplates(...) : { resourceTemplates: [] };
 				case "resources/read": return await generation.readResource({ uri: request.uri }, options);
```

| 版本 | 与 rc.5 的关系 | 行为差异 |
|---|---|---|
| 0.2.1-rc.2 | 差 1 个 hunk | 未声明 `resources` 能力时仍会发 `resources/list`（对 REA 无影响：REA 的 `initialize` 只声明 `tools`/`completions`/`prompts`，没有 `resources`） |
| 0.2.1-rc.3 | **与 rc.2 逐字节相同** | 同上（rc.3 的变更不在这个包里） |
| 0.2.1-rc.4 | **与 rc.5 逐字节相同** | 无 |
| 0.2.1-rc.5 | 基线 | — |
| 0.2.2-rc.1 | **与 rc.5 逐字节相同** | 无 |

**对 `dsh-rea` 的含义**：`config` 相关的行为在这 5 个版本上没有任何差异；唯一差异（resources 能力门禁）碰不到我们，因为 REA 不声明 resources 能力，而 rc.2/rc.3 下多出的那次 `resources/list` 只在「模型/AI 主动读 MCP 资源」时才发生。

---

## 4. `dsh-app-boot` 详解

### 4.1 `!!js` YAML 方言（5 个版本都有）

```js
const JsExpr = new yaml.Type("tag:yaml.org,2002:js", {
  kind: "scalar",
  resolve: (data) => typeof data === "string",
  construct: (data) => ({ __jsExpr: data }),
  predicate: isJsExpr,
  represent: (data) => data["__jsExpr"]
});
const entryListSchema = yaml.JSON_SCHEMA.extend(JsExpr);
```

- 用于：entry 列表文件（`yaml.load(content, { schema: entryListSchema })`）、`include` 文件、**patch 文件**（`const userPatchesSchema = entryListSchema;` → `parsePatchList` 用的就是它）、`--dump-config` 的解析与回写。
- schema 里 `LOADER_EXPRESSION_SCHEMA = { type:"object", properties:{ __jsExpr: {type:"string"} }, required:["__jsExpr"], ... }`，定义在 `$defs`，供 entry/patch 结构引用。
- 结论：**patch 文件里写 `!!js` 不会被「不认识的 tag」拒绝** —— 解析器把它变成 `{__jsExpr:"…"}`，后续交给 Loader 求值。

### 4.2 `!!js` 在 patch `config` 值 / 在 `disabled`

**(a) patch `config` 值：支持。**

- `metadata()` 里 `config: {}`（不约束），`patchStructure()` 是 `allOf:[ref("entryMetadata")], properties:{ insert: ref("entryList") }`；具体某个 id 的 patch 再把 `config` 收紧成「目标插件的投影 schema」（`patchRules` → `then: { properties: { config: { $ref: configRef } } }`）。
- 投影 schema 由 `expressions()` 包装：它递归给**每个值位置**加 `anyOf: [字面值, { $ref: "#/$defs/loaderExpression" }]`，并刻意跳过 `propertyNames`、`not`、`anyOf` 分支位置（注释：`Add expression alternatives only at config VALUE positions, not property names or applicator branches`）。
- 未知插件（没有可收集 schema）的 `configRef` 是 `#/$defs/unknownConfig`（`{}`，注释明确「这是未知配置，不是禁止字段」）。
- 真正求值在 Loader：`interpolate(ctx, config)` 递归把 `{__jsExpr}` 换成 `eval` 结果，挂在 `internal/config` 事件上，即**插件拿到的 config 里表达式已经求完值**。

**(b) `disabled` 字段：支持。**

- entry/patch 共用的 schema 明确写：

```js
disabled: {
  anyOf: [{ type: ["boolean", "null"] }, ref("loaderExpression")],
  description: "Boolean or !!js expression. The Loader coerces other truthy values as disabled; this schema rejects them."
}
```

- 还有一处 `dormant` 定义（用于「必填 config 的插件被禁用时不必提供 config」）：`disabled: { anyOf: [{ const: true }, ref("loaderExpression")] }` —— 也接受表达式。
- Loader 求值点（`cordis-plugin-loader` 1.0.6 与 1.1.0 相同）：

```js
const evaluate = new Function("ctx", "expr", `with (ctx) { return eval(expr) }`);
disabledOf(options) {
  return isJsExpr(options.disabled) ? Boolean(this.evaluate(options.disabled.__jsExpr)) : Boolean(options.disabled);
}
```

  注释写明「raw node 保留在 options 里，回写时保持原样」，所以 `!!js` 不会被写成 `true/false`。

**逐版本结论**

| | rc.2 | rc.3 | rc.4 | rc.5 | 0.2.2-rc.1 |
|---|---|---|---|---|---|
| (a) patch `config` 值支持 `!!js` | ✅ | ✅ | ✅ | ✅ | ✅ |
| (b) `disabled` 支持 `!!js` | ✅ | ✅ | ✅ | ✅ | ✅ |

依据：app-boot 的 rc.2/rc.3/rc.4/rc.5 是**同一个文件**（sha256 `5135179a…`），4.1/4.2 的所有代码在 4 个版本里逐字节一致；`0.2.2-rc.1` 里同样的构造也都在（`tag:yaml.org,2002:js` 在 672 行、`LOADER_EXPRESSION_SCHEMA` 在 3267–3272、`disabled: anyOf[…]` 在 3771 与 3897、`patchStructure` 在 3794）。

> 因此 `cordis.patch.yml` 顶部那句「Older Harness builds can ignore or mis-parse a `!!js` expression in `disabled`」**对 0.2.1-rc.2+ 不成立**。当前用 `disabled: true` 字面量仍然是对的（更简单），但理由应改成「单 row 设计 + 避免 `!!js` 求值副作用」，而不是「兼容性」。

### 4.3 `insert:` 行

patch 里 `- insert:` 的应用算法（rc.2–rc.5 与 0.2.2-rc.1 语义一致，后者多了一次 `structuredClone`）：

```js
if (insert) {
  if (id) {                       // 带 id：插进目标 group 的 config 尾部
    const target = entryMap.get(id);
    if (!target) { warn("patch insert: entry %C not found", id); continue; }
    if (!target.group) { warn("patch insert: entry %C is not a group", id); continue; }
    if (!Array.isArray(target.config)) target.config = [];
    target.config.push(...insert);
  } else data.push(...insert);     // 不带 id：追加到根 entry 列表
  buildMap(insert);                // 索引新行 → 同一 patch 列表里后面的 patch 可以命中它们
  continue;
}
```

- `- insert:` 列表里的每个元素就是一个完整 entry（`id`/`name`/`config`/`disabled`/`group` …），所以 **`disabled` 在 insert 行里同样生效**（`dsh-rea` 的 `rea-linux` 行就是这种写法）。
- 不带 `id` 的 insert 追加进根列表；带 `id` 的 insert 要求目标行 `group: true`。
- 相对路径的插入插件名会被**锚定到 patch 文件所在目录**（`anchorInsertedPluginNames` → `pathToFileURL(resolve(dirname(patch), name))`）；普通包名不变。
- 找不到目标行 = 警告并跳过，不中断（`dsh-rea` 里那两行 insert 永远能命中，因为不带 `id`）。
- 版本差异：`0.2.2-rc.1` 在 push 之前 `const clone = structuredClone(insert)`（rc.5 直接 push 原对象）。影响仅限于「同一 patch 对象被重复应用时插入行与 patch 列表共享引用」，对正常一次启动无可见差别。

### 4.4 `evaluatePluginCompatibility` 与 semver

```js
function getDshRuntimeVersion() {
  const manifest = JSON.parse(fs.readFileSync(fileURLToPath(new URL("../package.json", import.meta.url)), "utf8"));
  return runtimeVersionOf(manifest.version);      // ← app-boot 自己的版本号
}

function satisfies(runtimeVersion, range) {
  return range.trim() !== "" && semver.satisfies(runtimeVersion, range, { includePrerelease: true });
}

function unmetRequirements(fields, runtimeVersion) {
  const engines = own(fields, "engines") ? fields.engines : {};
  if (has(engines, "dsh")) { /* engines.dsh 单独决定 */ }
  if (!has(fields, "peerDependencies")) return {};
  for (const [name, range] of Object.entries(fields.peerDependencies)) {
    if (name !== "@deepseek-ai/dsh" && !name.startsWith("@deepseek-ai/dsh-")) continue;   // ← 只查 dsh* 系列
    if (!satisfies(runtimeVersion, [ "workspace:^", "workspace:~", "workspace:*" ].includes(range) ? runtimeVersion : range)) unmet[name] = range;
  }
}
```

要点：

1. **runtime 版本 = 当前安装的 `@deepseek-ai/dsh-app-boot` 的版本**，不是插件的、也不是 `@deepseek-ai/dsh-mcp-client` 的。
2. `engines.dsh` 有就**独自**决定，peerDependencies 被忽略；没有才回退到 peers。
3. 回退时**只检查** `@deepseek-ai/dsh` 和 `@deepseek-ai/dsh-*`；`@deepseek-ai/cordis`、`@deepseek-ai/cordis-plugin-*` 这类 peer 不参与兼容判定。`workspace:^ / ~ / *` 在 peers 里被解释成「等于当前 runtime」。
4. 不一致时返回结构化 issue，附 `exempted`（精确 `name@version` + 精确 runtime 版本的免检名单，来自 profile 的 `compatibility.json`）；插件页/CLI 用它生成 `pluginCompatibilityWarning()`。

**实算矩阵**（`semver` 7.8.6，与 app-boot 的 `^7.8.5` 同族；`includePrerelease: true`）：

| range | 0.2.1-rc.2 | 0.2.1-rc.3 | 0.2.1-rc.4 | 0.2.1-rc.5 | **0.2.2-rc.1** |
|---|---|---|---|---|---|
| `>=0.2.0-rc.2` | true | true | true | true | **true** |
| `>=0.2.1-rc.2` | true | true | true | true | **true** |
| `>=0.2.1-rc.5` | false | false | false | true | true |
| `>=0.2.2-rc.1` | false | false | false | false | true |
| `^0.2.1-rc.2` | true | true | true | true | **true** |
| `^0.2.0-rc.2` | true | true | true | true | **true** |
| `>=0.2.0-rc.2 <0.3.0` | true | true | true | true | **true** |

**对照组（去掉 `includePrerelease`）** —— 说明这个选项不是可有可无：

| range | rc.2 | rc.3 | rc.4 | rc.5 | 0.2.2-rc.1 |
|---|---|---|---|---|---|
| `>=0.2.0-rc.2` | **false** | **false** | **false** | **false** | **false** |
| `>=0.2.1-rc.2` | true | true | true | true | **false** |

也就是说：`>=0.2.0-rc.2` 这种范围在 DSH 这套预发布版本上**必须** `includePrerelease:true` 才成立；`>=0.2.1-rc.2` 不带该选项时会在 `0.2.2-rc.1` 上翻成 false（因为 patch 位从 1 跳到 2，比较器只允许同 `major.minor.patch` 的预发布）。DSH 传了 `true`，所以两者都正常。

### 4.5 rc.5 → 0.2.2-rc.1 的 app-boot 变更（挑对插件有影响的）

| 变更 | 位置 | 对插件/bundle 的影响 |
|---|---|---|
| **新增 `dsh.bundle.platforms`** | `bundle-platform.js` + `assertBundlePlatform()`，`loadProfileDirectory` 与 `reconcileProfilePlugins` 各调一次 | package.json `dsh.bundle.platforms` 必须是「非空的 Node 平台名数组」；`loadProfileDirectory` 遇到不含当前 Host 的声明→**跳过该 bundle 并列入 `skippedBundles`**；`plugin add`/reconcile 遇到→**抛 `UnsupportedBundlePlatformError`**。rc.5 完全不认这个字段 |
| **`optionalDependencies` 计入 profile 作用域** | `profileDependencyNames()` | 放在 `optionalDependencies` 里的 dsh 包，0.2.2-rc.1 起会被当作 profile 作用域包（rc.5 只认 `dependencies` + `peerDependencies`） |
| **必需启动行增加** | `requiredStartupEntryIds` 新增 `tool-executor-native`、`tool-executor-ptc` | 这是 root 组合的启动审计（缺少即 `StartupError`），只影响自己拼组合的人，不改 bundle 内容 |
| **`applyPatches` 对 insert 做 clone** | `applyPatches()` | 见 4.3，仅修「重复应用共享引用」 |
| **`StartupError` 带 `composition`** | 新增 `startup-diagnostics.js` / `captureStartupComposition` | 启动失败诊断更丰富；插件无需适配 |
| **删除 `internal/update` 的全局 prepend 处理器** | `boot()` | 旧版的隐式刷新路径被去掉；与插件配置无关 |
| **`recompose` 只 resume 父节点数据变化过、或失败过的行** | `recomposeProfile()` | 配置热重载时「哪些行会被重启」更精确（少重启），对插件是行为优化 |
| **删除 5 个导出** | 见 2.2 | import app-boot 常量的插件会 `ERR_MODULE_NOT_FOUND`-式落空（实际是 undefined/命名导出缺失） |
| **peer 生态 `~1.0.6` → `~1.1.0`，`cordis ~4.0.5` → `~4.1.0`** | package.json | 混装（rc 版 app-boot + 1.1 loader）不受支持；bundle 本身不受影响 |

---

## 5. REA MCP 服务端实测

命令与条件（Windows 10 / Node v24.19.0 / 直连 registry）：

```
npx -y rea-agents@6.4.0 mcp        # 经 cmd.exe /d /c 启动（Windows 上 npx 是 .cmd）
JSON-RPC: initialize(protocolVersion=2025-06-18, capabilities={}, clientInfo=dsh-rea-compat-audit)
       → notifications/initialized
       → tools/list
       → 收齐后 taskkill /T /F 整棵进程树
```

| 指标 | 第 1 次（npx 冷） | 第 2 次（npx 已缓存） |
|---|---|---|
| 到 `initialize` 响应 | **14314 ms** | **14745 ms** |
| `initialize` → `tools/list` 响应 | **1072 ms** | **989 ms** |
| 总计 | 15386 ms | 15738 ms |
| `instructions` | **304 字节**（ASCII，304 字符） | 304 字节 |
| 工具数 | **170** | 170 |
| 协商协议 | `2025-06-18` | `2025-06-18` |
| `serverInfo` | `{ name: "rea", version: "6.4.0" }` | 同 |
| `capabilities` | `tools.listChanged=true`、`completions:{}`、`prompts.listChanged=true`（**无 `resources`**） | 同 |
| 整个会话 stdout 字节数 | 1955257（≈1.87 MB，主要是 170 个工具的 schema） | 1955257 |

两次结果高度一致 → 那 ~14.3 s 是 **REA 服务端自身启动开销**，不是 npm 下载（第二次 npx 缓存命中仍然 14.7 s）。

`instructions` 原文（304 B）：

```
REA provides reverse-engineering tools for local artifacts, native binaries, managed code, browser
pages, and runtimes. Use the tool that directly answers the question; discover targets or inspect
inventory only when needed. Tool results include inline Evidence and report their coverage and limitations.
```

`maxInstructionBytes` 实际计量值 = 304 + `"### MCP server: rea\n\n"`(21) = **325 字节**，相对 `dsh-rea` 配的 131072 余量约 400×，相对默认 32768 余量约 100×。

裁剪后的 transcript（含完整工具名列表、taskkill 结果）：

```
C:\Users\fanqi\Documents\deepseek-harness\default-workspace\.rea-plugin-build\compat\rea-mcp\transcript.json
C:\Users\fanqi\Documents\deepseek-harness\default-workspace\.rea-plugin-build\compat\rea-mcp\initialize-response.json
C:\Users\fanqi\Documents\deepseek-harness\default-workspace\.rea-plugin-build\compat\rea-mcp-warm\transcript.json
```

---

## 6. What this means for `dsh-rea`

### 6.1 最低安全 DSH 版本

- **`0.2.1-rc.2`** 就是够用的下限：`dsh-mcp-client`/`dsh-app-boot` 在 rc.2 上已具备本插件依赖的全部能力（stdio config schema、`env` 合并、`reconnect`、`maxInstructionBytes`、`toolCallTimeoutMs`、`failOnStartupError`、`insert:` 行、`disabled` 行）。rc.2 与 rc.3 的 mcp-client 代码逐字节相同，rc.4/rc.5/0.2.2-rc.1 也相同。
- **`0.2.2-rc.1` 也安全**：mcp-client 代码与 rc.5 完全一致，app-boot 的改动（platform 门禁、insert clone、导出删减）都不落在本 bundle 的使用面上。
- **`engines.dsh` 现行写法 `>=0.2.1-rc.2` 是正确的**：5 个运行时全部满足（4.4 矩阵），并且它会把 `0.2.1-rc.1` 及更早挡在门外；写成 `>=0.2.0-rc.2` 同样能在 5 个版本上通过，只是下限更松（会把 0.2.0-rc.2 / 0.2.1-rc.1 也算进来，那两版不在本次审计范围内）。两者都依赖 DSH 传 `includePrerelease: true`。
- 有了 `engines.dsh` 之后，`peerDependencies["@deepseek-ai/dsh-mcp-client"]` **不再参与 DSH 版本兼容判定**（`unmetRequirements` 里遇到 `engines.dsh` 直接 return）。这是正确分工：peer 管的是 mcp-client 包版本，`engines.dsh` 管 DSH 版本。审计前的 v1.3.0 没有 `engines.dsh`，那条 peer 会被拿去和 DSH 运行时版本比较（当时范围是 `>=0.2.0-rc.2`，5 个运行时恰好都为 true，所以也没出问题）；v1.4.0 已经把这个隐式耦合拆开了。

### 6.2 在每个版本上都安全的 config key

下面这些键在 5 个版本的 schema 里逐字节一致，可以放心使用：

```
serverName            # 必填，/^[A-Za-z0-9_-]{1,32}$/（不能带点）
transport: stdio      # 可省略
command               # 必填
args                  # 默认 []
env                   # 默认 {}，合并于 scrubbedParentEnv() 之后
cwd                   # 默认 ""，Node 24 下等价于当前目录
toolCallTimeoutMs     # 默认 60000，无上下界
maxInstructionBytes   # 默认 32768，step 1 / min 1
failOnStartupError    # 默认 false
reconnect             # 键存在；enabled/initialDelayMs/maxDelayMs/maxAttempts 四个子键
```

`dsh-rea` 现在用的这一组（`serverName` / `transport` / `command` / `args` / `env` / `toolCallTimeoutMs: 1200000` / `maxInstructionBytes: 131072` / `failOnStartupError: false`）**在 5 个版本上都能通过校验**，已用真实 schema + schemastery 3.18.5/3.19.0 实跑确认（含两个 row）。

### 6.3 必须避免 / 需要知道的坑

1. **不要给 `reconnect` 写未知子键** —— `resolveReconnectPolicy` 会显式抛错（`<path>.<key> is not a reconnect option`），整个插件实例加载失败。目前 `dsh-rea` 没写 `reconnect`，用的是默认值 `500ms → 30s ×10 次`；REA 冷启动 14.3 s 每次都落在重连预算里，没有问题。
2. **`DSH_*` 和 `*_KEY/TOKEN/SECRET/PASSWORD*` 不会传给 REA 子进程**。如果将来 REA 需要这类环境变量（例如某个 provider 的 token），**必须显式写进 `env:`**；不写会静默丢失，症状是「工具在、但某个后端不可用」。
3. **`maxInstructionBytes` 设小了不是截断，而是整个 server 不可用 + 重试噪音**（超限被当作连接失败）。当前 304 字节的 REA 说明余量极大，不必调更大；131072 只是无害的宽裕值。
4. **`failOnStartupError: false` 是必须的**：REA 冷启动约 14.3 s，且依赖 `npx` 能在子进程 PATH 里找到。设为 `true` 会把这 14 秒的网络/解析抖动变成 DSH 启动硬失败。现状正确。
5. **`cwd` 默认是空串并被原样交给 transport**（不是 `undefined`）。本机 Node v24.19.0 实测 `spawn(..., { cwd: '' })` 正常（等同继承当前目录）；但如果将来 DSH 换 Node 大版本，这一条值得回归。
6. **`!!js` 在 `disabled` 里是可用的**（5 个版本都支持）。`cordis.patch.yml` 里「老版本可能忽略/误解析 `!!js`」的注释对 0.2.1-rc.2+ 已经不成立：真正的理由是「单 row 设计避免同名 server 冲突」。若以后想改成两个 row + `disabled: !!js process.platform==='win32'`，**在这 5 个版本上不会因为 `!!js` 而失败**（但仍要注意同一作用域内 `serverName` 不可重复，见 3.1）。
7. **`0.2.2-rc.1` 新增 `dsh.bundle.platforms`**：`dsh-rea` 目前不声明 → 全部平台可装，无影响。若将来声明，写 `["win32","darwin","linux"]` 这种完整清单，注意 rc.5 完全不认该字段（声明了也不生效），而 0.2.2-rc.1 会**强制**它 —— 声明错了会导致 bundle 在 `plugin add` 时直接抛错、在启动时被跳过。
8. **`0.2.2-rc.1` 删了 app-boot 的 5 个导出**：本 bundle 不 import app-boot，无影响；但若将来给 `dsh-rea` 加 host 侧代码并 import `@deepseek-ai/dsh-app-boot` 的 `DEFAULT_PROFILE_BUNDLES`/`OPTIONAL_BUNDLES` 等，会在 0.2.2-rc.1 上缺失。
9. **工具名可预测**：`mcp__rea__<raw>`，170 个全部干净、最长 48 字符（`mcp__rea-linux__` 前缀下最长 54），**不会**被 64 字符上限触发 hash 后缀。所以文档/提示词里写死工具名是安全的。阈值可以算出来：`mcp__`(5) + `serverName` + `__`(2) + 最长 raw 名(38) = `serverName` + 45，只要 `serverName` 超过 **19 个字符**，最长的 `build_reconstruction_obligation_ledger` 就会变成 `…_<12位hash>`，届时提示词里写死的工具名会失配。
10. **`toolCallTimeoutMs: 1200000`（20 分钟）能被 schema 接受**（裸 `z.number()`，无上下界），但语义上限在 `@modelcontextprotocol/client@2.2.0` 里 —— **未验证**它是否对该值做钳制。如果将来出现「长任务提前超时」，这是第一个要查的点。

### 6.4 一句话交付判断

`dsh-rea@1.4.0`（`engines.dsh: ">=0.2.1-rc.2"`）的 `cordis.patch.yml` / `package.json` 在 **0.2.1-rc.2 → 0.2.2-rc.1** 全区间内**无需改动即可工作**；`engines.dsh` 已在审计期间补上，且正好卡在本次独立确认的安全下限上。剩下唯一值得改的是 `cordis.patch.yml` 顶部关于 `!!js` 的那段注释 —— 它给的理由（「older Harness builds can ignore or mis-parse」）对 0.2.1-rc.2+ 已经不成立，真实理由应该是「单 row 设计避免同一作用域内 `serverName` 重复」，否则后来者会以为 `!!js` 不能用而放弃一个本来可用的方案。

---

## 7. 未验证 / 限制（请勿当成结论使用）

1. **`@modelcontextprotocol/client@2.2.0` 的内部行为**：连接超时、`timeout` 是否钳制、`cwd:''` 的处理、stdio 帧解析 —— 该包不在本次审计范围内，未读其源码。
2. **实机矩阵未跑**：没有在 5 个 DSH 版本上分别启动 `dsh-rea` 做端到端验证；所有结论来自阅读发布产物 + 对 schema/semver 的可执行复算。
3. **`!!js` 的运行时求值**是用 `cordis-plugin-loader` 1.0.6/1.1.0 的源码证明的（它们分别是 rc 系列与 0.2.2-rc.1 的 peer 依赖），不是用 app-boot 一个包自证的；如果 DSH 实际安装的 loader 版本超出 `~1.0.6` / `~1.1.0`，需要重新核对。
4. **更老的 DSH（< 0.2.1-rc.2）未审计**。`cordis.patch.yml` 里「老版本忽略 `!!js`」的说法可能对 0.1.x 成立，本次没有验证。
5. **`process.platform` 在 `!!js` 里的可见性**只做了代码层推理（`new Function` 非严格模式 + `with(ctx)`，自由标识符落到全局 → `process` 可见），没有在本机用该 loader 实跑一次 `!!js process.platform`。

---

## 附：本次审计产生的可复现文件

```
.rea-plugin-build\compat\
├─ tarballs\                                   # 10 个主包 + 辅助包 tarball（gzip 已校验）
├─ dsh-mcp-client\<ver>\package\lib\index.js     # 主证据
├─ dsh-app-boot\<ver>\package\lib\index.js       # 主证据
├─ dsh-subprocess\<ver>\package\lib\index.js     # scrubbedParentEnv
├─ dsh-http-proxy\<ver>\package\lib\index.js     # proxyEnvironmentForChild
├─ loader\{1.0.6,1.1.0}\package\lib\index.js     # !!js 求值点
├─ schemastery\{3.18.5,3.19.0}\package\lib\index.mjs
├─ diff-mcp-client-rc2-vs-rc5.diff               # 1 个 hunk
├─ diff-app-boot-rc5-vs-022rc1.diff              # 1540 行
├─ test-config-schema.mjs                        # 用真实 schema 校验 dsh-rea 的 config
├─ semver-matrix.mjs                             # 4.4 的矩阵
├─ compute-public-names.mjs                      # 170 个工具的公开名
├─ measure-rea.mjs                               # REA 实测脚本
└─ rea-mcp\ , rea-mcp-warm\                      # 两次实测的 transcript.json
```
