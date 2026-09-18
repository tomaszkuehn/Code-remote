#!/usr/bin/env bash
# Installer for the opencode + Telegram bot environment on Linux
# Usage: ./install.sh [-t "BOT_TOKEN"] [-u "USER_ID"] [-p PROVIDER] [-m MODEL] [-l LOCALE]
# Without parameters it prompts interactively.
set -euo pipefail

TELEGRAM_TOKEN=""
TELEGRAM_USER_ID=""
DEFAULT_PROVIDER="deepseek"
DEFAULT_MODEL="deepseek-v4-flash"
BOT_LOCALE="en"

while getopts "t:u:p:m:l:h" opt; do
  case "$opt" in
    t) TELEGRAM_TOKEN="$OPTARG" ;;
    u) TELEGRAM_USER_ID="$OPTARG" ;;
    p) DEFAULT_PROVIDER="$OPTARG" ;;
    m) DEFAULT_MODEL="$OPTARG" ;;
    l) BOT_LOCALE="$OPTARG" ;;
    h) echo "Usage: ./install.sh [-t token] [-u user_id] [-p provider] [-m model] [-l locale]"; exit 0 ;;
    *) echo "Unknown option. -h for help"; exit 1 ;;
  esac
done

step() { printf '\033[36m==> %s\033[0m\n' "$1"; }
ok()   { printf '\033[32m    OK: %s\033[0m\n' "$1"; }
warn() { printf '\033[33m    WARNING: %s\033[0m\n' "$1"; }
die()  { printf '\033[31mERROR: %s\033[0m\n' "$1"; exit 1; }

# ---------- 0. Basics ----------
step "Checking environment"
[ "$(uname -s)" = "Linux" ] || die "This script is for Linux"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|aarch64) ok "Architecture $ARCH" ;;
  *) warn "Architecture $ARCH untested - continuing" ;;
esac

SUDO=""
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then SUDO="sudo"; fi

# ---------- 1. Node.js 22+ ----------
step "Checking Node.js"
NODE_OK=0
if command -v node >/dev/null 2>&1; then
  NODE_VER="$(node --version | sed 's/^v//')"
  NODE_MAJOR="$(echo "$NODE_VER" | cut -d. -f1)"
  NODE_MINOR="$(echo "$NODE_VER" | cut -d. -f2)"
  if [ "$NODE_MAJOR" -gt 22 ] || { [ "$NODE_MAJOR" -eq 22 ] && [ "$NODE_MINOR" -ge 14 ]; }; then
    NODE_OK=1
    ok "Node.js v$NODE_VER already installed"
  else
    warn "Node.js $NODE_VER too old (22.14+ required)"
  fi
fi
if [ "$NODE_OK" -ne 1 ]; then
  step "Installing Node.js 22 (NodeSource)"
  if command -v apt-get >/dev/null 2>&1; then
    $SUDO apt-get update -y
    $SUDO apt-get install -y curl ca-certificates
    curl -fsSL https://deb.nodesource.com/setup_22.x | $SUDO bash -
    $SUDO apt-get install -y nodejs
  elif command -v dnf >/dev/null 2>&1; then
    curl -fsSL https://rpm.nodesource.com/setup_22.x | $SUDO bash -
    $SUDO dnf install -y nodejs
  elif command -v pacman >/dev/null 2>&1; then
    $SUDO pacman -Sy --noconfirm nodejs npm
  else
    die "Unknown package manager. Install Node.js 22+ manually and run again."
  fi
  command -v node >/dev/null 2>&1 || die "Node still unavailable after installation"
  ok "Installed Node.js $(node --version)"
fi

# ---------- 2. npm: opencode + bot ----------
step "Installing npm packages (opencode-ai, @grinev/opencode-telegram-bot)"
NPM="npm"
if ! npm prefix -g >/dev/null 2>&1 || [ ! -w "$(npm prefix -g)" ]; then
  # global prefix without root: ~/.npm-global
  mkdir -p "$HOME/.npm-global"
  npm config set prefix "$HOME/.npm-global" || true
  export PATH="$HOME/.npm-global/bin:$PATH"
  NPM="$HOME/.npm-global/bin/npm"
  ok "Global npm prefix: $HOME/.npm-global (add to PATH in ~/.bashrc: export PATH=\"\$HOME/.npm-global/bin:\$PATH\")"
  grep -q ".npm-global/bin" "$HOME/.bashrc" 2>/dev/null || echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$HOME/.bashrc"
fi
$NPM install -g opencode-ai@latest
$NPM install -g "@grinev/opencode-telegram-bot@latest"
ok "Global packages installed"
$NPM list -g --depth=0 2>/dev/null | grep opencode || true

# ---------- 3. opencode config ----------
step "Configuring opencode (~/.config/opencode)"
OC_CFG="$HOME/.config/opencode"
OC_PLUG="$OC_CFG/plugins"
mkdir -p "$OC_PLUG"
SRC="$(cd "$(dirname "$0")" && pwd)"

for f in opencode.json instructions.md package.json; do
  if [ -f "$SRC/$f" ]; then
    cp -f "$SRC/$f" "$OC_CFG/$f"
    ok "Copied $OC_CFG/$f"
  else
    warn "Missing $SRC/$f - skipped"
  fi
done
if [ -f "$SRC/sound.js" ]; then
  cp -f "$SRC/sound.js" "$OC_PLUG/sound.js"
  ok "Copied $OC_PLUG/sound.js"
fi

# fix user paths in opencode.json
sed -i "s|C:\\\\\\\\Users\\\\\\\\YOUR-USER|$HOME|g" "$OC_CFG/opencode.json" 2>/dev/null || true
sed -i "s|C:\\\\Users\\\\YOUR-USER|$HOME|g" "$OC_CFG/opencode.json" 2>/dev/null || true
# Linux: sound.js plays through powershell (Windows) - disable when powershell is missing
if ! command -v powershell.exe >/dev/null 2>&1 && ! command -v pwsh >/dev/null 2>&1; then
  warn "No PowerShell on Linux - sound.js will not play (you can remove the plugin file)"
fi

# MCP: the .ijfw path may not exist - remove the entry
if [ ! -f "$HOME/.ijfw/mcp-server/src/server.js" ]; then
  warn "No .ijfw mcp-server - removing MCP entry from config"
  node -e "
    const fs = require('fs');
    const p = '$OC_CFG/opencode.json';
    const c = JSON.parse(fs.readFileSync(p, 'utf8'));
    delete c.mcp;
    fs.writeFileSync(p, JSON.stringify(c, null, 2));
  "
fi

# plugin dependency
( cd "$OC_CFG" && $NPM install --no-fund --no-audit "@opencode-ai/plugin@latest" >/dev/null 2>&1 ) || warn "Installing @opencode-ai/plugin failed"
ok "opencode config ready"

# ---------- 4. Bot: .env ----------
step "Configuring the Telegram bot (~/.config/opencode-telegram-bot)"
BOT_DIR="$HOME/.config/opencode-telegram-bot"
BOT_LC="$BOT_DIR/local-commands"
mkdir -p "$BOT_LC"

if [ -z "$TELEGRAM_TOKEN" ]; then read -r -p "Enter the bot token from @BotFather: " TELEGRAM_TOKEN; fi
if [ -z "$TELEGRAM_USER_ID" ]; then read -r -p "Enter your Telegram User ID (from @userinfobot): " TELEGRAM_USER_ID; fi
[ -n "$TELEGRAM_TOKEN" ] || die "Bot token is required"

cat > "$BOT_DIR/.env" <<EOF
TELEGRAM_BOT_TOKEN=$TELEGRAM_TOKEN
TELEGRAM_ALLOWED_USER_ID=$TELEGRAM_USER_ID
OPENCODE_API_URL=http://localhost:4096
OPENCODE_MODEL_PROVIDER=$DEFAULT_PROVIDER
OPENCODE_MODEL_ID=$DEFAULT_MODEL
BOT_LOCALE=$BOT_LOCALE
LOG_LEVEL=info
EOF
chmod 600 "$BOT_DIR/.env"
ok "Saved $BOT_DIR/.env (chmod 600)"

# /guide command
if [ -f "$SRC/guide.js" ]; then
  cp -f "$SRC/guide.js" "$BOT_LC/guide.js"
  cat > "$BOT_LC/guide.json" <<EOF
{
  "description": "Short bot tutorial: sessions, projects, commands",
  "exec": "node $BOT_LC/guide.js",
  "allowWhenBusy": true
}
EOF
  ok "/guide command installed"
fi

# ---------- 5. systemd: server + bot ----------
step "systemd units (user)"
SYSTEMD_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_DIR"
export PATH="$HOME/.npm-global/bin:$PATH"
OPENCODE_BIN="$(command -v opencode || echo "$HOME/.npm-global/bin/opencode")"
BOT_BIN="$(command -v opencode-telegram || echo "$HOME/.npm-global/bin/opencode-telegram")"

cat > "$SYSTEMD_DIR/opencode-serve.service" <<EOF
[Unit]
Description=OpenCode server port 4096 (Telegram bot)
After=network.target

[Service]
ExecStart=$OPENCODE_BIN serve --port 4096
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

cat > "$SYSTEMD_DIR/opencode-bot.service" <<EOF
[Unit]
Description=OpenCode Telegram bot
After=opencode-serve.service
Requires=opencode-serve.service

[Service]
ExecStart=$BOT_BIN start
WorkingDirectory=$HOME
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now opencode-serve.service
sleep 4
systemctl --user enable --now opencode-bot.service
# keep running after logout (independent of an active session)
loginctl enable-linger "$USER" 2>/dev/null || warn "enable-linger failed - the bot runs only while logged in"
ok "Services opencode-serve and opencode-bot started"

# ---------- 6. Verification ----------
step "Verification"
sleep 4
if curl -sf -o /dev/null "http://localhost:4096/app"; then
  ok "opencode server: http://localhost:4096 responds"
else
  warn "Server not responding: systemctl --user status opencode-serve"
fi
systemctl --user status opencode-bot.service --no-pager -n 3 || true

echo
printf '\033[35mDONE. Open the bot chat in Telegram and send /status\033[0m\n'
printf '\033[35mLogs: journalctl --user -u opencode-bot -f\033[0m\n'
printf '\033[35mSee README.md\033[0m\n'
