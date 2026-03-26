#!/usr/bin/env bash

# Author: godspoon | https://github.com/godspoon
# License: MIT
# Source: https://github.com/godspoon/docripper

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# ─── System Dependencies ──────────────────────────────────────────────────────

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  ca-certificates \
  git \
  gnupg \
  procps \
  xdg-utils
msg_ok "Installed Dependencies"

# ─── Node.js 20 ──────────────────────────────────────────────────────────────

NODE_VERSION="20" setup_nodejs

# ─── Chromium System Libraries ───────────────────────────────────────────────
# Required by playwright-core's bundled Chromium for headless rendering

msg_info "Installing Chromium System Libraries"
$STD apt-get install -y \
  libasound2 \
  libatk-bridge2.0-0 \
  libatk1.0-0 \
  libcairo2 \
  libcups2 \
  libdbus-1-3 \
  libdrm2 \
  libegl1 \
  libgbm1 \
  libglib2.0-0 \
  libgtk-3-0 \
  libnspr4 \
  libnss3 \
  libpango-1.0-0 \
  libpangocairo-1.0-0 \
  libx11-6 \
  libx11-xcb1 \
  libxcb1 \
  libxcomposite1 \
  libxcursor1 \
  libxdamage1 \
  libxext6 \
  libxfixes3 \
  libxi6 \
  libxkbcommon0 \
  libxrandr2 \
  libxrender1 \
  libxshmfence1 \
  libxtst6 \
  fonts-liberation \
  fonts-noto-color-emoji 2>/dev/null || true
# Ubuntu 24.04 uses t64-suffixed package names for some of the above —
# the 2>/dev/null || true allows graceful fallback; add t64 variants below
$STD apt-get install -y \
  libatk1.0-0t64 \
  libcups2t64 \
  libglib2.0-0t64 \
  libgtk-3-0t64 \
  libasound2t64 2>/dev/null || true
msg_ok "Installed Chromium System Libraries"

# ─── Clone / Download DocRipper ──────────────────────────────────────────────

msg_info "Downloading DocRipper"
REPO_URL="https://github.com/godspoon/docripper"
INSTALL_DIR="/opt/docripper"

# Check if a release exists, otherwise fall back to main branch
# The || true inside $() prevents grep/sed exit-1 from killing the script
# under set -eo pipefail when the repo has no releases yet.
LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/godspoon/docripper/releases/latest" \
  2>/dev/null | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' || true)

if [[ -n "$LATEST_TAG" ]]; then
  $STD git clone --depth 1 --branch "$LATEST_TAG" "$REPO_URL" "$INSTALL_DIR"
  echo "$LATEST_TAG" >"$INSTALL_DIR/.version"
else
  $STD git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
  echo "main" >"$INSTALL_DIR/.version"
fi
msg_ok "Downloaded DocRipper"

# ─── Build ───────────────────────────────────────────────────────────────────

msg_info "Installing Node Dependencies"
cd "$INSTALL_DIR"
$STD npm install
msg_ok "Installed Node Dependencies"

msg_info "Building DocRipper"
$STD npm run build
msg_ok "Built DocRipper"

# ─── Chromium Binary ─────────────────────────────────────────────────────────

msg_info "Downloading Chromium (this may take a moment)"
cd "$INSTALL_DIR"
PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright $STD npx playwright install chromium
msg_ok "Downloaded Chromium"

# ─── Environment Config ───────────────────────────────────────────────────────

msg_info "Configuring DocRipper"

# Find the Chromium binary path (revision number may change with playwright updates)
CHROMIUM_BIN=$(find /opt/ms-playwright -name "chrome" -type f 2>/dev/null | head -1)
if [[ -z "$CHROMIUM_BIN" ]]; then
  CHROMIUM_BIN="/opt/ms-playwright/chromium-1208/chrome-linux64/chrome"
fi

cat >"$INSTALL_DIR/.env" <<EOF
NODE_ENV=production
PORT=5000

# Chromium binary path (set by installer — update if you reinstall playwright)
PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
PLAYWRIGHT_CHROMIUM_PATH=${CHROMIUM_BIN}

# Optional: Anthropic API key for AI quality analysis of extracted docs
# Get a free key at https://console.anthropic.com
# Without this, all scraping features still work — only the AI panel is disabled
# ANTHROPIC_API_KEY=sk-ant-...
EOF

msg_ok "Configured DocRipper"

# ─── Systemd Service ─────────────────────────────────────────────────────────

msg_info "Creating Service"
cat >/etc/systemd/system/docripper.service <<EOF
[Unit]
Description=DocRipper Documentation Extractor
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/docripper
EnvironmentFile=/opt/docripper/.env
ExecStart=/usr/bin/node dist/index.cjs
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

# Chromium needs higher file descriptor limits
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now docripper
msg_ok "Created Service"

# ─── Convenience scripts ──────────────────────────────────────────────────────

printf '#!/bin/bash\njournalctl -f -n 100 -u docripper -o cat\n' >/usr/bin/docripper-log
printf '#!/bin/bash\nsystemctl restart docripper\n' >/usr/bin/docripper-restart
printf '#!/bin/bash\nsystemctl stop docripper\n' >/usr/bin/docripper-stop
printf '#!/bin/bash\nsystemctl start docripper\n' >/usr/bin/docripper-start
chmod +x /usr/bin/docripper-{log,restart,stop,start}

# ─── Done ─────────────────────────────────────────────────────────────────────

motd_ssh
customize
cleanup_lxc
