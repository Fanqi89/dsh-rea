#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# dsh-rea - POSIX setup for REA's optional dependencies (macOS / Linux).
#
# The REA MCP server itself is started by the tiny Node launcher inside
# cordis.patch.yml, which resolves the server entry in this order:
#   1. $REA_MCP_ENTRY                     (only if you set it yourself)
#   2. $HOME/.rea/dsh/agents/6.4.0/node_modules/rea-agents/scripts/rea.mjs
#                                         (pinned local install - step 8 here)
#   3. npx -y rea-agents@6.4.0 mcp        (network fallback, not provisioned)
# Layer 2 is spawned with the Node bundled with DSH, so it needs no npx, no
# network and no dependency on the user's Node on PATH at launch time.
#
# The rest of this script provisions the OPTIONAL analysis lanes (none of them
# is required for the MCP server to start):
#   Ghidra 12.1.4   native decompilation provider  GHIDRA_INSTALL_DIR
#   JADX 0.7.1      APK code decompilation         REA_JADX_MCP_JAR
#   adb             Android devices                REA_ADB_PATH
#   apktool         APK resources                  REA_APKTOOL_COMMAND
#   Chrome/Chromium browser lane                   REA_BROWSER_EXECUTABLE
#
# Design constraints:
#   * runs on macOS's stock bash 3.2: no associative arrays, no ${var,,},
#     no mapfile/readarray, no bash-4-only arithmetic.
#   * never installs system packages and never edits shell profiles: every
#     missing prerequisite is printed as a [hint] with the exact command for
#     the detected package manager.
#   * --dry-run prints every action and changes nothing (safe to run under
#     Git Bash / MSYS on Windows as well).
#
# Markers: [ok] verified, [skip] already present (or skipped by a flag),
#          [hint] manual step, [warn] optional step failed, [fail] hard failure.
# Exit codes: 0 done (optionally with [warn]s), 1 hard failure, 2 usage error.
# ---------------------------------------------------------------------------

set -euo pipefail

REA_VERSION="6.4.0"
REA_PKG="rea-agents@${REA_VERSION}"

# Release asset names verified live on 2026-11-07 (see docs/SETUP-POSIX.md):
#   ghidra_12.1.4_PUBLIC_20260921.zip -> HTTP 200 (20250826 -> HTTP 404)
# The SHA-256 below is the value pinned by scripts/setup-rea-tools.ps1 and
# docs/SETUP.md.
GHIDRA_VERSION="12.1.4"
GHIDRA_ASSET="ghidra_12.1.4_PUBLIC_20260921.zip"
GHIDRA_URL="https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.1.4_build/${GHIDRA_ASSET}"
GHIDRA_SHA256="ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db"

# jadx-headless-mcp is published by 1013503897/jadx-headless-mcp (the
# morluto/... path that appears in some notes returns HTTP 404).
JADX_VERSION="0.7.1"
JADX_ASSET="jadx-headless-mcp-0.7.1-all.jar"
JADX_URL="https://github.com/1013503897/jadx-headless-mcp/releases/download/v${JADX_VERSION}/${JADX_ASSET}"
JADX_SHA256="6e5eacf500b64292bfb73c49797c1958f6ee44646e43e868039ae7feb573ff75"

DRY_RUN=0
SKIP_GHIDRA=0
SKIP_JADX=0
SKIP_ADB=0
SKIP_APKTOOL=0
SKIP_AGENTS=0
TOOLS_ROOT="${REA_TOOLS_ROOT:-$HOME/.rea/tools}"
APKTOOL_JAR_OPT=""

OS_KIND="other"
OS_RAW=""
ARCH=""

OK_COUNT=0
SKIP_COUNT=0
HINT_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
HARD_FAIL=0

ENV_JAVA=""
ENV_GHIDRA=""
ENV_JADX=""
ENV_ADB=""
ENV_APKTOOL=""
ENV_BROWSER=""

NODE_BIN=""
NPM_BIN=""
NODE_OK=0
JAVA_BIN=""
JAVA_MAJOR=""

# --------------------------------------------------------------- output ----
step() { printf '\n== %s\n' "$1"; }
log_info() { printf '         %s\n' "$1"; }
log_ok() {
  printf '  [ok]   %s\n' "$1"
  OK_COUNT=$((OK_COUNT + 1))
}
log_skip() {
  printf '  [skip] %s\n' "$1"
  SKIP_COUNT=$((SKIP_COUNT + 1))
}
log_hint() {
  printf '  [hint] %s\n' "$1"
  HINT_COUNT=$((HINT_COUNT + 1))
}
log_warn() {
  printf '  [warn] %s\n' "$1"
  WARN_COUNT=$((WARN_COUNT + 1))
}
log_fail() {
  printf '  [fail] %s\n' "$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}
die() {
  printf 'error: %s\n' "$1" >&2
  printf 'try: bash %s --help\n' "$0" >&2
  exit 2
}

usage() {
  cat <<'USAGE_EOF'
dsh-rea - POSIX setup for REA's optional dependencies (macOS / Linux).

USAGE
  bash scripts/setup-rea-tools.sh [options]

OPTIONS
  --dry-run            Print every action, change nothing, exit 0.
  --tools-root DIR     Where downloaded tools are unpacked.
                       Default: ${REA_TOOLS_ROOT:-$HOME/.rea/tools}
  --apktool-jar PATH   Use this apktool jar (otherwise common paths are probed).
  --skip-ghidra        Do not download/verify Ghidra (native lane stays off).
  --skip-jadx          Do not download the JADX headless MCP jar.
  --skip-adb           Do not look for adb.
  --skip-apktool       Do not write the apktool wrapper.
  --skip-agents        Do not provision the pinned REA MCP install (layer 2);
                       the launcher then falls back to npx.
  -h, --help           Show this help.

WHAT IT DOES (in order)
  1. Node.js: require ^22.19.0 || ^24.11.0 || >=26.0.0 (REA's engines).
  2. JDK 21+: detect JAVA_HOME or java on PATH.
  3. Ghidra 12.1.4: download (SHA-256 pinned), unzip into --tools-root.
  4. JADX 0.7.1 headless MCP jar.
  5. adb (Android platform-tools) detection.
  6. apktool: write an executable POSIX wrapper for REA_APKTOOL_COMMAND.
  7. Chrome / Chromium detection for the browser lane.
  8. Pinned REA MCP install (npm --prefix ~/.rea/dsh/agents/6.4.0).
  9. Summary: copy-pasteable exports, how to make them reach DSH, and the
     JSON-RPC probe that proves the server is reachable.

NOTES
  * Nothing is installed system-wide: missing prerequisites are printed as
    [hint] lines with the command for the detected package manager.
  * No shell profile is modified. Variables only matter for the DSH process
    that launches the MCP server (see docs/SETUP-POSIX.md).
  * The pinned local REA install needs no REA_* variable at all: the launcher
    resolves it by path and spawns it with DSH's bundled Node.
  * Exit codes: 0 = done (maybe with [warn]), 1 = hard failure, 2 = usage.
USAGE_EOF
}

# ------------------------------------------------------------- helpers ----
lower() {
  printf '%s' "$1" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz'
}

# version_ge A B -> true when A >= B, comparing up to three dotted components.
version_ge() {
  local a b i av bv
  a="$1"
  b="$2"
  a="${a%%-*}"
  a="${a%%+*}"
  b="${b%%-*}"
  b="${b%%+*}"
  i=1
  while [ "$i" -le 3 ]; do
    av=$(printf '%s\n' "$a" | cut -d. -f"$i" | tr -cd '0123456789')
    bv=$(printf '%s\n' "$b" | cut -d. -f"$i" | tr -cd '0123456789')
    if [ -z "$av" ]; then av=0; fi
    if [ -z "$bv" ]; then bv=0; fi
    if [ "$av" -gt "$bv" ]; then return 0; fi
    if [ "$av" -lt "$bv" ]; then return 1; fi
    i=$((i + 1))
  done
  return 0
}

# node_engines_ok VERSION -> true when it satisfies ^22.19.0 || ^24.11.0 || >=26.0.0
node_engines_ok() {
  local v major
  v="$1"
  v="${v#v}"
  major=$(printf '%s\n' "$v" | cut -d. -f1 | tr -cd '0123456789')
  if [ -z "$major" ]; then return 1; fi
  if [ "$major" -eq 22 ]; then
    if version_ge "$v" "22.19.0"; then return 0; fi
    return 1
  fi
  if [ "$major" -eq 24 ]; then
    if version_ge "$v" "24.11.0"; then return 0; fi
    return 1
  fi
  if [ "$major" -ge 26 ]; then return 0; fi
  return 1
}

# sha256_of FILE -> prints lowercase digest, or returns 1 when no tool exists.
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
    return 0
  fi
  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$1" | sed -n 's/.*= *//p'
    return 0
  fi
  return 1
}

# dq STRING -> STRING double-quoted and escaped for a /bin/sh command line.
dq() {
  printf '"%s"' "$(printf '%s' "$1" | sed -e 's/[\\"$`]/\\&/g')"
}

# ------------------------------------------------------------- platform ----
detect_platform() {
  OS_RAW=$(uname -s 2>/dev/null || printf 'unknown')
  ARCH=$(uname -m 2>/dev/null || printf 'unknown')
  case "$OS_RAW" in
    Darwin) OS_KIND="macos" ;;
    Linux) OS_KIND="linux" ;;
    *) OS_KIND="other" ;;
  esac
}

has_apt() { command -v apt-get >/dev/null 2>&1; }
has_dnf() { command -v dnf >/dev/null 2>&1; }
has_pacman() { command -v pacman >/dev/null 2>&1; }

hint_node() {
  case "$OS_KIND" in
    macos)
      printf 'brew install node   # Node 24/26 satisfy REA; node@22 also works: brew install node@22'
      ;;
    linux)
      if has_apt; then
        printf 'curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt-get install -y nodejs   # distro nodejs can be too old'
      elif has_dnf; then
        printf 'sudo dnf install -y nodejs   # needs 22.19+/24.11+/26+; otherwise NodeSource 22.x or nvm'
      elif has_pacman; then
        printf 'sudo pacman -S --needed nodejs npm'
      else
        printf 'install Node.js ^22.19.0 || ^24.11.0 || >=26.0.0 from https://nodejs.org/en/download'
      fi
      ;;
    *)
      printf 'install Node.js ^22.19.0 || ^24.11.0 || >=26.0.0 from https://nodejs.org/en/download'
      ;;
  esac
}

hint_jdk() {
  case "$OS_KIND" in
    macos)
      printf 'brew install --cask temurin@21   # or any JDK 21+ from https://adoptium.net/temurin/releases/?version=21'
      ;;
    linux)
      if has_apt; then
        printf 'sudo apt-get install -y openjdk-21-jdk'
      elif has_dnf; then
        printf 'sudo dnf install -y java-21-openjdk-devel'
      elif has_pacman; then
        printf 'sudo pacman -S --needed jdk21-openjdk'
      else
        printf 'install a JDK 21+ from https://adoptium.net/temurin/releases/?version=21'
      fi
      ;;
    *)
      printf 'install a JDK 21+ from https://adoptium.net/temurin/releases/?version=21'
      ;;
  esac
}

hint_curl() {
  case "$OS_KIND" in
    macos) printf 'curl ships with macOS; if missing: brew install curl' ;;
    linux)
      if has_apt; then
        printf 'sudo apt-get install -y curl'
      elif has_dnf; then
        printf 'sudo dnf install -y curl'
      elif has_pacman; then
        printf 'sudo pacman -S --needed curl'
      else
        printf 'install curl'
      fi
      ;;
    *) printf 'install curl' ;;
  esac
}

hint_unzip() {
  case "$OS_KIND" in
    macos) printf 'unzip ships with macOS; if missing: brew install unzip' ;;
    linux)
      if has_apt; then
        printf 'sudo apt-get install -y unzip'
      elif has_dnf; then
        printf 'sudo dnf install -y unzip'
      elif has_pacman; then
        printf 'sudo pacman -S --needed unzip'
      else
        printf 'install unzip'
      fi
      ;;
    *) printf 'install unzip' ;;
  esac
}

hint_adb() {
  case "$OS_KIND" in
    macos)
      printf 'brew install android-platform-tools   # then: export REA_ADB_PATH="$(command -v adb)"'
      ;;
    linux)
      if has_apt; then
        printf 'sudo apt-get install -y android-tools-adb   # then: export REA_ADB_PATH="$(command -v adb)"'
      elif has_dnf; then
        printf 'sudo dnf install -y android-tools   # then: export REA_ADB_PATH="$(command -v adb)"'
      elif has_pacman; then
        printf 'sudo pacman -S --needed android-tools   # then: export REA_ADB_PATH="$(command -v adb)"'
      else
        printf 'install Android platform-tools, then export REA_ADB_PATH=/path/to/adb'
      fi
      ;;
    *)
      printf 'install Android platform-tools, then export REA_ADB_PATH=/path/to/adb'
      ;;
  esac
}

hint_apktool() {
  case "$OS_KIND" in
    macos)
      printf 'brew install apktool   # jar at /opt/homebrew/bin/apktool.jar (Apple Silicon) or /usr/local/bin/apktool.jar'
      ;;
    linux)
      if has_apt; then
        printf 'sudo apt-get install -y apktool   # jar at /usr/share/apktool/apktool.jar'
      elif has_dnf; then
        printf 'sudo dnf install -y apktool   # or download the jar from https://github.com/iBotPeaches/Apktool/releases'
      elif has_pacman; then
        printf 'sudo pacman -S --needed apktool'
      else
        printf 'download apktool.jar from https://github.com/iBotPeaches/Apktool/releases and re-run with --apktool-jar PATH'
      fi
      ;;
    *)
      printf 'download apktool.jar from https://github.com/iBotPeaches/Apktool/releases and re-run with --apktool-jar PATH'
      ;;
  esac
}

hint_browser() {
  case "$OS_KIND" in
    macos)
      printf 'brew install --cask google-chrome   # then: export REA_BROWSER_EXECUTABLE="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"'
      ;;
    linux)
      if has_apt; then
        printf 'sudo apt-get install -y chromium   # or google-chrome from https://www.google.com/chrome/'
      elif has_dnf; then
        printf 'sudo dnf install -y chromium   # or google-chrome-stable'
      elif has_pacman; then
        printf 'sudo pacman -S --needed chromium'
      else
        printf 'install Chrome or Chromium, then export REA_BROWSER_EXECUTABLE=/path/to/chrome'
      fi
      ;;
    *)
      printf 'install Chrome or Chromium, then export REA_BROWSER_EXECUTABLE=/path/to/chrome'
      ;;
  esac
}

# ---------------------------------------------------------------- flags ----
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --skip-ghidra) SKIP_GHIDRA=1 ;;
    --skip-jadx) SKIP_JADX=1 ;;
    --skip-adb) SKIP_ADB=1 ;;
    --skip-apktool) SKIP_APKTOOL=1 ;;
    --skip-agents) SKIP_AGENTS=1 ;;
    --tools-root)
      if [ $# -lt 2 ]; then die "--tools-root needs a directory"; fi
      TOOLS_ROOT="$2"
      shift
      ;;
    --tools-root=*)
      TOOLS_ROOT="${1#*=}"
      ;;
    --apktool-jar)
      if [ $# -lt 2 ]; then die "--apktool-jar needs a path"; fi
      APKTOOL_JAR_OPT="$2"
      shift
      ;;
    --apktool-jar=*)
      APKTOOL_JAR_OPT="${1#*=}"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
  shift
done

if [ -z "$TOOLS_ROOT" ]; then
  die "--tools-root must not be empty"
fi

detect_platform

if [ "$OS_KIND" = "other" ]; then
  if [ "$DRY_RUN" -eq 0 ]; then
    printf 'error: unsupported OS "%s" (arch %s)\n' "$OS_RAW" "$ARCH" >&2
    printf '       this script targets macOS (Darwin) and Linux.\n' >&2
    printf '       Windows: powershell -NoProfile -ExecutionPolicy Bypass -File .\\scripts\\setup-rea-tools.ps1\n' >&2
    printf '       Linux on WSL 2: bash scripts/linux-tools-setup.sh inside the distro.\n' >&2
    exit 1
  fi
  printf 'note: OS "%s" is not macOS/Linux; --dry-run only, nothing will be changed.\n' "$OS_RAW"
fi

printf 'dsh-rea POSIX setup\n'
printf '  OS:         %s (%s)\n' "$OS_KIND" "$ARCH"
printf '  tools root: %s\n' "$TOOLS_ROOT"
printf '  REA:        %s\n' "$REA_PKG"
if [ "$DRY_RUN" -eq 1 ]; then
  printf '  mode:       DRY RUN (no download, no write, no install)\n'
fi

# ------------------------------------------------------- 1. Node.js -------
step "1/9 Node.js (REA engines: ^22.19.0 || ^24.11.0 || >=26.0.0)"
NODE_PATH_RAW=""
if NODE_PATH_RAW=$(command -v node 2>/dev/null); then :; else NODE_PATH_RAW=""; fi
NODE_RAW=""
NODE_VER=""
if [ -n "$NODE_PATH_RAW" ]; then
  NODE_BIN="$NODE_PATH_RAW"
  if NODE_RAW=$("$NODE_BIN" --version 2>/dev/null); then :; else NODE_RAW=""; fi
  NODE_VER="${NODE_RAW#v}"
fi
if [ -n "$NODE_VER" ] && node_engines_ok "$NODE_VER"; then
  log_ok "node $NODE_RAW at $NODE_BIN satisfies REA's engines"
  NODE_OK=1
else
  if [ -z "$NODE_BIN" ]; then
    log_warn "node not found on PATH"
  else
    log_warn "node $NODE_RAW at $NODE_BIN does not satisfy ^22.19.0 || ^24.11.0 || >=26.0.0"
  fi
  log_hint "install Node.js: $(hint_node)"
fi

NPM_PATH_RAW=""
if NPM_PATH_RAW=$(command -v npm 2>/dev/null); then :; else NPM_PATH_RAW=""; fi
NPM_VER=""
if [ -n "$NPM_PATH_RAW" ]; then
  NPM_BIN="$NPM_PATH_RAW"
  if NPM_VER=$("$NPM_BIN" --version 2>/dev/null); then :; else NPM_VER=""; fi
  log_ok "npm ${NPM_VER:-?} at $NPM_BIN"
else
  log_warn "npm not found on PATH (the pinned REA install in step 8 needs it)"
  log_hint "npm usually ships with Node.js; Debian/Ubuntu may need: sudo apt-get install -y npm"
fi

AGENTS_READY=1
if [ "$NODE_OK" -eq 0 ] || [ -z "$NPM_BIN" ]; then
  AGENTS_READY=0
fi
if [ "$DRY_RUN" -eq 0 ] && [ "$SKIP_AGENTS" -eq 0 ] && [ "$AGENTS_READY" -eq 0 ]; then
  log_fail "step 8 (pinned REA MCP install) needs a supported node + npm; stopping before any download so nothing is half-installed"
  log_hint "install Node.js first, then re-run: bash $0"
  log_hint "or provision only the optional analysis tools now: bash $0 --skip-agents"
  exit 1
fi

# ---------------------------------------------------------- 2. JDK 21+ ----
step "2/9 JDK 21+ (required by Ghidra and JADX)"
JAVA_HOW=""
if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
  JAVA_BIN="${JAVA_HOME}/bin/java"
  JAVA_HOW="JAVA_HOME"
else
  JAVA_PATH_RAW=""
  if JAVA_PATH_RAW=$(command -v java 2>/dev/null); then :; else JAVA_PATH_RAW=""; fi
  if [ -n "$JAVA_PATH_RAW" ]; then
    JAVA_BIN="$JAVA_PATH_RAW"
    JAVA_HOW="PATH"
  fi
fi

JAVA_RAW=""
JAVA_MAJOR=""
if [ -n "$JAVA_BIN" ]; then
  if JAVA_RAW=$("$JAVA_BIN" -version 2>&1 | sed -n '1p'); then :; else JAVA_RAW=""; fi
  JAVA_MAJOR=$(printf '%s\n' "$JAVA_RAW" | sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p')
fi

JAVA_HOME_GUESS=""
if [ -n "$JAVA_MAJOR" ] && [ "$JAVA_MAJOR" -ge 21 ]; then
  log_ok "JDK $JAVA_MAJOR via $JAVA_HOW: $JAVA_BIN"
  if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
    JAVA_HOME_GUESS="${JAVA_HOME}"
  else
    JAVA_DIR=$(dirname "$JAVA_BIN")
    JAVA_PARENT=$(cd "$JAVA_DIR/.." 2>/dev/null && pwd || true)
    if [ -n "$JAVA_PARENT" ] && [ -x "$JAVA_PARENT/bin/java" ]; then
      JAVA_HOME_GUESS="$JAVA_PARENT"
    fi
  fi
  if [ -n "$JAVA_HOME_GUESS" ] && [ ! -x "$JAVA_HOME_GUESS/bin/javac" ]; then
    log_warn "no bin/javac under $JAVA_HOME_GUESS - looks like a JRE; Ghidra and JADX need a full JDK"
  fi
  if [ -n "$JAVA_HOME_GUESS" ]; then
    ENV_JAVA="export JAVA_HOME=$(dq "$JAVA_HOME_GUESS")"
    log_info "expected export: $ENV_JAVA"
  else
    log_hint "JAVA_HOME could not be derived from $JAVA_BIN; set it to your JDK 21+ home"
  fi
else
  if [ -z "$JAVA_BIN" ]; then
    log_warn "no java found (JAVA_HOME unset or invalid, java not on PATH)"
  else
    log_warn "java at $JAVA_BIN reports \"$JAVA_RAW\" which is older than 21"
  fi
  log_hint "$(hint_jdk)"
  if [ "$OS_KIND" = "macos" ] && [ "$ARCH" = "arm64" ]; then
    log_hint "Apple Silicon: install an aarch64 JDK (Temurin 21 has a mac aarch64 build); an x86_64 JDK needs Rosetta"
  fi
fi

# -------------------------------------------------------- 3. Ghidra -------
step "3/9 Ghidra $GHIDRA_VERSION (native decompilation provider)"
GHIDRA_HOME=""

if [ -n "${GHIDRA_INSTALL_DIR:-}" ]; then
  if [ -x "${GHIDRA_INSTALL_DIR}/support/analyzeHeadless" ]; then
    GHIDRA_HOME="${GHIDRA_INSTALL_DIR}"
    log_skip "GHIDRA_INSTALL_DIR already points at a usable install: $GHIDRA_HOME"
  else
    log_warn "GHIDRA_INSTALL_DIR is set to ${GHIDRA_INSTALL_DIR} but support/analyzeHeadless is missing or not executable"
  fi
fi

if [ -z "$GHIDRA_HOME" ] && [ "$SKIP_GHIDRA" -eq 0 ]; then
  GHIDRA_SCAN=""
  for GHIDRA_CAND in "$TOOLS_ROOT"/ghidra_*; do
    if [ -d "$GHIDRA_CAND" ] && [ -x "$GHIDRA_CAND/support/analyzeHeadless" ]; then
      GHIDRA_SCAN="$GHIDRA_CAND"
    fi
  done
  if [ -n "$GHIDRA_SCAN" ]; then
    GHIDRA_HOME="$GHIDRA_SCAN"
    log_ok "found an existing install under --tools-root: $GHIDRA_HOME"
  fi
fi

if [ "$SKIP_GHIDRA" -eq 1 ]; then
  if [ -n "$GHIDRA_HOME" ]; then
    log_skip "Ghidra download skipped by --skip-ghidra; the existing install above is used"
  else
    log_skip "Ghidra skipped by --skip-ghidra"
    log_hint "REA will report the ghidra provider as unavailable; IDA still works via REA_IDA_MCP_CONFIG"
  fi
elif [ -n "$GHIDRA_HOME" ]; then
  : # already reported above
elif [ "$DRY_RUN" -eq 1 ]; then
  log_hint "would download $GHIDRA_URL (~570 MB), verify SHA-256 ${GHIDRA_SHA256:0:16}..., unzip into $TOOLS_ROOT, then export GHIDRA_INSTALL_DIR"
elif ! command -v curl >/dev/null 2>&1; then
  log_warn "curl not found; cannot download Ghidra"
  log_hint "$(hint_curl)"
  log_hint "manual: download $GHIDRA_URL, unzip into $TOOLS_ROOT, export GHIDRA_INSTALL_DIR=\"$TOOLS_ROOT/ghidra_${GHIDRA_VERSION}_PUBLIC\""
else
  mkdir -p "$TOOLS_ROOT"
  GHIDRA_ZIP="$TOOLS_ROOT/$GHIDRA_ASSET"
  GHIDRA_ZIP_OK=0
  if [ -f "$GHIDRA_ZIP" ]; then
    GHIDRA_ZIP_SHA=""
    if GHIDRA_ZIP_SHA=$(sha256_of "$GHIDRA_ZIP"); then
      if [ "$(lower "$GHIDRA_ZIP_SHA")" = "$(lower "$GHIDRA_SHA256")" ]; then
        GHIDRA_ZIP_OK=1
        log_skip "reusing verified download: $GHIDRA_ZIP"
      else
        log_warn "existing $GHIDRA_ZIP has the wrong SHA-256; removing it and downloading again"
        rm -f "$GHIDRA_ZIP"
      fi
    else
      GHIDRA_ZIP_OK=1
      log_warn "no SHA-256 tool (sha256sum/shasum/openssl); reusing $GHIDRA_ZIP without verification"
    fi
  fi

  if [ "$GHIDRA_ZIP_OK" -eq 0 ]; then
    log_info "downloading $GHIDRA_URL"
    log_info "this is a ~570 MB download and can take several minutes"
    if curl -fL --retry 3 -o "$GHIDRA_ZIP" "$GHIDRA_URL"; then
      GHIDRA_ZIP_OK=1
    else
      log_warn "download failed"
      rm -f "$GHIDRA_ZIP"
      log_hint "check network/proxy, then retry: curl -fL --retry 3 -o $(dq "$GHIDRA_ZIP") $(dq "$GHIDRA_URL")"
      log_hint "or download it manually from $GHIDRA_URL and unzip into $TOOLS_ROOT"
    fi
  fi

  if [ "$GHIDRA_ZIP_OK" -eq 1 ]; then
    if ! command -v unzip >/dev/null 2>&1; then
      log_warn "unzip not found; cannot extract $GHIDRA_ZIP"
      log_hint "$(hint_unzip)"
      log_hint "then: unzip -q $(dq "$GHIDRA_ZIP") -d $(dq "$TOOLS_ROOT")"
    else
      GHIDRA_SHA_ACTUAL=""
      GHIDRA_SHA_VERIFIED=0
      if GHIDRA_SHA_ACTUAL=$(sha256_of "$GHIDRA_ZIP"); then
        if [ "$(lower "$GHIDRA_SHA_ACTUAL")" = "$(lower "$GHIDRA_SHA256")" ]; then
          GHIDRA_SHA_VERIFIED=1
          log_ok "SHA-256 verified for $GHIDRA_ASSET"
        else
          log_warn "SHA-256 MISMATCH for $GHIDRA_ZIP"
          log_info "  expected $GHIDRA_SHA256"
          log_info "  actual   $GHIDRA_SHA_ACTUAL"
          log_info "refusing to unzip a corrupt/tampered archive; file removed"
          rm -f "$GHIDRA_ZIP"
          log_hint "download it again from $GHIDRA_URL and verify manually before unzipping"
        fi
      else
        log_warn "no SHA-256 tool available; unzipping without verification (expected $GHIDRA_SHA256)"
        GHIDRA_SHA_VERIFIED=1
      fi

      if [ "$GHIDRA_SHA_VERIFIED" -eq 1 ]; then
        log_info "extracting (this takes a few minutes)"
        if unzip -q -o "$GHIDRA_ZIP" -d "$TOOLS_ROOT"; then
          GHIDRA_SCAN=""
          for GHIDRA_CAND in "$TOOLS_ROOT"/ghidra_*; do
            if [ -d "$GHIDRA_CAND" ] && [ -x "$GHIDRA_CAND/support/analyzeHeadless" ]; then
              GHIDRA_SCAN="$GHIDRA_CAND"
            fi
          done
          if [ -n "$GHIDRA_SCAN" ]; then
            GHIDRA_HOME="$GHIDRA_SCAN"
            log_ok "Ghidra extracted: $GHIDRA_HOME"
            log_info "zip kept at $GHIDRA_ZIP (delete it to reclaim ~570 MB; re-runs reuse it)"
          else
            log_warn "archive extracted but no ghidra_*/support/analyzeHeadless was found under $TOOLS_ROOT"
            log_hint "inspect $(dq "$TOOLS_ROOT") and export GHIDRA_INSTALL_DIR to the folder that contains support/analyzeHeadless"
          fi
        else
          log_warn "unzip failed"
          log_hint "extract manually: unzip -q $(dq "$GHIDRA_ZIP") -d $(dq "$TOOLS_ROOT")"
        fi
      fi
    fi
  fi

  if [ -z "$GHIDRA_HOME" ]; then
    log_warn "Ghidra was not provisioned; the MCP server still starts, only the Ghidra native lane stays off"
    log_hint "manual: download $GHIDRA_URL, unzip into $TOOLS_ROOT, export GHIDRA_INSTALL_DIR=\"$TOOLS_ROOT/ghidra_${GHIDRA_VERSION}_PUBLIC\""
  fi
fi

if [ -n "$GHIDRA_HOME" ]; then
  ENV_GHIDRA="export GHIDRA_INSTALL_DIR=$(dq "$GHIDRA_HOME")"
fi

# ---------------------------------------------------------- 4. JADX -------
step "4/9 JADX $JADX_VERSION headless MCP jar (APK code decompilation)"
JADX_JAR="${REA_JADX_MCP_JAR:-$HOME/.rea/android/$JADX_ASSET}"
JADX_HAVE=0

if [ -f "$JADX_JAR" ]; then
  JADX_HAVE=1
  log_skip "jar already present: $JADX_JAR"
elif [ "$SKIP_JADX" -eq 1 ]; then
  log_skip "JADX skipped by --skip-jadx"
  log_hint "download $JADX_URL to $JADX_JAR then: export REA_JADX_MCP_JAR=$(dq "$JADX_JAR")"
elif [ "$DRY_RUN" -eq 1 ]; then
  log_hint "would download $JADX_URL (~42 MB) to $JADX_JAR, verify SHA-256 ${JADX_SHA256:0:16}..., then export REA_JADX_MCP_JAR"
elif ! command -v curl >/dev/null 2>&1; then
  log_warn "curl not found; cannot download the JADX jar"
  log_hint "$(hint_curl)"
  log_hint "manual: download $JADX_URL to $JADX_JAR then: export REA_JADX_MCP_JAR=$(dq "$JADX_JAR")"
else
  JADX_DIR=$(dirname "$JADX_JAR")
  mkdir -p "$JADX_DIR"
  log_info "downloading $JADX_URL"
  if curl -fL --retry 3 -o "$JADX_JAR" "$JADX_URL"; then
    JADX_SHA_ACTUAL=""
    if JADX_SHA_ACTUAL=$(sha256_of "$JADX_JAR"); then
      if [ "$(lower "$JADX_SHA_ACTUAL")" = "$(lower "$JADX_SHA256")" ]; then
        JADX_HAVE=1
        log_ok "SHA-256 verified; jar at $JADX_JAR"
      else
        log_warn "SHA-256 MISMATCH for $JADX_JAR (expected $JADX_SHA256, actual $JADX_SHA_ACTUAL); file removed"
        rm -f "$JADX_JAR"
      fi
    else
      JADX_HAVE=1
      log_warn "no SHA-256 tool available; jar kept without verification (expected $JADX_SHA256)"
    fi
  else
    log_warn "download failed"
    rm -f "$JADX_JAR"
    log_hint "download it manually: $JADX_URL -> $JADX_JAR"
  fi
fi

if [ "$JADX_HAVE" -eq 1 ] && [ -f "$JADX_JAR" ]; then
  ENV_JADX="export REA_JADX_MCP_JAR=$(dq "$JADX_JAR")"
  if [ "$DRY_RUN" -eq 0 ]; then
    log_info "APK code decompilation needs a JDK 21+ as well (step 2)"
  fi
else
  if [ "$SKIP_JADX" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    log_hint "JADX is best effort here; inspect_android_package / decode_android_resources still work without it"
  fi
fi

# ----------------------------------------------------------- 5. adb -------
step "5/9 adb (Android devices)"
ADB_HAVE=0
if [ -n "${REA_ADB_PATH:-}" ]; then
  if [ -x "${REA_ADB_PATH}" ]; then
    ADB_HAVE=1
    ENV_ADB="export REA_ADB_PATH=$(dq "${REA_ADB_PATH}")"
    log_skip "REA_ADB_PATH already points at an executable: ${REA_ADB_PATH}"
  else
    log_warn "REA_ADB_PATH is set to ${REA_ADB_PATH} but that file is missing or not executable"
  fi
fi

if [ "$ADB_HAVE" -eq 0 ] && [ "$SKIP_ADB" -eq 1 ]; then
  log_skip "adb skipped by --skip-adb"
elif [ "$ADB_HAVE" -eq 0 ]; then
  ADB_PATH_RAW=""
  if ADB_PATH_RAW=$(command -v adb 2>/dev/null); then :; else ADB_PATH_RAW=""; fi
  if [ -n "$ADB_PATH_RAW" ]; then
    ADB_HAVE=1
    log_ok "adb on PATH: $ADB_PATH_RAW"
    ENV_ADB="export REA_ADB_PATH=$(dq "$ADB_PATH_RAW")"
    log_info "optional but explicit: $ENV_ADB"
  else
    log_hint "$(hint_adb)"
    log_hint "without adb the device lane stays off: inspect_adb_client / list_adb_devices report adb_unavailable"
  fi
fi

# ------------------------------------------------------- 6. apktool -------
step "6/9 apktool (APK resources; needs a real executable, not a .bat)"
APKTOOL_HAVE=0
APKTOOL_PLANNED=""
APKTOOL_FROM_ENV=0

if [ -n "${REA_APKTOOL_COMMAND:-}" ]; then
  if [ -f "${REA_APKTOOL_COMMAND}" ] && [ -x "${REA_APKTOOL_COMMAND}" ]; then
    APKTOOL_HAVE=1
    APKTOOL_FROM_ENV=1
    log_skip "REA_APKTOOL_COMMAND already points at an executable: ${REA_APKTOOL_COMMAND}"
  else
    log_warn "REA_APKTOOL_COMMAND is set to ${REA_APKTOOL_COMMAND} but that is not an executable file (REA runs it shell-free)"
  fi
fi

if [ "$APKTOOL_HAVE" -eq 0 ] && [ "$SKIP_APKTOOL" -eq 1 ]; then
  log_skip "apktool skipped by --skip-apktool"
elif [ "$APKTOOL_HAVE" -eq 0 ]; then
  APKTOOL_JAR=""
  if [ -n "$APKTOOL_JAR_OPT" ]; then
    if [ -f "$APKTOOL_JAR_OPT" ]; then
      APKTOOL_JAR="$APKTOOL_JAR_OPT"
    else
      log_warn "--apktool-jar $APKTOOL_JAR_OPT does not exist"
    fi
  fi
  if [ -z "$APKTOOL_JAR" ]; then
    for APKTOOL_CAND in \
      "$TOOLS_ROOT"/apktool/*.jar \
      /opt/homebrew/bin/apktool.jar \
      /usr/local/bin/apktool.jar \
      /opt/homebrew/Cellar/apktool/*/libexec/apktool.jar \
      /usr/local/Cellar/apktool/*/libexec/apktool.jar \
      /usr/share/apktool/apktool.jar \
      /usr/local/share/apktool/apktool.jar; do
      if [ -f "$APKTOOL_CAND" ]; then
        APKTOOL_JAR="$APKTOOL_CAND"
        break
      fi
    done
  fi

  if [ -z "$APKTOOL_JAR" ]; then
    log_hint "$(hint_apktool)"
    log_hint "if you already have apktool.jar, re-run with: bash $0 --apktool-jar /path/to/apktool.jar"
    log_info "without it inspect_apktool_client and decode_android_resources stay unavailable"
  else
    log_ok "apktool jar: $APKTOOL_JAR"
    APKTOOL_WRAPPER="$TOOLS_ROOT/apktool/apktool"
    JAVA_FOR_WRAPPER=""
    if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
      JAVA_FOR_WRAPPER="${JAVA_HOME}/bin/java"
    elif [ -n "$JAVA_BIN" ]; then
      JAVA_FOR_WRAPPER="$JAVA_BIN"
    fi
    if [ -z "$JAVA_FOR_WRAPPER" ]; then
      JAVA_FOR_WRAPPER="java"
      log_warn "no JDK found; the wrapper will resolve \"java\" from PATH at runtime (pin it by setting JAVA_HOME)"
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
      APKTOOL_PLANNED="$APKTOOL_WRAPPER"
      log_hint "would write $APKTOOL_WRAPPER (#!/bin/sh, exec $(dq "$JAVA_FOR_WRAPPER") -jar $(dq "$APKTOOL_JAR") \"\$@\") and chmod +x"
    else
      APKTOOL_DIR=$(dirname "$APKTOOL_WRAPPER")
      mkdir -p "$APKTOOL_DIR"
      {
        printf '#!/bin/sh\n'
        printf '# Generated by dsh-rea scripts/setup-rea-tools.sh\n'
        printf '# REA executes this file shell-free, so it must be a real executable.\n'
        printf 'exec %s -jar %s "$@"\n' "$(dq "$JAVA_FOR_WRAPPER")" "$(dq "$APKTOOL_JAR")"
      } >"$APKTOOL_WRAPPER"
      chmod 755 "$APKTOOL_WRAPPER"
      if [ -f "$APKTOOL_WRAPPER" ] && [ -x "$APKTOOL_WRAPPER" ]; then
        APKTOOL_HAVE=1
        log_ok "wrote executable wrapper: $APKTOOL_WRAPPER"
        log_info "verify it manually: $(dq "$APKTOOL_WRAPPER") --version"
      else
        log_warn "wrapper written but not executable: $APKTOOL_WRAPPER"
      fi
    fi
  fi
fi

if [ "$APKTOOL_FROM_ENV" -eq 1 ]; then
  ENV_APKTOOL="export REA_APKTOOL_COMMAND=$(dq "${REA_APKTOOL_COMMAND}")"
elif [ "$APKTOOL_HAVE" -eq 1 ]; then
  ENV_APKTOOL="export REA_APKTOOL_COMMAND=$(dq "$TOOLS_ROOT/apktool/apktool")"
elif [ "$DRY_RUN" -eq 1 ] && [ -n "$APKTOOL_PLANNED" ]; then
  ENV_APKTOOL="export REA_APKTOOL_COMMAND=$(dq "$APKTOOL_PLANNED")"
  log_hint "would then export REA_APKTOOL_COMMAND=$(dq "$APKTOOL_PLANNED")"
fi

# ------------------------------------------------------- 7. browser -------
step "7/9 Browser for the browser/CDP lane"
BROWSER_HAVE=0
BROWSER_BIN=""
BROWSER_ALREADY=0

if [ -n "${REA_BROWSER_EXECUTABLE:-}" ]; then
  if [ -x "${REA_BROWSER_EXECUTABLE}" ]; then
    BROWSER_HAVE=1
    BROWSER_ALREADY=1
    BROWSER_BIN="${REA_BROWSER_EXECUTABLE}"
    log_skip "REA_BROWSER_EXECUTABLE already points at an executable: $BROWSER_BIN"
  else
    log_warn "REA_BROWSER_EXECUTABLE is set to ${REA_BROWSER_EXECUTABLE} but that file is missing or not executable"
  fi
fi

if [ "$BROWSER_HAVE" -eq 0 ] && [ "$OS_KIND" = "macos" ]; then
  for BROWSER_CAND in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "$HOME/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium"; do
    if [ -x "$BROWSER_CAND" ]; then
      BROWSER_BIN="$BROWSER_CAND"
      BROWSER_HAVE=1
      break
    fi
  done
fi

if [ "$BROWSER_HAVE" -eq 0 ] && [ "$OS_KIND" = "linux" ]; then
  for BROWSER_NAME in google-chrome google-chrome-stable chromium chromium-browser; do
    BROWSER_CAND=""
    if BROWSER_CAND=$(command -v "$BROWSER_NAME" 2>/dev/null); then :; else BROWSER_CAND=""; fi
    if [ -n "$BROWSER_CAND" ]; then
      BROWSER_BIN="$BROWSER_CAND"
      BROWSER_HAVE=1
      break
    fi
  done
fi

if [ "$BROWSER_HAVE" -eq 1 ]; then
  if [ "$BROWSER_ALREADY" -eq 0 ]; then
    log_ok "browser: $BROWSER_BIN"
  fi
  ENV_BROWSER="export REA_BROWSER_EXECUTABLE=$(dq "$BROWSER_BIN")"
else
  log_hint "$(hint_browser)"
  log_info "without a browser the browser lane stays off: list_browser_targets reports a missing executable"
fi

# -------------------------------------------------------- 8. agents -------
step "8/9 Pinned REA MCP install (launcher layer 2)"
REA_PREFIX="$HOME/.rea/dsh/agents/$REA_VERSION"
REA_ENTRY="$REA_PREFIX/node_modules/rea-agents/scripts/rea.mjs"
REA_PKG_JSON="$REA_PREFIX/node_modules/rea-agents/package.json"
REA_INSTALLED_VER=""

if [ "$SKIP_AGENTS" -eq 1 ]; then
  log_skip "pinned install skipped by --skip-agents"
  log_hint "the launcher then falls back to layer 3: npx -y $REA_PKG mcp (needs network and a usable node on PATH)"
else
  if [ -f "$REA_ENTRY" ] && [ -f "$REA_PKG_JSON" ]; then
    if REA_INSTALLED_VER=$(node -e 'process.stdout.write(String(require(process.argv[1]).version||""))' "$REA_PKG_JSON" 2>/dev/null); then :; else REA_INSTALLED_VER=""; fi
  fi

  NEED_INSTALL=1
  if [ -f "$REA_ENTRY" ] && [ "$REA_INSTALLED_VER" = "$REA_VERSION" ]; then
    NEED_INSTALL=0
    log_skip "already installed: $REA_PKG at $REA_PREFIX"
  fi

  if [ "$NEED_INSTALL" -eq 1 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      log_hint "would run: npm install --prefix $(dq "$REA_PREFIX") $REA_PKG --no-audit --no-fund --loglevel=error"
    else
      log_info "running: npm install --prefix $(dq "$REA_PREFIX") $REA_PKG --no-audit --no-fund --loglevel=error"
      if npm install --prefix "$REA_PREFIX" "$REA_PKG" --no-audit --no-fund --loglevel=error; then
        :
      else
        log_fail "npm install failed"
        HARD_FAIL=1
      fi
    fi
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log_info "would then assert: $REA_ENTRY"
    log_info "layer 2 needs no environment variable; the launcher resolves this exact path"
  else
    if [ -f "$REA_ENTRY" ]; then
      REA_INSTALLED_VER=""
      if REA_INSTALLED_VER=$(node -e 'process.stdout.write(String(require(process.argv[1]).version||""))' "$REA_PKG_JSON" 2>/dev/null); then :; else REA_INSTALLED_VER=""; fi
      log_ok "entry verified: $REA_ENTRY"
      if [ -n "$REA_INSTALLED_VER" ]; then
        log_info "installed version: $REA_INSTALLED_VER"
      else
        log_info "installed version: unknown (package.json $REA_PKG_JSON unreadable)"
      fi
      if [ -n "$REA_INSTALLED_VER" ] && [ "$REA_INSTALLED_VER" != "$REA_VERSION" ]; then
        log_warn "installed version $REA_INSTALLED_VER differs from the pinned $REA_VERSION; the launcher spawns this path unconditionally"
        log_hint "reinstall with: npm install --prefix $(dq "$REA_PREFIX") $REA_PKG --no-audit --no-fund --loglevel=error"
      fi
      log_info "layer 2 needs no environment variable; REA_MCP_ENTRY is only an override"
      log_info "the launcher spawns it with the Node bundled with DSH (no npx, no network)"
    else
      log_fail "expected entry file is missing: $REA_ENTRY"
      log_hint "run: npm install --prefix $(dq "$REA_PREFIX") $REA_PKG --no-audit --no-fund --loglevel=error"
      HARD_FAIL=1
    fi
  fi
fi

# ------------------------------------------------------- 9. summary -------
step "9/9 Summary"
printf '\nEnvironment variables (copy-paste form):\n'
ANY_ENV=0
if [ -n "$ENV_JAVA" ]; then
  printf '  %s\n' "$ENV_JAVA"
  ANY_ENV=1
fi
if [ -n "$ENV_GHIDRA" ]; then
  printf '  %s\n' "$ENV_GHIDRA"
  ANY_ENV=1
fi
if [ -n "$ENV_JADX" ]; then
  printf '  %s\n' "$ENV_JADX"
  ANY_ENV=1
fi
if [ -n "$ENV_ADB" ]; then
  printf '  %s\n' "$ENV_ADB"
  ANY_ENV=1
fi
if [ -n "$ENV_APKTOOL" ]; then
  printf '  %s\n' "$ENV_APKTOOL"
  ANY_ENV=1
fi
if [ -n "$ENV_BROWSER" ]; then
  printf '  %s\n' "$ENV_BROWSER"
  ANY_ENV=1
fi
if [ "$ANY_ENV" -eq 0 ]; then
  printf '  (none)\n'
fi

printf '\nNotes:\n'
printf '  - The pinned local REA install (step 8) needs NO REA_* variable at all:\n'
printf '    the launcher resolves\n'
printf '      %s\n' "$REA_ENTRY"
printf '    and spawns it with the Node bundled with DSH.\n'
printf '  - JAVA_HOME / GHIDRA_INSTALL_DIR / REA_* above only enable the optional\n'
printf '    analysis lanes (Ghidra, JADX, adb, apktool, browser).\n'
printf '  - These variables must be present in the environment of the process that\n'
printf '    LAUNCHES DSH. A desktop app started from Finder / Dock does not read your\n'
printf '    shell profile (~/.zshrc, ~/.bash_profile). Reliable options:\n'
printf '      1) start DSH from a wrapper script that exports them first (recommended);\n'
printf '      2) macOS: launchctl setenv NAME value  (then restart DSH);\n'
printf '      3) Linux: export them in ~/.profile and log out/in, or start DSH from a terminal.\n'
printf '    See docs/SETUP-POSIX.md for wrapper examples.\n'

printf '\nVerify the MCP server without DSH:\n'
VERIFY_JSON='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"probe","version":"0.0.0"}}}'
printf "  printf '%%s\\\\n' '%s' | node \"\$HOME/.rea/dsh/agents/%s/node_modules/rea-agents/scripts/rea.mjs\" mcp\n" "$VERIFY_JSON" "$REA_VERSION"
printf '  The first JSON line of the response proves the server is reachable.\n'

printf '\nOptional deeper checks:\n'
printf '  npx -y %s doctor --json        # provider/environment report\n' "$REA_PKG"
printf '  npx -y %s capabilities --json  # per-operation availability\n' "$REA_PKG"
if [ -n "$GHIDRA_HOME" ]; then
  printf '  Ghidra self-test: "%s/support/analyzeHeadless" "$HOME/.rea/tmp" probe -import /bin/ls -noanalysis\n' "$GHIDRA_HOME"
fi

printf '\nResult: %d ok, %d already present/skipped, %d manual hint(s), %d warning(s)' "$OK_COUNT" "$SKIP_COUNT" "$HINT_COUNT" "$WARN_COUNT"
if [ "$DRY_RUN" -eq 1 ]; then
  printf '\nDry run only: nothing was downloaded, written, or installed.\n'
  exit 0
fi
if [ "$HARD_FAIL" -ne 0 ] || [ "$FAIL_COUNT" -ne 0 ]; then
  printf '\n\nOne or more required steps failed - see the [fail] lines above.\n'
  exit 1
fi
printf '\n\nDone. [warn] steps are optional: the REA MCP server starts without them,\n'
printf 'the matching analysis lane stays unavailable until you finish those manually.\n'
exit 0
