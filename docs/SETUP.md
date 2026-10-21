# 环境配置（Windows / macOS / Linux）

> 插件本体零依赖；这份文档只解决「要反编译**原生二进制**、**APK 代码/资源**、**Android 设备**、**浏览器页面**时还缺什么」。
> 一键脚本：[`scripts/setup-rea-tools.ps1`](../scripts/setup-rea-tools.ps1)（Windows）。macOS / Linux 用本文档里的手动步骤。

## 0. 依赖总览

| 能力 | 需要什么 | 本仓库负责 |
|---|---|---|
| 静态 JS / Electron / ASAR、.NET(PE/CLI)、PE 资源、通用归档、EVM | 无 | — |
| **APK 代码反编译**（类/方法/引用） | **完整 JDK 17+** + `jadx-headless-mcp 0.7.1` JAR + `REA_JADX_MCP_JAR` | 脚本自动 |
| **APK 资源/资源表** | **apktool** + `REA_APKTOOL_COMMAND` | 脚本 `-WithApktool` |
| **原生二进制反编译**（伪代码/汇编/引用/调用图） | **Ghidra 12.1.x**（或 IDA / Hopper）+ `GHIDRA_INSTALL_DIR` | 脚本自动 |
| **Android 设备**（装/拉 APK、logcat、截图） | **adb**（platform-tools）+ `REA_ADB_PATH` | 脚本自动 |
| **浏览器/CDP**（页面结构、截图、网络、场景） | Chrome / Edge + `REA_BROWSER_EXECUTABLE` | 脚本自动检测 |
| JEB 项目 | 已启动的 JEB 客户端 + `REA_JEB_MCP_URL` | 手动 |
| 固件解包、ELF 布局、core、mitmproxy | Linux 专属工具（binwalk / unblob / pwntools / mitmdump） | 平台限制 |
| 进程行为捕获 | Linux/macOS PTY | 平台限制 |

## 1. 一键脚本（Windows，推荐）

```powershell
# 预览，不下载、不改环境
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-rea-tools.ps1 -DryRun

# 正式执行：JDK 探测 + Ghidra + 浏览器 + adb + JADX + 技能 + doctor
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-rea-tools.ps1

# 额外装 apktool（APK 资源解码）
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-rea-tools.ps1 -WithApktool
```

参数：`-ToolsRoot C:\tools`、`-SkipGhidra`、`-SkipAdb`、`-SkipJadx`、`-SkipSkill`、`-WithApktool`、`-DryRun`。

脚本只写**用户级**环境变量（不需要管理员），已存在且有效的值不覆盖；下载物均做 SHA-256 校验：

| 下载物 | 版本 | SHA-256 |
|---|---|---|
| Ghidra | 12.1.4（约 570 MB） | `ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db` |
| jadx-headless-mcp | 0.7.1（约 42 MB） | `6e5eacf500b64292bfb73c49797c1958f6ee44646e43e868039ae7feb573ff75` |
| apktool | 3.0.3（约 15 MB） | `dbf930b076c6b9be08d57c449cacefc3bdd6b71ebd59b3066fc0e1f5b14f9423` |

> **改完环境变量必须重启 DeepSeek Harness**：REA 子进程的环境继承自 Harness 主进程，热改不生效。

> **GitHub 直连超时怎么办**：脚本用 `Invoke-WebRequest` 直连 GitHub Release；若卡住/超时
> （国内网络常见），可改用镜像前缀手动下载，再重跑脚本（脚本发现文件已存在会跳过下载，
> 仍做 SHA-256 校验，因此镜像下载同样安全）：
>
> ```powershell
> $url = "https://ghproxy.net/https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.1.4_build/ghidra_12.1.4_PUBLIC_20260921.zip"
> $zip = Join-Path $env:TEMP 'ghidra_12.1.4_PUBLIC_20260921.zip'
> curl.exe -L --fail -o $zip $url
> powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-rea-tools.ps1 -WithApktool
> ```

## 2. 手动步骤

### 2.1 Ghidra（原生反编译）

1. 下载 `ghidra_12.1.4_PUBLIC_20260921.zip`（[release](https://github.com/NationalSecurityAgency/ghidra/releases/tag/Ghidra_12.1.4_build)）并解压到 `C:\tools\`，得到 `C:\tools\ghidra_12.1.4_PUBLIC\`（含 `support\analyzeHeadless.bat`）。
2. 设置环境变量：

```powershell
[Environment]::SetEnvironmentVariable('GHIDRA_INSTALL_DIR','C:\tools\ghidra_12.1.4_PUBLIC','User')
[Environment]::SetEnvironmentVariable('JAVA_HOME','C:\Program Files\Java\jdk-21.0.11','User')
```

3. 重启 Harness。首次原生查询会启动 Ghidra 导入 + 自动分析，按目标大小可能几分钟；可用 `GHIDRA_HEADLESS_MAXMEM`、`REA_GHIDRA_STARTUP_TIMEOUT_MS` 调整。

### 2.2 JADX（APK 代码反编译）

```powershell
$jar = Join-Path $env:LOCALAPPDATA 'rea\android\jadx-headless-mcp-0.7.1-all.jar'
New-Item -ItemType Directory -Force (Split-Path $jar) | Out-Null
Invoke-WebRequest 'https://github.com/1013503897/jadx-headless-mcp/releases/download/v0.7.1/jadx-headless-mcp-0.7.1-all.jar' -OutFile $jar
# 校验 SHA-256 后：
[Environment]::SetEnvironmentVariable('REA_JADX_MCP_JAR',$jar,'User')
[Environment]::SetEnvironmentVariable('JAVA_HOME','C:\Program Files\Java\jdk-21.0.11','User')
```

可选调优：`REA_JADX_HEAP_MIB=8192`、`REA_JADX_OPERATION_TIMEOUT_MS=600000`（大 multidex 冷加载）。

### 2.3 adb（Android 设备）

```powershell
Invoke-WebRequest 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' -OutFile "$env:TEMP\platform-tools.zip"
Expand-Archive "$env:TEMP\platform-tools.zip" -DestinationPath 'C:\tools' -Force
[Environment]::SetEnvironmentVariable('REA_ADB_PATH','C:\tools\platform-tools\adb.exe','User')
```

### 2.4 apktool（APK 资源）

apktool 官方只提供 `.jar` + `.bat` 启动器，而 REA 用 **shell-free `execFile`** 调用 launcher
（`<launcher> --version`、`<launcher> d …`）——Windows 上 `.bat` 不能被那样直接执行。
所以这里编译一个 4 KB 的 `apktool.exe` 转发器（源码模板：[`scripts/apktool-shim.cs`](../scripts/apktool-shim.cs)），
把参数原样转给 `java -jar apktool.jar` 并转发输出。脚本会自动完成这一步。

```powershell
# 一键（会自动下载 jar、编译 shim、写环境变量）
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-rea-tools.ps1 -WithApktool

# 手动：下载 jar 后，用 scripts/apktool-shim.cs 把 __JAVA__ / __JAR__ 替换掉再编译
Add-Type -TypeDefinition $cs -Language CSharp -OutputAssembly C:\tools\apktool\apktool.exe -OutputType ConsoleApplication
[Environment]::SetEnvironmentVariable('REA_APKTOOL_COMMAND','C:\tools\apktool\apktool.exe','User')
```

> 本机实测：`inspect-apktool-client` 报 `3.0.3`；`decode-android-resources` 解出完整
> AndroidManifest、`com.llw / 1.0 / sdk16-30`、字符串 `app_name=纳西妲送你的礼物`、14 个解码文件。
> 直接指向 `.bat` 会报 `version_unresolved`（这是 REA 6.4.0 的 Windows 启动器限制，不是配置错误）。

### 2.5 浏览器

```powershell
[Environment]::SetEnvironmentVariable('REA_BROWSER_EXECUTABLE','C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe','User')
```

### 2.6 macOS / Linux

- 原生：安装 Ghidra 后 `export GHIDRA_INSTALL_DIR=...`（Hopper 仅 macOS；IDA 任意平台 + `REA_IDA_MCP_CONFIG`）。
- JADX/apktool/adb 同理，用 `export REA_JADX_MCP_JAR=…`、`REA_APKTOOL_COMMAND=…`、`REA_ADB_PATH=…`。
- Linux 额外可用：`inspect_binary_layout`（pwntools）、core 分析、binwalk/unblob 固件、mitmproxy 抓包、进程捕获。

### 2.7 Windows 上的 Linux 专属线（WSL 2）

REA 对 Linux 门禁的能力（ELF 布局、崩溃 core、固件、原生 mitmproxy 抓包、PTY 进程捕获、
`import-reference-source`）在 `win32` 进程里会返回 `unsupported_host`；`.deb` / Linux 应用也只能在
Linux 主机上直接打开。做法是准备一个 **Linux REA 实例**（第二个 MCP server，`serverName: rea-linux`）：

```powershell
# 一次：启用 WSL 功能 + 装内核 + 导入 Ubuntu 24.04 + 装工具链
#      首次启用 WSL 会要求重启；重启后再跑一次完成导入与安装
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-wsl-linux-toolchain.ps1

# 之后：把 cordis.patch.yml 里 rea-linux 的 disabled: true 改成 false，重启 Harness
```

WSL 内由 `scripts/linux-tools-setup.sh` 安装：`python3-pip`、`pipx` 管理的 **pwntools / binwalk /
unblob / mitmproxy**，以及 `binutils file gdb xz-utils p7zip-full dpkg-dev`、**Node.js 22** 和
`rea-agents 6.4.0`。发行版默认导入到 `C:\wsl\Ubuntu-24.04`，可用 `-Distribution` / `-InstallPath` 改。

只用 `.deb` 拆包、不装 WSL 时，Windows 侧可用 7-Zip 独立版：

```powershell
& "C:\tools\7zip\7zr.exe" x .\pkg.deb          # ar 包 → control.tar.* / data.tar.*
& "C:\tools\7zip\7zr.exe" x .\data.tar.xz      # → ELF、资源、目录树
```

> ELF 的反编译本身仍走 Linux 实例（`mcp__rea-linux__open_binary` + `analyze_function`）。

## 3. 技能

```bash
npx -y rea-agents@6.4.0 setup --skill --yes     # 装到 ~/.agents/skills/reverse-engineer-anything
npx -y rea-agents@6.4.0 doctor --skill --json   # 期望 identity.skill.state = aligned
```

## 4. 验证

```bash
npx -y rea-agents@6.4.0 doctor --json      # 配置类问题看这里（改环境变量后需重启）
npx -y rea-agents@6.4.0 providers --json   # 已配置的 provider
npx -y rea-agents@6.4.0 capabilities --json# 每个操作的 available / 平台原因
```

Harness 内真调用见 [CAPABILITIES.md](CAPABILITIES.md#验证清单)。
