#!/usr/bin/env bash
# Instalator srodowiska opencode + Telegram bot na Linux
# Uzycie: ./install.sh [-t "TOKEN_BOTA"] [-u "USER_ID"] [-p PROVIDER] [-m MODEL] [-l LOCALE]
# Bez parametrow zapyta interaktywnie.
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
    h) echo "Uzycie: ./install.sh [-t token] [-u user_id] [-p provider] [-m model] [-l locale]"; exit 0 ;;
    *) echo "Nieznana opcja. -h = pomoc"; exit 1 ;;
  esac
done

step() { printf '\033[36m==> %s\033[0m\n' "$1"; }
ok()   { printf '\033[32m    OK: %s\033[0m\n' "$1"; }
warn() { printf '\033[33m    UWAGA: %s\033[0m\n' "$1"; }
die()  { printf '\033[31mBLAD: %s\033[0m\n' "$1"; exit 1; }

# ---------- 0. Podstawy ----------
step "Sprawdzanie srodowiska"
[ "$(uname -s)" = "Linux" ] || die "Ten skrypt jest dla Linuxa"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|aarch64) ok "Architektura $ARCH" ;;
  *) warn "Architektura $ARCH nie testowana - kontynuuje" ;;
esac

SUDO=""
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then SUDO="sudo"; fi

# ---------- 1. Node.js 22+ ----------
step "Sprawdzanie Node.js"
NODE_OK=0
if command -v node >/dev/null 2>&1; then
  NODE_VER="$(node --version | sed 's/^v//')"
  NODE_MAJOR="$(echo "$NODE_VER" | cut -d. -f1)"
  NODE_MINOR="$(echo "$NODE_VER" | cut -d. -f2)"
  if [ "$NODE_MAJOR" -gt 22 ] || { [ "$NODE_MAJOR" -eq 22 ] && [ "$NODE_MINOR" -ge 14 ]; }; then
    NODE_OK=1
    ok "Node.js v$NODE_VER juz zainstalowany"
  else
    warn "Node.js $NODE_VER za stary (wymagany 22.14+)"
  fi
fi
if [ "$NODE_OK" -ne 1 ]; then
  step "Instalacja Node.js 22 (NodeSource)"
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
    die "Nieznany package manager. Zainstaluj Node.js 22+ recznie i uruchom ponownie."
  fi
  command -v node >/dev/null 2>&1 || die "Node nadal niedostepny po instalacji"
  ok "Zainstalowano Node.js $(node --version)"
fi

# ---------- 2. npm: opencode + bot ----------
step "Instalacja pakietow npm (opencode-ai, @grinev/opencode-telegram-bot)"
NPM="npm"
if ! npm prefix -g >/dev/null 2>&1 || [ ! -w "$(npm prefix -g)" ]; then
  # globalny prefix bez roota: ~/.npm-global
  mkdir -p "$HOME/.npm-global"
  npm config set prefix "$HOME/.npm-global" || true
  export PATH="$HOME/.npm-global/bin:$PATH"
  NPM="$HOME/.npm-global/bin/npm"
  ok "Globalny prefix npm: $HOME/.npm-global (dodaj do PATH w ~/.bashrc: export PATH=\"\$HOME/.npm-global/bin:\$PATH\")"
  grep -q ".npm-global/bin" "$HOME/.bashrc" 2>/dev/null || echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$HOME/.bashrc"
fi
$NPM install -g opencode-ai@latest
$NPM install -g "@grinev/opencode-telegram-bot@latest"
ok "Pakiety globalne zainstalowane"
$NPM list -g --depth=0 2>/dev/null | grep opencode || true

# ---------- 3. Config opencode ----------
step "Konfiguracja opencode (~/.config/opencode)"
OC_CFG="$HOME/.config/opencode"
OC_PLUG="$OC_CFG/plugins"
mkdir -p "$OC_PLUG"
SRC="$(cd "$(dirname "$0")" && pwd)"

for f in opencode.json instructions.md package.json; do
  if [ -f "$SRC/$f" ]; then
    cp -f "$SRC/$f" "$OC_CFG/$f"
    ok "Skopiowano $OC_CFG/$f"
  else
    warn "Brak $SRC/$f - pominieto"
  fi
done
if [ -f "$SRC/sound.js" ]; then
  cp -f "$SRC/sound.js" "$OC_PLUG/sound.js"
  ok "Skopiowano $OC_PLUG/sound.js"
fi

# poprawka sciezek usera w opencode.json
sed -i "s|C:\\\\\\\\Users\\\\\\\\TWOJ-USER|$HOME|g" "$OC_CFG/opencode.json" 2>/dev/null || true
sed -i "s|C:\\\\Users\\\\TWOJ-USER|$HOME|g" "$OC_CFG/opencode.json" 2>/dev/null || true
# Linux: sound.js odtwarza przez powershell (Windows) - wylacz przy braku powershell
if ! command -v powershell.exe >/dev/null 2>&1 && ! command -v pwsh >/dev/null 2>&1; then
  warn "Brak PowerShell na Linux - sound.js nie bedzie gral (mozna usunac plik pluginu)"
fi

# MCP: sciezka .ijfw moze nie istniec - usun wpis
if [ ! -f "$HOME/.ijfw/mcp-server/src/server.js" ]; then
  warn "Brak .ijfw mcp-server - usuwam wpis MCP z configu"
  node -e "
    const fs = require('fs');
    const p = '$OC_CFG/opencode.json';
    const c = JSON.parse(fs.readFileSync(p, 'utf8'));
    delete c.mcp;
    fs.writeFileSync(p, JSON.stringify(c, null, 2));
  "
fi

# dep pluginu
( cd "$OC_CFG" && $NPM install --no-fund --no-audit "@opencode-ai/plugin@latest" >/dev/null 2>&1 ) || warn "Instalacja @opencode-ai/plugin nie powiodla sie"
ok "Config opencode gotowy"

# ---------- 4. Bot: .env ----------
step "Konfiguracja bota Telegram (~/.config/opencode-telegram-bot)"
BOT_DIR="$HOME/.config/opencode-telegram-bot"
BOT_LC="$BOT_DIR/local-commands"
mkdir -p "$BOT_LC"

if [ -z "$TELEGRAM_TOKEN" ]; then read -r -p "Podaj token bota z @BotFather: " TELEGRAM_TOKEN; fi
if [ -z "$TELEGRAM_USER_ID" ]; then read -r -p "Podaj Twoje Telegram User ID (z @userinfobot): " TELEGRAM_USER_ID; fi
[ -n "$TELEGRAM_TOKEN" ] || die "Token bota wymagany"

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
ok "Zapisano $BOT_DIR/.env (chmod 600)"

# /pomoc
if [ -f "$SRC/pomoc.js" ]; then
  cp -f "$SRC/pomoc.js" "$BOT_LC/pomoc.js"
  cat > "$BOT_LC/pomoc.json" <<EOF
{
  "description": "Krotki samouczek bota: sesje, projekty, komendy",
  "exec": "node $BOT_LC/pomoc.js",
  "allowWhenBusy": true
}
EOF
  ok "Komenda /pomoc zainstalowana"
fi

# ---------- 5. systemd: serwer + bot ----------
step "Jednostki systemd (user)"
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
# bieg po wylogowaniu (bez zaleznosci od aktywnej sesji)
loginctl enable-linger "$USER" 2>/dev/null || warn "enable-linger nie powiodl sie - bot działa tylko przy zalogowanej sesji"
ok "Uslugi opencode-serve i opencode-bot uruchomione"

# ---------- 6. Weryfikacja ----------
step "Weryfikacja"
sleep 4
if curl -sf -o /dev/null "http://localhost:4096/app"; then
  ok "Serwer opencode: http://localhost:4096 odpowiada"
else
  warn "Serwer nie odpowiada: systemctl --user status opencode-serve"
fi
systemctl --user status opencode-bot.service --no-pager -n 3 || true

echo
printf '\033[35mGOTOWE. Otworz czat z botem w Telegramie i wyslij /status\033[0m\n'
printf '\033[35mLogi: journalctl --user -u opencode-bot -f\033[0m\n'
printf '\033[35mWiecej w README-INSTALACJA.md\033[0m\n'