#requires -Version 5.1
<#
.SYNOPSIS
  Prepare the Linux-only side of REA on Windows through WSL 2.

.DESCRIPTION
  REA gates several families to Linux:
    - inspect_binary_layout / inspect_recorded_crash (pwntools, gdb)
    - inspect_firmware_regions / extract_firmware   (binwalk / unblob)
    - inspect_web_network_capture (native mitmproxy captures)
    - the Linux analysis paths behind .deb / ELF targets
  Those cannot run on the Windows process directly, so this script prepares a
  WSL 2 Ubuntu distribution and installs the toolchain inside it, then prints
  the MCP command that exposes a second REA server (serverName "rea-linux") to
  the Harness.

  WSL itself needs one reboot after the optional features are enabled: run this
  script once, reboot, run it again to import the distribution and install the
  tools.

.PARAMETER Distribution
  WSL distribution name to create or reuse. Default: Ubuntu-24.04

.PARAMETER InstallPath
  Directory the imported distribution's virtual disk lives in. Default: C:\wsl\Ubuntu-24.04

.PARAMETER RootfsUrl
  Ubuntu base rootfs tarball used for the first import.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-wsl-linux-toolchain.ps1
#>
param(
  [string]$Distribution = 'Ubuntu-24.04',
  [string]$InstallPath = 'C:\wsl\Ubuntu-24.04',
  [string]$RootfsUrl = 'https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.3-base-amd64.tar.gz',
  [switch]$DryRun,
  [switch]$SkipFeatureCheck
)

$ErrorActionPreference = 'Stop'
function Write-Step([string]$t) { Write-Host "`n=== $t" -ForegroundColor Cyan }
function Write-Ok([string]$t) { Write-Host "  [OK]   $t" -ForegroundColor Green }
function Write-Info([string]$t) { Write-Host "  [..]   $t" }
function Write-Warn2([string]$t) { Write-Host "  [WARN] $t" -ForegroundColor Yellow }

$rootfs = 'C:\tools\wsl\ubuntu-base-24.04.tar.gz'
$kernelMsi = 'C:\tools\wsl\wsl_update_x64.msi'

function Test-Admin {
  return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WslDistros {
  try { return (& wsl.exe -l -q 2>$null) } catch { return @() }
}

function Invoke-Download([string]$url, [string]$dest) {
  if (Test-Path $dest) { Write-Info "reusing $dest"; return }
  if ($DryRun) { Write-Info "would download $url -> $dest"; return }
  New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
  & curl.exe -L --fail -o $dest $url
  if (-not (Test-Path $dest)) { throw "download failed: $url" }
}

# ---------------------------------------------------------------- features
Write-Step '1/5 WSL 可选功能'
if (-not $SkipFeatureCheck) {
  if (-not (Test-Admin)) {
    Write-Warn2 '需要管理员权限来启用 WSL 功能；请用“以管理员身份运行”的 PowerShell 重跑本脚本。'
  } else {
    $wslFeature = (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue).State
    $vmFeature = (Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue).State
    Write-Info "Microsoft-Windows-Subsystem-Linux = $wslFeature"
    Write-Info "VirtualMachinePlatform            = $vmFeature"
    if ($DryRun) {
      Write-Info 'would run dism /online /enable-feature ... /norestart for both features'
    } elseif ($wslFeature -ne 'Enabled' -or $vmFeature -ne 'Enabled') {
      & dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
      & dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null
      Write-Ok 'features enabled (reboot required)'
    }
  }
}

# ---------------------------------------------------------------- kernel
Write-Step '2/5 WSL 2 内核'
if ($DryRun) {
  Write-Info "would install $kernelMsi silently if missing"
} elseif (-not (Test-Path $kernelMsi)) {
  Invoke-Download 'https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi' $kernelMsi
  Write-Ok "downloaded $(Split-Path $kernelMsi -Leaf)"
}
if (Test-Path $kernelMsi) { Write-Ok 'kernel package present' }

# ---------------------------------------------------------------- import
Write-Step "3/5 导入发行版 $Distribution"
$distros = @(Get-WslDistros)
Write-Info ("已安装发行版: " + (($distros | Where-Object { $_ }) -join ', '))
if ($distros -contains $Distribution) {
  Write-Ok "$Distribution 已存在，跳过导入"
} elseif ($DryRun) {
  Write-Info "would import $Distribution from $rootfs into $InstallPath (wsl --import --version 2)"
} else {
  try {
    & wsl.exe --set-default-version 2 2>&1 | Out-Null
  } catch { Write-Warn2 "wsl --set-default-version 失败（可能仍需要重启）" }
  Invoke-Download $RootfsUrl $rootfs
  New-Item -ItemType Directory -Force $InstallPath | Out-Null
  & wsl.exe --import $Distribution $InstallPath $rootfs --version 2
  if ($LASTEXITCODE -ne 0) {
    Write-Warn2 '导入失败：如果这是首次启用 WSL，请重启 Windows 后再运行本脚本。'
    exit 2
  }
  Write-Ok "已导入 $Distribution"
}

# ---------------------------------------------------------------- tools
Write-Step '4/5 安装 Linux 侧工具链'
$setupScript = Join-Path $PSScriptRoot 'linux-tools-setup.sh'
if (-not (Test-Path $setupScript)) { throw "缺少 $setupScript" }
if ($DryRun) {
  Write-Info "would copy linux-tools-setup.sh into $Distribution and run it as root"
} else {
  # 复制进 WSL 前把 CRLF 收敛成 LF：Windows 检出的脚本常带 CR，bash 会报
  # `$'\r': command not found`，heredoc 也会把 CR 写进脚本。
  $bashScript = (Get-Content $setupScript -Raw).Replace("`r`n", "`n")
  & wsl.exe -d $Distribution -u root -- bash -c "cat > /root/linux-tools-setup.sh <<'EOS'
$bashScript
EOS
chmod +x /root/linux-tools-setup.sh && bash /root/linux-tools-setup.sh"
  if ($LASTEXITCODE -ne 0) { Write-Warn2 "工具链安装返回 $LASTEXITCODE，请检查上面的输出" } else { Write-Ok '工具链安装完成' }
}

# ---------------------------------------------------------------- next step
Write-Step '5/5 在 DSH 里接入 Linux REA 实例（可选）'
Write-Info 'Windows 侧的 REA 用 win32 判定平台，Linux 专属工具只能在 Linux 实例里跑。'
Write-Info '本仓库的 cordis.patch.yml 已内置一行被禁用的 `rea-linux`：'
Write-Info ''
Write-Info '    - id: rea-linux'
Write-Info "      name: '@deepseek-ai/dsh-mcp-client'"
Write-Info '      disabled: true          # 把这里改成 false 并重启 Harness'
Write-Info '      config:'
Write-Info '        serverName: rea-linux'
Write-Info "        command: wsl.exe"
Write-Info "        args: ['-d', '$Distribution', '-u', 'root', '--', 'npx', '-y', 'rea-agents@6.4.0', 'mcp']"
Write-Info ''
Write-Info '启用后 Linux 专属工具会以 mcp__rea-linux__* 出现（约 170 个，token 成本翻倍，按需开启）。'

Write-Host "`n完成。若刚启用 WSL 功能，请先重启 Windows，再运行一次本脚本。`n" -ForegroundColor Yellow
