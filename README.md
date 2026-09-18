# OpenCode Remote

Run [opencode](https://opencode.ai) on your computer and drive it from anywhere through a Telegram bot. The bot talks to the opencode server on port `4096`, so a single session stays alive and can be resumed from the TUI, from `opencode attach`, and from your phone at the same time.

Polish installation guide: [INSTALACAJA.md](INSTALACAJA.md).

## What this repo gives you

| Piece | What it does |
|---|---|
| `install.ps1` (Windows) / `install.sh` (Linux) | One-shot installer |
| `opencode.json`, `package.json` | opencode config (permissions, plugins, providers) |
| `sound.js` | Plugin: plays a sound on permission/question and auto-continues responses cut off by the output token limit |
| `guide.js` | `/guide` command content for the bot |
| `tray.ps1` + `launch-tray.vbs` + `install-tray.ps1` | Windows tray icon: server/bot status, restarts, logs, Telegram on/off, autostart |

No private data lives in this repo: no tokens, no user IDs. You create your own bot token with @BotFather and find your own ID with @userinfobot.

## Requirements

- Windows 10/11 (PowerShell 5.1+) **or** Linux (Ubuntu/Debian/Fedora/Arch), 64-bit
- Node.js 22.14+, internet access
- Telegram account with access to @BotFather and @userinfobot

## 1. Get your Telegram credentials (5 minutes)

**Bot token** (a new bot per machine):
1. Open [@BotFather](https://t.me/BotFather), send `/newbot`
2. Pick a display name (e.g. `opencode remote`)
3. Pick a username ending in `bot` (e.g. `my_name_oc_bot`)
4. Copy the token from the reply — format `123456:ABC-DEF1234...` (`-t` / `-TelegramToken`)

**Your Telegram User ID** (the same on every machine):
1. Open [@userinfobot](https://t.me/userinfobot), send any message
2. Read the `Id:` number (10 digits) — that is `-u` / `-TelegramUserId`

Treat the token like a password. The ID is the bot's allowlist: everyone else is ignored.

## 2. Install

**Windows** (PowerShell):
```powershell
cd path\to\code-remote
.\install.ps1 -TelegramToken "123456:ABC-DEF..." -TelegramUserId "YOUR-ID"
```
Without parameters the script prompts for the missing values.

**Linux**:
```bash
cd /path/to/code-remote
chmod +x install.sh
./install.sh -t "123456:ABC-DEF..." -u "YOUR-ID"
```

The installer:
1. checks/installs Node.js 22+,
2. installs the global npm packages `opencode-ai` and `@grinev/opencode-telegram-bot`,
3. copies the opencode config to `~/.config/opencode/`, fixes user paths and plugin deps,
4. writes the bot `.env` and the `/guide` command,
5. starts the opencode server on port 4096,
6. starts the bot,
7. on Windows also registers the tray icon autostart.

Optional flags: `-p/-DefaultModelProvider`, `-m/-DefaultModelId`, `-l/-BotLocale`.

## 3. Connect

After installation, open the bot chat and send `/status`. The server exposes:

```
http://localhost:4096
```

To work on the same session from your computer:

```powershell
cd path\to\project
opencode attach http://localhost:4096 -c        # continue the last session
opencode attach http://localhost:4096 -s ses_x  # a specific session
```

## Linux specifics

- Node.js via NodeSource (apt/dnf) or pacman
- Autostart through **systemd user units**: `opencode-serve.service` + `opencode-bot.service`; `loginctl enable-linger` keeps them running when logged out
- Config in `~/.config/opencode/` and `~/.config/opencode-telegram-bot/`
- Logs: `journalctl --user -u opencode-bot -f`
- `sound.js` cannot play sound without PowerShell — the plugin is optional on Linux
- The bot `.env` gets `chmod 600`
- No tray icon (`tray.ps1` / `install-tray.ps1` are Windows-only); state via `systemctl --user status`

> **daemon vs systemd:** on Windows the bot runs as a **daemon** (`opencode-telegram start --daemon`). On Linux systemd owns the process and runs the bot in the **foreground** (`opencode-telegram start`) — do not use `--daemon` or `opencode-telegram stop` there.

```bash
systemctl --user status opencode-bot      # state
journalctl --user -u opencode-bot -f      # live logs
systemctl --user restart opencode-bot     # after config changes
```

## Windows tray icon

The `OC` icon in the notification area:
- **green** = server + bot running, **yellow** = server only, **red** = server stopped
- double-click = open the Telegram chat
- right-click menu: status, open chat, Telegram communication on/off, restart bot/server, start everything, bot logs, config folder, start with system, close

Telegram communication can be toggled independently of the server. When disabled, a flag file `%APPDATA%\opencode-telegram-bot\run\telegram-disabled` keeps the bot off across logons; the server keeps running.

```powershell
.\install-tray.ps1              # register autostart and show the icon
.\install-tray.ps1 -Uninstall   # remove autostart and close the icon
.\install-tray.ps1 -NoStart     # autostart only, do not launch now
```

## After installation

- Use a **new bot token** on each computer; the allowlist ID stays the same.
- Default model: `-DefaultModelProvider deepseek -DefaultModelId deepseek-v4-flash`; change it in the chat.
- The opencode server needs a logged-in provider: run `opencode` (TUI) and sign in, otherwise the bot reports no models.
- Restart the bot after config changes: Windows → `opencode-telegram stop` + `opencode-telegram start --daemon` (or the tray menu); Linux → `systemctl --user restart opencode-bot`.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Bot does not answer `/status` | check logs (Win: `%APPDATA%\opencode-telegram-bot\logs\`, Lin: `journalctl --user -u opencode-bot -f`); the allowlist ID must match yours; a bad token stops the bot |
| `401` / bad token | the token was copied incomplete — issue `/token` in @BotFather, paste into `.env`, restart the bot |
| `Command failed` on `/guide` | `guide.json` `exec` must contain the full path |
| No models in the bot | no provider signed in — run `opencode` in the TUI and sign in |
| Server does not start after reboot | `Start-ScheduledTask opencode-serve`; check `Get-ScheduledTaskInfo opencode-serve` |
| Bot stops after reboot | Windows: the tray icon starts it at logon (or `opencode-telegram start --daemon`); Linux: `systemctl --user enable --now opencode-bot` |
| No tray icon after reboot | `Start-ScheduledTask opencode-tray`; check `Get-ScheduledTask -TaskName opencode-tray`; reinstall with `.\install-tray.ps1` |

## License

MIT — see [LICENSE](LICENSE).
