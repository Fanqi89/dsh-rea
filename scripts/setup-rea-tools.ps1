#requires -Version 5.1
<#
.SYNOPSIS
  REA / dsh-rea 在 Windows 上的可选依赖一键配置脚本（Ghidra + JDK + 技能 + adb + 浏览器路径）。

.DESCRIPTION
  只做“让 REA 的原生反编译、Android、浏览器分析线可用”这件事：
    1. 检查 Node.js / npx
    2. 找到或指定可用的 JDK 21+（Ghidra 需要完整 JDK：java + javac）
    3. 下载并校验、解压 Ghidra 12.1.4，写入 GHIDRA_INSTALL_DIR
    4. 检测 Chrome / Edge，写入 REA_BROWSER_EXECUTABLE
    5. 下载 platform-tools，写入 REA_ADB_PATH
    6. 可选：下载 apktool，写入 REA_APKTOOL_COMMAND
    7. 安装与包版本对齐的 REA 技能（rea setup --skill --yes）
    8. 跑 rea doctor 输出结果

  所有环境变量都写“用户级”（User），不需要管理员权限；已存在且有效的不覆盖。
  改完环境变量必须重启 DeepSeek Harness 才会进入 Agent 的环境。

.PARAMETER DryRun
  只打印将要做什么，不下载、不改环境变量、不写文件。

.PARAMETER ToolsRoot
  工具安装根目录，默认 C:\tools（会自动创建）。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-rea-tools.ps1 -DryRun

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-rea-tools.ps1

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-rea-tools.ps1 -WithApktool
#>
param(
  [string]$ToolsRoot = 'C:\tools',
  [switch]$SkipGhidra,
  [switch]$SkipAdb,
  [switch]$SkipJadx,
  [switch]$WithApktool,
  [switch]$SkipSkill,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ReaPkg = 'rea-agents@6.4.0'

$GhidraVersion = '12.1.4'
$GhidraUrl = 'https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.1.4_build/ghidra_12.1.4_PUBLIC_20260921.zip'
$GhidraSha256 = 'ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db'
$PlatformToolsUrl = 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip'
$JadxVersion = '0.7.1'
$JadxUrl = 'https://github.com/1013503897/jadx-headless-mcp/releases/download/v0.7.1/jadx-headless-mcp-0.7.1-all.jar'
$JadxSha256 = '6e5eacf500b64292bfb73c49797c1958f6ee44646e43e868039ae7feb573ff75'
$ApktoolVersion = '3.0.3'
$ApktoolUrl = 'https://github.com/iBotPeaches/Apktool/releases/download/v3.0.3/apktool_3.0.3.jar'
$ApktoolSha256 = 'dbf930b076c6b9be08d57c449cacefc3bdd6b71ebd59b3066fc0e1f5b14f9423'

function Write-Step([string]$Text) { Write-Host "`n=== $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text) { Write-Host "  [OK]   $Text" -ForegroundColor Green }
function Write-Warn2([string]$Text) { Write-Host "  [WARN] $Text" -ForegroundColor Yellow }
function Write-Info([string]$Text) { Write-Host "  [..]   $Text" }
function Write-Fail([string]$Text) { Write-Host "  [FAIL] $Text" -ForegroundColor Red }

# 原生命令（javac / node / npx）会把版本与进度写到 stderr；在 $ErrorActionPreference='Stop'
# 下 PowerShell 5.1 会把它当成终止性错误，所以统一用这个包装器临时放开。
function Invoke-Native([string]$Exe, [string[]]$CommandArgs) {
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    return (& $Exe @CommandArgs 2>&1 | Out-String)
  } finally {
    $ErrorActionPreference = $prev
  }
}

# 用 .NET ZipFile 解压（PS 5.1 的 Expand-Archive 解 570MB 会很慢）
function Expand-ZipFast([string]$ZipPath, [string]$Destination) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
  $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
  try {
    foreach ($entry in $zip.Entries) {
      $target = Join-Path $Destination $entry.FullName
      if ($entry.FullName.EndsWith('/')) {
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        continue
      }
      $parent = Split-Path $target -Parent
      if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
      [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
    }
  } finally {
    $zip.Dispose()
  }
}

function Set-UserEnv([string]$Name, [string]$Value) {
  if ($DryRun) { Write-Info "would set user env $Name = $Value"; return }
  $current = [Environment]::GetEnvironmentVariable($Name, 'User')
  if ($current -eq $Value) { Write-Ok "$Name already $Value"; return }
  [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
  Set-Item -Path "Env:$Name" -Value $Value -ErrorAction SilentlyContinue
  Write-Ok "set user env $Name = $Value"
}

function Test-UserEnv([string]$Name) {
  $u = [Environment]::GetEnvironmentVariable($Name, 'User')
  if ($u) { return $u }
  return [Environment]::GetEnvironmentVariable($Name, 'Machine')
}

function Invoke-Download([string]$Url, [string]$Dest, [string]$Sha256) {
  if ($DryRun) { Write-Info "would download $Url -> $Dest"; return $false }
  if (Test-Path $Dest) {
    Write-Info "reusing existing download $Dest"
  } else {
    Write-Info "downloading $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
  }
  if ($Sha256) {
    $actual = (Get-FileHash $Dest -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Sha256.ToLowerInvariant()) {
      throw "SHA-256 mismatch for $Dest`n  expected $Sha256`n  actual   $actual"
    }
    Write-Ok "sha256 verified: $([IO.Path]::GetFileName($Dest))"
  }
  return $true
}

function Find-Jdk {
  $candidates = @()
  foreach ($root in @('C:\Program Files\Java', 'C:\Program Files\Eclipse Adoptium', 'C:\Program Files\Microsoft', 'C:\Program Files\Zulu')) {
    if (Test-Path $root) {
      $candidates += Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'jdk' }
    }
  }
  $jdkHome = Test-UserEnv 'JAVA_HOME'
  if ($jdkHome -and (Test-Path (Join-Path $jdkHome 'bin\javac.exe'))) {
    $candidates = @([pscustomobject]@{ FullName = $jdkHome }) + $candidates
  }
  $valid = @()
  foreach ($c in $candidates) {
    $javac = Join-Path $c.FullName 'bin\javac.exe'
    if (-not (Test-Path $javac)) { continue }
    $raw = (Invoke-Native $javac @('-version')).Trim()
    if ($raw -match 'javac\s+(\d+)(?:\.(\d+))?') {
      $major = [int]$Matches[1]
      if ($major -eq 1 -and $Matches[2]) { $major = [int]$Matches[2] }
      if ($major -ge 21) { $valid += [pscustomobject]@{ Path = $c.FullName; Major = $major } }
    }
  }
  return $valid | Sort-Object -Property @{ Expression = { if ($_.Major -eq 21) { 0 } else { 1 } } }, Major | Select-Object -First 1
}

# ---------------------------------------------------------------- 1. Node.js
Write-Step '检查 Node.js / npx'
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
  Write-Fail 'node 不在 PATH 上；REA 需要 Node.js 22.19+ / 24.11+ / 26+，请先安装 Node.js LTS。'
  exit 1
}
$nodeVersion = (Invoke-Native 'node' @('--version')).Trim()
$npx = Get-Command npx.cmd -ErrorAction SilentlyContinue
if (-not $npx) { $npx = Get-Command npx -ErrorAction SilentlyContinue }
$npxExe = $null
if ($npx) { $npxExe = $npx.Source }
Write-Ok "node $nodeVersion"
if (-not $npx) { Write-Warn2 'npx 未找到；后续安装技能与 doctor 会失败' } else { Write-Ok "npx: $($npx.Source)" }

# ---------------------------------------------------------------- 2. JDK
Write-Step '检查 JDK（Ghidra / JADX / apktool 都需要完整 JDK 17+：java + javac）'
$jdk = Find-Jdk
if (-not $jdk) {
  Write-Fail '没有找到 JDK 21+。请安装 Temurin 21 (https://adoptium.net/temurin/releases/?version=21) 后重跑。'
  Write-Warn2 'Ghidra 与 apktool 都需要 JDK；Android/静态分析线不受影响。'
} else {
  Write-Ok "JDK $($jdk.Major): $($jdk.Path)"
  if ((Test-UserEnv 'JAVA_HOME') -ne $jdk.Path) { Set-UserEnv 'JAVA_HOME' $jdk.Path }
}

# ---------------------------------------------------------------- 3. Ghidra
Write-Step "Ghidra $GhidraVersion（Windows 上唯一的原生反汇编 provider）"
$ghidraHome = $null
$existing = Test-UserEnv 'GHIDRA_INSTALL_DIR'
if ($existing -and (Test-Path (Join-Path $existing 'support\analyzeHeadless.bat'))) {
  $ghidraHome = $existing
  Write-Ok "已配置 GHIDRA_INSTALL_DIR = $existing"
} else {
  $found = Get-ChildItem $ToolsRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'ghidra_*' -and (Test-Path (Join-Path $_.FullName 'support\analyzeHeadless.bat')) } |
    Sort-Object Name -Descending | Select-Object -First 1
  if ($found) { $ghidraHome = $found.FullName; Write-Ok "found existing $ghidraHome" }
}
if ($SkipGhidra) {
  Write-Warn2 '跳过 Ghidra（-SkipGhidra）'
} elseif ($ghidraHome) {
  Set-UserEnv 'GHIDRA_INSTALL_DIR' $ghidraHome
} elseif ($DryRun) {
  Write-Info "would download Ghidra (~570 MB) -> $ToolsRoot and set GHIDRA_INSTALL_DIR"
} else {
  New-Item -ItemType Directory -Force -Path $ToolsRoot | Out-Null
  $zip = Join-Path $env:TEMP 'ghidra_12.1.4_PUBLIC_20260921.zip'
  if (Invoke-Download $GhidraUrl $zip $GhidraSha256) {
    Write-Info 'extracting (570 MB, 需要几分钟)…'
    Expand-ZipFast $zip $ToolsRoot
    $ghidraHome = (Get-ChildItem $ToolsRoot -Directory |
      Where-Object { $_.Name -like 'ghidra_*' -and (Test-Path (Join-Path $_.FullName 'support\analyzeHeadless.bat')) } |
      Sort-Object Name -Descending | Select-Object -First 1).FullName
    if (-not $ghidraHome) { throw '解压后没找到 support\analyzeHeadless.bat，请检查压缩包内容' }
    Set-UserEnv 'GHIDRA_INSTALL_DIR' $ghidraHome
  }
}
if ($ghidraHome) { Write-Info "Ghidra 目录: $ghidraHome" }

# ---------------------------------------------------------------- 4. 浏览器
Write-Step '浏览器（REA 的浏览器/CDP 抓取线）'
$browser = $null
foreach ($p in @(
    'C:\Program Files\Google\Chrome\Application\chrome.exe',
    'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
    'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    'C:\Program Files\Microsoft\Edge\Application\msedge.exe')) {
  if (Test-Path $p) { $browser = $p; break }
}
$existingBrowser = Test-UserEnv 'REA_BROWSER_EXECUTABLE'
if ($existingBrowser -and (Test-Path $existingBrowser)) {
  Write-Ok "已配置 REA_BROWSER_EXECUTABLE = $existingBrowser"
} elseif ($browser) {
  Set-UserEnv 'REA_BROWSER_EXECUTABLE' $browser
} else {
  Write-Warn2 '没找到 Chrome/Edge；可手动设置 REA_BROWSER_EXECUTABLE 指向 chrome.exe/msedge.exe'
}

# ---------------------------------------------------------------- 5. adb
Write-Step 'Android platform-tools（adb）'
if ($SkipAdb) {
  Write-Warn2 '跳过 adb（-SkipAdb）'
} else {
  $adb = $null
  $configuredAdb = Test-UserEnv 'REA_ADB_PATH'
  if ($configuredAdb -and (Test-Path $configuredAdb)) { $adb = $configuredAdb; Write-Ok "已配置 REA_ADB_PATH = $configuredAdb" }
  if (-not $adb) {
    $onPath = Get-Command adb -ErrorAction SilentlyContinue
    if ($onPath) { $adb = $onPath.Source; Write-Ok "PATH 上的 adb: $adb" }
  }
  if (-not $adb -and -not $DryRun) {
    New-Item -ItemType Directory -Force -Path $ToolsRoot | Out-Null
    $zip = Join-Path $env:TEMP 'platform-tools-latest-windows.zip'
    if (Invoke-Download $PlatformToolsUrl $zip '') {
      Expand-ZipFast $zip $ToolsRoot
      $candidate = Join-Path $ToolsRoot 'platform-tools\adb.exe'
      if (Test-Path $candidate) { $adb = $candidate } else { Write-Warn2 '解压后没找到 adb.exe' }
    }
  }
  if ($adb) { Set-UserEnv 'REA_ADB_PATH' $adb } elseif ($DryRun) { Write-Info 'would download platform-tools and set REA_ADB_PATH' }
}

# ---------------------------------------------------------------- JADX
Write-Step 'JADX（APK 代码反编译：inspect_android_package / search_android_classes / inspect_android_class / inspect_android_method / trace_android_references）'
$jadxJar = $null
$configuredJar = Test-UserEnv 'REA_JADX_MCP_JAR'
if ($configuredJar -and (Test-Path $configuredJar)) {
  $jadxJar = $configuredJar
  Write-Ok "已配置 REA_JADX_MCP_JAR = $configuredJar"
} elseif (-not $jdk) {
  Write-Warn2 '没有可用 JDK，JADX 无法运行；跳过（静态 APK 归档分析仍可用）'
} elseif ($SkipJadx) {
  Write-Warn2 '跳过 JADX（-SkipJadx）'
} elseif ($DryRun) {
  Write-Info "would download jadx-headless-mcp $JadxVersion (~42 MB) and set REA_JADX_MCP_JAR"
} else {
  $jadxDir = Join-Path $env:LOCALAPPDATA 'rea\android'
  New-Item -ItemType Directory -Force -Path $jadxDir | Out-Null
  $jadxJar = Join-Path $jadxDir "jadx-headless-mcp-$JadxVersion-all.jar"
  if (Invoke-Download $JadxUrl $jadxJar $JadxSha256) { Set-UserEnv 'REA_JADX_MCP_JAR' $jadxJar }
}

# ---------------------------------------------------------------- apktool
Write-Step 'apktool（可选，APK 资源解码；与 JDK 配套）'
if (-not $WithApktool) {
  Write-Info '未指定 -WithApktool，跳过（需要时加该参数重跑）'
} elseif (-not $jdk) {
  Write-Warn2 '没有可用 JDK，apktool 无法运行，跳过'
} else {
  $existingTool = Test-UserEnv 'REA_APKTOOL_COMMAND'
  if ($existingTool -and (Test-Path $existingTool)) {
    Write-Ok "已配置 REA_APKTOOL_COMMAND = $existingTool"
  } elseif ($DryRun) {
    Write-Info "would download apktool $ApktoolVersion and write $ToolsRoot\apktool\apktool.bat"
  } else {
    $apkDir = Join-Path $ToolsRoot 'apktool'
    New-Item -ItemType Directory -Force -Path $apkDir | Out-Null
    $jar = Join-Path $apkDir "apktool_$ApktoolVersion.jar"
    if (Invoke-Download $ApktoolUrl $jar $ApktoolSha256) {
      # REA 用 shell-free execFile 启动 launcher；Windows 上 .bat 不能被直接执行，
      # 所以编译一个 apktool.exe 转发到 java -jar apktool.jar（模板见同目录 apktool-shim.cs）。
      $shimTemplate = Join-Path $PSScriptRoot 'apktool-shim.cs'
      $java = Join-Path $jdk.Path 'bin\java.exe'
      if (-not (Test-Path $shimTemplate)) {
        Write-Warn2 "缺少启动器模板 $shimTemplate；请在仓库 scripts 目录下运行本脚本"
      } else {
        $cs = (Get-Content $shimTemplate -Raw -Encoding UTF8).Replace('__JAVA__', $java).Replace('__JAR__', $jar)
        $csPath = Join-Path $apkDir 'ApktoolShim.cs'
        $shimExe = Join-Path $apkDir 'apktool.exe'
        Set-Content -Path $csPath -Value $cs -Encoding UTF8
        if (Test-Path $shimExe) { Remove-Item $shimExe -Force }
        Add-Type -TypeDefinition $cs -Language CSharp -OutputAssembly $shimExe -OutputType ConsoleApplication -ErrorAction Stop
        $reported = (Invoke-Native $shimExe @('--version')).Trim()
        if ($reported -match '^\d+(\.\d+)+') {
          Write-Ok "wrote $shimExe (reports $reported)"
          Set-UserEnv 'REA_APKTOOL_COMMAND' $shimExe
        } else {
          Write-Warn2 "编译出的 $shimExe 未报告版本：$reported"
        }
      }
    }
  }
}

# ---------------------------------------------------------------- REA 技能
Write-Step 'REA 技能（与 rea-agents 包版本对齐）'
if ($SkipSkill) {
  Write-Warn2 '跳过技能安装（-SkipSkill）'
} elseif ($DryRun) {
  Write-Info "would run npx -y $ReaPkg setup --skill --yes"
} elseif ($npx) {
  $out = Invoke-Native $npxExe @('-y', $ReaPkg, 'setup', '--skill', '--yes')
  $out.Trim() -split "`n" | Select-Object -Last 8 | ForEach-Object { Write-Info $_.Trim() }
  Write-Ok '技能安装流程结束（doctor 第 8 步会复核）'
} else {
  Write-Warn2 '缺少 npx，跳过技能安装'
}

# ---------------------------------------------------------------- doctor
Write-Step 'rea doctor 复核'
if ($DryRun) {
  Write-Info "would run npx -y $ReaPkg doctor --json"
} elseif ($npx) {
  $json = Invoke-Native $npxExe @('-y', $ReaPkg, 'doctor', '--json')
  try {
    $doc = $json | ConvertFrom-Json
    Write-Info "healthy: $($doc.healthy)   environment_healthy: $($doc.environment_healthy)"
    foreach ($c in $doc.checks) {
      $mark = if ($c.ok) { 'OK  ' } else { 'MISS' }
      $detail = $c.detail
      if (-not $detail) { $detail = $c.remediation }
      Write-Info ("{0} {1,-22} {2} {3}" -f $mark, $c.name, $c.classification, $detail)
    }
  } catch {
    Write-Warn2 "doctor 输出无法解析：$json"
  }
}

Write-Host "`n完成。`n" -ForegroundColor Cyan
Write-Host '下一步（必须做）：完全重启 DeepSeek Harness，让新的用户级环境变量进入 Agent 进程。' -ForegroundColor Yellow
Write-Host '重启后在 DSH 里验证：' -ForegroundColor Yellow
Write-Host '  - 原生：open_binary <某个 exe> → analyze_function / procedure_pseudo_code'
Write-Host '  - Android：inspect_adb_client / list_adb_devices'
Write-Host '  - 浏览器：list_browser_targets'
