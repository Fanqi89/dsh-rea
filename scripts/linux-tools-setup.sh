#!/usr/bin/env bash
# Linux-side toolchain for REA's Linux-only capabilities, run inside WSL.
#
# Covers: native ELF layout (pwntools), firmware (binwalk/unblob), packet
# captures (mitmproxy/mitmdump), recorded crash inspection (gdb), and the .deb
# / dpkg tooling used for Debian packages.
#
# Usage:  bash linux-tools-setup.sh            (as root inside WSL)
set -euo pipefail

echo "== apt base packages =="
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg git xz-utils zstd arj cabextract p7zip-full \
  binutils file gdb python3 python3-pip python3-venv pipx \
  dpkg-dev fakeroot build-essential libssl-dev \
  unzip tar cpio lz4 lzop squashfs-tools

echo "== Node.js 22 (REA requires >= 22.19) =="
if ! command -v node >/dev/null || [ "$(node -p 'process.versions.node.split(".")[0]')" -lt 22 ]; then
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key |
    gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list
  apt-get update
  apt-get install -y nodejs
fi

echo "== Python analysis tools (pipx keeps them isolated) =="
pipx ensurepath
for pkg in pwntools binwalk unblob mitmproxy; do
  echo "-- $pkg"
  pipx install --force "$pkg" || echo "WARN: $pkg install failed"
done

echo "== REA (rea-agents) for the Linux MCP instance =="
npm install -g "rea-agents@6.4.0" || echo "WARN: rea-agents global install failed"

echo "== versions =="
{
  echo "python: $(python3 --version)"
  echo "node:   $(node --version || echo missing)"
  echo "rea:    $(command -v rea >/dev/null && rea --version || echo missing)"
  for tool in pwn binwalk unblob mitmdump gdb ar file; do
    if command -v "$tool" >/dev/null; then echo "$tool: $(command -v $tool)"; else echo "$tool: MISSING"; fi
  done
} | tee /root/rea-linux-tools.txt

echo
echo "Done. Tool versions are recorded in /root/rea-linux-tools.txt"
