# macOS / Linux 环境配置（POSIX）

> 本页是 [SETUP.md](SETUP.md) 的 POSIX 对应物：**插件本体零依赖**，这里只解决「要原生反编译、APK 代码/资源、Android 设备、浏览器页面时还缺什么」。
> 一键脚本：[`scripts/setup-rea-tools.sh`](../scripts/setup-rea-tools.sh)（macOS / Linux）。
> Windows 用 [`scripts/setup-rea-tools.ps1`](../scripts/setup-rea-tools.ps1)；Windows 上的 Linux 专属线用 WSL 2（见 [SETUP.md](SETUP.md) 的 2.7 与 [CAPABILITIES.md](CAPABILITIES.md) 的 3.1）。

## 0. 开箱可用范围

| 能力 | macOS | Linux | 依赖 / 说明 |
|---|---|---|---|
| **MCP 服务器本体**（170 个 `mcp__rea__*` 工具：静态 JS/Electron/ASAR、.NET、PE 资源、通用归档、EVM、证据体系） | 可用 | 可用 | 只要 Node ≥ 22.19；脚本第 8 步会把 pinned 本地安装装好 |
| **Ghidra 原生线**（伪代码、汇编、函数清单、xref、调用图、字符串/名称、DWARF） | 可用 | 可用 | JDK 21+ + Ghidra 12.1.4；脚本第 2/3 步 |
| **Android 代码线**（包信息、Manifest、类清单、方法级 Java 源码、smali 回退、引用追踪） | 可用 | 可用 | JDK 21+ + JADX 0.7.1 jar；脚本第 2/4 步 |
| **Android 资源线**（资源表、资源解码） | 可用 | 可用 | JDK 21+ + apktool；脚本第 6 步生成 wrapper |
| **Android 设备**（装/拉 APK、logcat、截图、进程） | 可用 | 可用 | adb；脚本第 5 步只检测、不安装 |
| **浏览器 / CDP 线**（DOM、脚本、网络观测、截图、场景回放、WebMCP） | 可用 | 可用 | Chrome 或 Chromium；脚本第 7 步只检测 |
| Hopper（macOS 原生 UI / system framework 逆向） | 可用（自备 Hopper） | **不可用** | Hopper 是 macOS 应用，REA 的 10 个 macOS 专属 provider 操作在 Linux 返回 `unsupported_host` |
| Linux 专属线（ELF 布局、崩溃 core、固件、mitmproxy、`.deb`） | **不可用** | 可用（自备 pwntools/binwalk/unblob/mitmdump） | 见 [CAPABILITIES.md](CAPABILITIES.md) 的 3.1 |
| 进程捕获（PTY 回放 / 文件系统观测） | 可用 | 可用 | 无额外依赖 |

> 一句话：**脚本自动补齐的是 Node 环境与 Ghidra/JADX/apktool 的下载与路径，adb/浏览器只检测**。系统级包（JDK、adb、Chromium）永远由你决定装不装——脚本只打印对应包管理器的准确命令。

## 1. 前置条件

| 项目 | 要求 | 说明 |
|---|---|---|
| Node.js | `^22.19.0 \|\| ^24.11.0 \|\| >=26.0.0` | 与 `rea-agents@6.4.0` 的 `engines.node` 完全一致；22.x 低于 22.19、23.x、25.x 都不满足 |
| npm | 随 Node 提供 | 第 8 步的 pinned 安装要用（`npm install --prefix`） |
| JDK | **21+ 且是完整 JDK**（含 `javac`） | Ghidra、JADX、apktool 都需要；只有 JRE 时脚本会 `[warn]` |
| bash | **bash 3.2 或更新**（macOS 自带就是 3.2） | 脚本刻意不用 bash 4 特性（无 associative array / `${var,,}` / `mapfile`），所以 macOS 不需要装新版 bash；`dash` 不适用，请用 `bash` 调用 |
| 网络 | 首次下载 Ghidra（约 570 MB）与 JADX（约 42 MB） | 失败不阻塞 MCP 启动，只影响对应能力；npm 包由第 8 步决定（失败则回退 `npx`） |
| 磁盘 | Ghidra zip + 解压后合计 1 GB 以上 | zip 默认保留（重跑时复用并校验 SHA-256），可手删 |

## 2. 快速开始

```bash
cd /path/to/dsh-rea

# 1) 先预览：只打印动作，不下载、不写文件、不装任何东西（退出码 0）
bash scripts/setup-rea-tools.sh --dry-run

# 2) 正式执行：Node 检查 → JDK 检查 → Ghidra → JADX → adb → apktool → 浏览器 → pinned REA 安装 → 汇总
bash scripts/setup-rea-tools.sh

# 3) 自定义工具目录 / 复用已有的 apktool.jar
bash scripts/setup-rea-tools.sh --tools-root "$HOME/opt/rea-tools" --apktool-jar /opt/homebrew/bin/apktool.jar

# 4) 只做 pinned REA 安装（完全跳过可选分析依赖）
bash scripts/setup-rea-tools.sh --skip-ghidra --skip-jadx --skip-adb --skip-apktool
```

**参数**

| 参数 | 作用 |
|---|---|
| `--dry-run` | 打印每一步将做什么；不下载、不写文件、不改环境；退出码 0（Windows 的 bash 里也能安全跑） |
| `--tools-root DIR` | 工具解压根目录，默认 `${REA_TOOLS_ROOT:-$HOME/.rea/tools}` |
| `--apktool-jar PATH` | 指定已有的 apktool jar（否则按常见路径探测） |
| `--skip-ghidra` | 不下载/不校验 Ghidra（已存在的安装仍会被识别并导出） |
| `--skip-jadx` | 不下载 JADX jar |
| `--skip-adb` | 不看 adb |
| `--skip-apktool` | 不生成 apktool wrapper |
| `--skip-agents` | 不装 pinned REA（启动器会回退到 `npx` 方案） |
| `-h` / `--help` | 用法 |

**输入输出的约定**（脚本自己在末尾也会重复一遍）：

- `[ok]` = 已核验通过；`[skip]` = 已存在或被参数跳过；`[hint]` = 需要你手动执行的具体命令；`[warn]` = 可选步骤失败（不阻塞）；`[fail]` = 硬失败（退出码 1）。
- 退出码：`0` 完成（可能带 `[warn]`）、`1` 硬失败、`2` 参数错误。
- **不要用 `sudo` 跑**：脚本只写 `$HOME`，不需要管理员权限；系统包安装一律交给你执行它打印出的 `[hint]`。
- 不需要 `chmod +x`：用 `bash scripts/setup-rea-tools.sh` 调用即可（仓库若带执行位，`./scripts/setup-rea-tools.sh` 也可）。

## 3. 它到底装了什么、装到哪

启动器（`cordis.patch.yml` 里的 Node 启动器）解析 REA 服务器入口的顺序是固定的：

```text
1. $REA_MCP_ENTRY                                      （你自己指定时）
2. $HOME/.rea/dsh/agents/6.4.0/node_modules/rea-agents/scripts/rea.mjs
                                                       （脚本第 8 步装的就是它；用 DSH 自带 Node 启动）
3. npx -y rea-agents@6.4.0 mcp                         （兜底：需要网络 + PATH 上有可用 Node）
```

第 2 层是「pinned 本地安装」，脚本执行的就是：

```bash
npm install --prefix "$HOME/.rea/dsh/agents/6.4.0" rea-agents@6.4.0 --no-audit --no-fund --loglevel=error
```

装完脚本会断言 `.../node_modules/rea-agents/scripts/rea.mjs` 存在，并打印它的绝对路径与已安装版本。

> 若你的 `dsh-rea` 版本里 `cordis.patch.yml` 仍是早期的「纯 npx」启动器（v1.3.0 及更早），
> 第 8 步装好的本地安装不会被读取（但也不会出错）；升级插件后即按上面的 1/2/3 顺序解析。

| 步骤 | 产物 | 默认位置 | 导出的变量 | 缺了会怎样 |
|---|---|---|---|---|
| 1 | 无（只检查 Node 与 npm） | — | — | 缺 Node/npm 时脚本会在任何下载**之前** `[fail]` 退出，避免半装 |
| 2 | 无（只探测 JDK 21+，优先 `JAVA_HOME`，否则 PATH 上的 `java`） | — | `JAVA_HOME` | Ghidra/JADX/apktool 用不了 |
| 3 | Ghidra 12.1.4（zip 保留在根目录，解压出 `ghidra_12.1.4_PUBLIC/`） | `$tools_root/` | `GHIDRA_INSTALL_DIR` | 原生反编译线关闭（MCP 仍可启动） |
| 4 | `jadx-headless-mcp-0.7.1-all.jar`（best effort） | `$HOME/.rea/android/` | `REA_JADX_MCP_JAR` | APK 代码反编译关闭（包信息/资源解码仍可用） |
| 5 | 无（检测 `REA_ADB_PATH` 或 PATH 上的 `adb`） | — | `REA_ADB_PATH`（可选但显式） | 设备线关闭 |
| 6 | `apktool` wrapper（`#!/bin/sh` → `exec <java> -jar <jar> "$@"`，755） | `$tools_root/apktool/apktool` | `REA_APKTOOL_COMMAND` | 资源解码关闭 |
| 7 | 无（检测 Chrome / Chromium） | — | `REA_BROWSER_EXECUTABLE` | 浏览器线关闭 |
| 8 | `rea-agents@6.4.0` 本地安装 | `$HOME/.rea/dsh/agents/6.4.0/` | **不需要任何变量** | 启动器回退第 3 层 `npx`（要网络） |
| 9 | 汇总：全部 `export` 行、环境可见性说明、验证命令 | — | — | — |

**apktool 为什么要 wrapper**：REA 用 **shell-free `exec`** 启动 `REA_APKTOOL_COMMAND`
（`<launcher> --version`、`<launcher> d …`），所以它必须是一个**真可执行文件**。
macOS/Linux 上 `apktool.jar` 本身不可执行，Homebrew 的 `apktool` 脚本又不保证在
REA 子进程的 PATH 上，于是脚本生成一个最小的 POSIX wrapper：

```sh
#!/bin/sh
# Generated by dsh-rea scripts/setup-rea-tools.sh
# REA executes this file shell-free, so it must be a real executable.
exec "/path/to/java" -jar "/path/to/apktool.jar" "$@"
```

它把 `java` 和 jar 都写成**绝对路径**，因此不依赖 DSH 子进程的 PATH；验证：
`"$REA_APKTOOL_COMMAND" --version`（apktool 应打印版本号）。Windows 上这个位置由
C# 编译的 `apktool.exe` shim 承担（见 SETUP.md 2.4）。

**下载物与校验**（脚本在 `sha256sum` / `shasum -a 256` / `openssl dgst -sha256` 任一可用时校验，不匹配会明确报错并**拒绝解压**）：

| 下载物 | 版本 / 资产名 | SHA-256 |
|---|---|---|
| Ghidra | 12.1.4 · `ghidra_12.1.4_PUBLIC_20260921.zip` | `ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db` |
| jadx-headless-mcp | 0.7.1 · `jadx-headless-mcp-0.7.1-all.jar` | `6e5eacf500b64292bfb73c49797c1958f6ee44646e43e868039ae7feb573ff75` |

> 两个地址都在 2026-11-07 实测可达（HTTP 200）：Ghidra 用
> `NationalSecurityAgency/ghidra` 的 `Ghidra_12.1.4_build` 标签、
> JADX 用 `1013503897/jadx-headless-mcp` 的 `v0.7.1` 标签。
> GitHub 直连不通时，可先用镜像下载到同一路径（脚本发现文件已存在会复用并**仍然校验 SHA-256**）：
>
> ```bash
> curl -fL --retry 3 -o "$HOME/.rea/tools/ghidra_12.1.4_PUBLIC_20260921.zip" \
>   "https://ghproxy.net/https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.1.4_build/ghidra_12.1.4_PUBLIC_20260921.zip"
> bash scripts/setup-rea-tools.sh   # 会复用该 zip 并校验
> ```

## 4. 环境变量

只有**可选分析线**需要变量；pinned 本地 REA 安装一个都不需要。

| 变量 | macOS 典型值 | Linux 典型值 | 用途 |
|---|---|---|---|
| `JAVA_HOME` | `/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home` | `/usr/lib/jvm/java-21-openjdk-amd64` | Ghidra / JADX / apktool |
| `GHIDRA_INSTALL_DIR` | `$HOME/.rea/tools/ghidra_12.1.4_PUBLIC` | 同 | 原生反编译 provider |
| `REA_JADX_MCP_JAR` | `$HOME/.rea/android/jadx-headless-mcp-0.7.1-all.jar` | 同 | APK 代码反编译 |
| `REA_ADB_PATH` | `$(command -v adb)`（Homebrew：`/opt/homebrew/bin/adb`） | `/usr/bin/adb` | Android 设备线 |
| `REA_APKTOOL_COMMAND` | `$HOME/.rea/tools/apktool/apktool` | 同 | APK 资源解码 |
| `REA_BROWSER_EXECUTABLE` | `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome` | `$(command -v google-chrome)` 或 `$(command -v chromium)` | 浏览器 / CDP 线 |
| `REA_TOOLS_ROOT` | `$HOME/.rea/tools` | 同 | `--tools-root` 的默认值 |
| `REA_MCP_ENTRY` | 一般**不要**设 | 一般**不要**设 | 覆盖启动器第 1 层（只想用某个自备 `rea.mjs` 时才设） |

```bash
# 临时会话里试一下（只在当前 shell 有效）
export JAVA_HOME="/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home"
export GHIDRA_INSTALL_DIR="$HOME/.rea/tools/ghidra_12.1.4_PUBLIC"
export REA_JADX_MCP_JAR="$HOME/.rea/android/jadx-headless-mcp-0.7.1-all.jar"
export REA_BROWSER_EXECUTABLE="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
```

## 5. 让 Finder / Dock 启动的 DSH 看到这些变量

关键点：**MCP 子进程继承的是「启动 DSH 的那个进程」的环境**，不是你的交互式 shell 环境。
macOS 上从 Finder / Dock 双击启动的 App **不会读** `~/.zshrc` / `~/.bash_profile`，
所以「在终端里 export 完再点图标」是无效的。

按可靠性排序：

**A. 用 wrapper 脚本启动 DSH（推荐，最可控）**

```sh
#!/bin/sh
# ~/bin/dsh-with-rea
export JAVA_HOME="/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home"
export GHIDRA_INSTALL_DIR="$HOME/.rea/tools/ghidra_12.1.4_PUBLIC"
export REA_JADX_MCP_JAR="$HOME/.rea/android/jadx-headless-mcp-0.7.1-all.jar"
export REA_BROWSER_EXECUTABLE="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
exec "/Applications/DeepSeek Harness.app/Contents/MacOS/DeepSeek Harness" "$@"
```

```bash
chmod +x "$HOME/bin/dsh-with-rea"
"$HOME/bin/dsh-with-rea"        # 以后都用它启动；env 一定进得去 DSH 进程
```

> App 包内二进制名以实际安装为准：`ls "/Applications/DeepSeek Harness.app/Contents/MacOS/"`，
> 把 `exec` 后面那行换成列出的可执行文件名即可。

Linux 同理，把 `exec` 换成 DSH 的真实可执行路径（`which dsh` 或桌面安装目录里的二进制），
再让 `.desktop` 的 `Exec=` 指向这个 wrapper。

**B. macOS `launchctl setenv`（不改启动方式，但要重启 DSH）**

```bash
launchctl setenv JAVA_HOME "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home"
launchctl setenv GHIDRA_INSTALL_DIR "$HOME/.rea/tools/ghidra_12.1.4_PUBLIC"
launchctl getenv GHIDRA_INSTALL_DIR      # 回读确认
# 完全退出 DSH，再从 Finder/Dock 启动
```

> `launchctl setenv` **重启后失效**；要长期生效得写一个 LaunchAgent（`EnvironmentVariables`）或每次登录后重跑。
> 变量很多时它比 wrapper 更难维护，因此只建议临时排障用。

**C. Linux：从终端启动或写进 profile**

```bash
# 从终端启动（最简单，env 直接继承）
export GHIDRA_INSTALL_DIR="$HOME/.rea/tools/ghidra_12.1.4_PUBLIC"
exec dsh                      # 换成你的 DSH 启动命令（桌面版填 AppImage / 二进制路径）
```

若坚持用桌面图标：把 `Exec=` 改成包着 export 的 wrapper（见 A）；若 DSH 是以
systemd user service 运行的，用 `systemctl --user set-environment JAVA_HOME=...` 后再
`systemctl --user restart <unit>`。把变量写进 `~/.profile` 只对「从登录 shell 里启动的程序」有效。

> **重要**：如果你的目标只是让 REA 的 MCP 服务器起来，上面**全都不需要**——
> 第 2 层 pinned 安装按固定路径解析，且用 DSH 自带的 Node 启动。这些变量只影响
> Ghidra / JADX / adb / apktool / 浏览器这些可选能力。

## 6. 验证

### 6.1 不开 DSH：直接握手（脚本末尾打印的就是这条）

```bash
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"probe","version":"0.0.0"}}}' | node "$HOME/.rea/dsh/agents/6.4.0/node_modules/rea-agents/scripts/rea.mjs" mcp
```

期望输出**一行 JSON**，其中含 `"serverInfo":{"name":"rea","version":"6.4.0"}`（下面是实跑输出，`instructions` 字段为节选）：

```text
{"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{"listChanged":true},"completions":{},"prompts":{"listChanged":true}},"serverInfo":{"name":"rea","version":"6.4.0"},"instructions":"REA provides reverse-engineering tools ..."},"jsonrpc":"2.0","id":1}
```

**第一行 JSON 就是「服务器可达」的证据**；没有任何输出说明服务器没起来（看 stderr；常见原因：入口文件不存在、Node 版本不满足、安装不完整）。

### 6.2 Ghidra 自检（原生线是否真能用）

```bash
"$GHIDRA_INSTALL_DIR/support/analyzeHeadless" "$HOME/.rea/tmp" probe -import /bin/ls -noanalysis
```

期望看到 Ghidra 启动、`Import succeeded` / `REPORT: Save succeeded` 之类的日志
（`-noanalysis` 只导入不分析，几秒到几十秒；第一次会创建 `$HOME/.rea/tmp` 项目目录）。
如果这里就报 JDK/内存错误，先修 `JAVA_HOME`，再回 DSH 里试原生分析。

### 6.3 在 DSH 里逐条验证

| 能力 | 试这个工具 | 期望 |
|---|---|---|
| 工具已接入 | 让 Agent「列出你的 `mcp__rea__` 工具」/ `binary_session` | 170 个 `mcp__rea__*`，`tool_availability` 里 ghidra 可用 |
| 原生反编译 | `open_binary` + `analyze_function` / `procedure_pseudo_code` | 伪代码 + Evidence |
| APK 代码 | `inspect_android_package` / `inspect_android_method` | Java 源码 |
| APK 资源 | `inspect_apktool_client` / `decode_android_resources` | apktool 版本 + 资源清单 |
| Android 设备 | `inspect_adb_client` / `list_adb_devices` | adb 版本 + 设备列表 |
| 浏览器 | `list_browser_targets` / `inspect_web_page` | CDP 目标列表 |
| 引擎体检 | `npx -y rea-agents@6.4.0 doctor --json` | 各 provider 检查项转绿 |

> 注意时序：Ghidra 首次查询要导入 + 自动分析，可能几分钟（`toolCallTimeoutMs` 已放宽）；不是卡死。

## 7. macOS 注意事项

- **Gatekeeper 隔离**：`curl` 下载的 zip 解压出的文件带 `com.apple.quarantine`，
  首次运行 `support/analyzeHeadless` 可能被拦。处理：

  ```bash
  xattr -dr com.apple.quarantine "$GHIDRA_INSTALL_DIR"
  xattr -l "$GHIDRA_INSTALL_DIR/support/analyzeHeadless"   # 回读应为空
  ```

- **Apple Silicon 要原生 JDK**：装 aarch64 的 Temurin 21（`brew install --cask temurin@21`），
  这样 Ghidra 会用自带的 `os/mac_arm_64` 原生 decompiler；x86_64 的 JDK 只能靠 Rosetta 跑，
  明显更慢且会退到 x86_64 的 decompiler。
  自检：`"$JAVA_HOME/bin/java" -XshowSettings:properties -version 2>&1 | grep os.arch`
  应显示 `aarch64`。
- **Homebrew 前缀**：Apple Silicon 是 `/opt/homebrew`（`apktool.jar` 通常在
  `/opt/homebrew/bin/apktool.jar`），Intel 是 `/usr/local`。脚本两个位置都探测。
- **路径带空格**：Chrome 的可执行路径含空格，`export` 时一定加引号（脚本打印的形态已带引号即可直接复制）。
- `apktool --version` 会真的启一次 JVM，慢一两秒是正常的。

## 8. Linux 注意事项

- **系统包名**（脚本会按检测到的包管理器打印；这里给对照）：

  | 需要的 | apt (Debian/Ubuntu) | dnf (Fedora/RHEL) | pacman (Arch) |
  |---|---|---|---|
  | Node 22+ | NodeSource 22.x（发行版 `nodejs` 常偏旧） | NodeSource / nvm | `nodejs npm` |
  | JDK 21+ | `openjdk-21-jdk` | `java-21-openjdk-devel` | `jdk21-openjdk` |
  | adb | `android-tools-adb` | `android-tools` | `android-tools` |
  | Chromium | `chromium` | `chromium` | `chromium` |
  | apktool | `apktool`（jar 在 `/usr/share/apktool/apktool.jar`） | 官方 jar | `apktool` |

- **不需要 root**：Ghidra、JADX、apktool wrapper 都装在 `$HOME`（`~/.rea/...`）。
- **Linux 专属线（ELF 布局 / core / 固件 / mitmproxy / PTY）在 Linux 主机上可直接用**，
  但要自备 `pwntools`、`binwalk`、`unblob`、`mitmproxy`（`pipx install pwntools` 等）。
- **WSL 2 用户**：WSL 里的 Linux 发行版就是一台 Linux，可以在这里跑本脚本；
  但 Windows 侧 DSH 的 MCP 启动器用的是 **Windows 路径**，所以本脚本在 WSL 里装的东西
  只对 `cordis.patch.yml` 里那条 `rea-linux`（`serverName: rea-linux`）有用。
  完整步骤仍按 [SETUP.md](SETUP.md) 2.7：`scripts/setup-wsl-linux-toolchain.ps1` 准备 WSL，
  `scripts/linux-tools-setup.sh` 在发行版内装工具链，然后把 `rea-linux` 行的
  `disabled: true` 改成 `false`。
- **无图形环境的服务器**：浏览器线不可用（没有 Chrome/Chromium 可执行文件），
  其余静态分析线不受影响。

## 9. 限制（如实）

- 本脚本**只准备依赖，不验证分析结果**：它不启动 Ghidra 分析、不连 adb 设备、不开浏览器；
  「装好了」只代表文件/路径/版本检查通过，真正的能力要用第 6 节的手动验证。
- **不做任何系统级安装**：JDK、adb、Chromium、apktool 只给命令，不代跑；也**不修改**任何 shell
  profile、`~/.dsh` 或 DSH 安装目录（只写 `$HOME/.rea` 与 `--tools-root`）。
- **Hopper 仅 macOS**：Windows / Linux 上没有 Hopper，原生反编译用 Ghidra（或 IDA，走
  `REA_IDA_MCP_CONFIG`）。macOS 的 10 个专属 provider 操作在 Linux 上返回 `unsupported_host`，
  见 [CAPABILITIES.md](CAPABILITIES.md) 第 3 节。
- **Ghidra 下载失败不阻塞**：MCP 服务器照样能起，只是原生线不可用；JADX 同为 best effort。
- **apktool 只支持 jar + POSIX wrapper**：没有为 Linux/macOS 找预编译二进制；老版本 apktool 的
  `--version` 输出格式不同时，最多让 `inspect_apktool_client` 少报一个版本号，`d` 解码本身不受影响。
- 本脚本已在 Windows 的 bash（Git Bash / MSYS2，bash 5.3）上做过 `bash -n` 语法检查与
  `--dry-run` 全流程验证；**macOS / Linux 实机执行请以本页命令为准**，若某步在你机器上
  与预期不同，按对应的 `[hint]` 手动步骤处理即可（脚本不会半途改系统）。

## 10. 卸载 / 回滚

脚本只往两个地方写东西，删掉就干净了：

```bash
# 1) pinned REA 安装（第 8 步）+ JADX jar（第 4 步）+ 默认 tools root（第 3/6 步）
rm -rf "$HOME/.rea"

# 2) 如果你用了 --tools-root 指向别处
rm -rf "/your/tools/root"

# 3) 只删 Ghidra zip（想保留解压结果时）
rm -f "$HOME/.rea/tools/ghidra_12.1.4_PUBLIC_20260921.zip"

# 4) 环境变量
launchctl unsetenv GHIDRA_INSTALL_DIR     # macOS
launchctl unsetenv JAVA_HOME
unset GHIDRA_INSTALL_DIR REA_JADX_MCP_JAR REA_ADB_PATH REA_APKTOOL_COMMAND REA_BROWSER_EXECUTABLE   # 当前 shell；wrapper 里删掉对应 export
```

| 只想删 | 命令 | 影响 |
|---|---|---|
| pinned REA 安装 | `rm -rf "$HOME/.rea/dsh"` | 启动器回退到 `npx -y rea-agents@6.4.0 mcp`（需要网络） |
| Ghidra | `rm -rf "$HOME/.rea/tools/ghidra_12.1.4_PUBLIC"` | 原生反编译线关闭 |
| JADX | `rm -f "$HOME/.rea/android/jadx-headless-mcp-0.7.1-all.jar"` | APK 代码反编译关闭 |
| apktool wrapper | `rm -rf "$HOME/.rea/tools/apktool"` | APK 资源解码关闭 |
| 全部 | `rm -rf "$HOME/.rea"` | 只剩插件本体（零依赖能力仍可用） |

> 插件本身（`dsh-rea` bundle）与仓库文件不受影响；卸载插件见 [README.md](../README.md) 的「卸载 / 临时禁用」。
