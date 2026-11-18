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

echo "== Node.js 24.22.3 (REA 6.9.0 requires ^22.23.4 || ^24.22.1 || >=26.12.1) =="
node_ok() {
  command -v node >/dev/null || return 1
  node -e '
    const v = process.versions.node.split(".").map(Number);
    const ok = (v[0] === 22 && (v[1] > 23 || (v[1] === 23 && v[2] >= 4)))
      || (v[0] === 24 && (v[1] > 22 || (v[1] === 22 && v[2] >= 1)))
      || (v[0] >= 26 && (v[1] > 12 || (v[1] === 12 && v[2] >= 1)));
    process.exit(ok ? 0 : 1);
  '
}
if node_ok; then
  echo "node $(node --version) already satisfies REA 6.9.0"
else
  NODE_VER="v24.22.3"
  NODE_ASSET="node-$NODE_VER-linux-x64.tar.xz"
  NODE_BASE="https://nodejs.org/dist/$NODE_VER"
  TMP_NODE=$(mktemp -d)
  if curl -fsSL "$NODE_BASE/$NODE_ASSET" -o "$TMP_NODE/$NODE_ASSET" &&
    curl -fsSL "$NODE_BASE/SHASUMS256.txt" -o "$TMP_NODE/SHASUMS256.txt"; then
    WANT=$(grep -E "[[:space:]]$NODE_ASSET\$" "$TMP_NODE/SHASUMS256.txt" | awk '{print $1}' | head -n1)
    GOT=$(sha256sum "$TMP_NODE/$NODE_ASSET" | awk '{print $1}')
    if [ -n "$WANT" ] && [ "$WANT" = "$GOT" ]; then
      tar -xJf "$TMP_NODE/$NODE_ASSET" -C /usr/local --strip-components=1
      echo "installed node $(node --version) into /usr/local"
    else
      echo "WARN: SHA-256 mismatch for $NODE_ASSET (want ${WANT:-?} got ${GOT:-?})"
    fi
  else
    echo "WARN: could not download $NODE_BASE/$NODE_ASSET"
  fi
  rm -rf "$TMP_NODE"
  node_ok || echo "WARN: node still does not satisfy REA 6.9.0; the rea-linux row will fail to start"
fi

echo "== Python analysis tools (pipx keeps them isolated) =="
pipx ensurepath
for pkg in pwntools binwalk unblob mitmproxy; do
  echo "-- $pkg"
  pipx install --force "$pkg" || echo "WARN: $pkg install failed"
done

echo "== REA (rea-agents) for the Linux MCP instance =="
npm install -g "rea-agents@6.9.0" || echo "WARN: rea-agents global install failed"

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
