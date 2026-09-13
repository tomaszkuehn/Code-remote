# Instalacja zdalnego opencode na nowym komputerze

Zestaw: opencode (npm) + serwer na porcie 4096 + bot Telegram (`@grinev/opencode-telegram-bot`) + plugin dźwięków/auto-kontynuacji + komenda `/pomoc` + ikona w tray (autostart serwera i bota przy logowaniu).

Folder jest **bez danych prywatnych** (żadnych tokenów/ID/userów) — prywatne dane wpisujesz tylko przy instalacji:
- token bota tworzysz sam przez @BotFather (`/newbot`),
- swoje Telegram ID podaje @userinfobot,
- w `.env` bota nic nie trzymaj na stałe w tym repozytorium.

Kopiując folder gdziekolwiek (git, pendrive, chmura) nie wyciekasz danymi.

## Pozyskanie identyfikatorów z Telegramu (5 minut)

**1. Token bota** (każda maszyna = nowy bot):
1. Otwórz [@BotFather](https://t.me/BotFather) w Telegramie, wyślij `/newbot`,
2. podaj nazwę wyświetlaną (dowolna, np. `opencode remote`),
3. podaj username kończący się na `bot` (np. `moj_nazwisko_oc_bot`),
4. skopiuj token z odpowiedzi — format `123456:ABC-DEF1234...` (to parametr `-t` / `-TelegramToken`).

**2. Twoje Telegram User ID** (to samo na wszystkich maszynach):
1. Otwórz [@userinfobot](https://t.me/userinfobot), wyślij dowolną wiadomość (np. `hi`),
2. w odpowiedzi odczytaj numer `Id:` (10-cyfrowy) — to parametr `-u` / `-TelegramUserId`.

Bezpieczeństwo: token traktuj jak hasło (nie wrzucaj do gita). ID nie jest tajne, ale pełni rolę whitelisty — bot ignoruje wszystkich innych, nawet znających nazwę bota.

## Wymagania

- Windows 10/11 (PowerShell 5.1+) **lub Linux** (Ubuntu/Debian/Fedora/Arch) — 64-bit,
- internet; winget (do Node.js) albo ręcznie zainstalowany Node.js 22.14+,
- konto Telegramu, dostęp do @BotFather i @userinfobot.

## Instalacja na Linux

```bash
cd /sciezka/do/code-remote
chmod +x install.sh
./install.sh -t "123456:ABC-DEF..." -u "TWOJE-ID"
# lub interaktywnie (zapyta o token i ID):
./install.sh
```

Różnice względem Windows:
- Node.js instalowany przez NodeSource (apt/dnf) lub pacman,
- autostart przez **systemd user units**: `opencode-serve.service` + `opencode-bot.service` (start po logowaniu; `loginctl enable-linger` — także bez sesji, np. serwer headless),
- configi: `~/.config/opencode/` i `~/.config/opencode-telegram-bot/`,
- logi bota: `journalctl --user -u opencode-bot -f`,
- `sound.js` nie zagra (odtwarza dźwięki przez PowerShell — plugin pomijalny na Linux; skrypt ostrzega),
- `.env` bota dostaje `chmod 600` (tylko właściciel),
- gdy globalny `npm prefix` wymaga roota, skrypt ustawia `~/.npm-global` i dopisuje do `~/.bashrc`,
- brak ikony w tray (`tray.ps1`/`install-tray.ps1` są tylko dla Windows; na Linux stan widać przez `systemctl --user status`).

> **Różnica daemon vs systemd:** na Windows bot działa jako **daemon** (`opencode-telegram start --daemon`, proces w tle, stan w `%APPDATA%\opencode-telegram-bot\run\bot-service.json`). Na Linux systemd sam pilnuje procesu, więc unit uruchamia bota w **foreground** (`opencode-telegram start`) i restartuje go przy padnięciu — **nie** używaj tam `--daemon` ani `opencode-telegram stop` (kolidowałyby z systemd).

Sterowanie usługami:
```bash
systemctl --user status opencode-bot      # stan
journalctl --user -u opencode-bot -f      # log na żywo
systemctl --user restart opencode-bot     # po zmianie plików
```

## Pliki w tym folderze

| Plik | Dokąd trafia | Co to |
|---|---|---|
| `install.ps1` (Windows) / `install.sh` (Linux) | — | Instalator (uruchamiasz tylko jeden) |
| `opencode.json` | `~\.config\opencode\` | uprawnienia, pluginy, instrukcje, providery |
| `instructions.md` | `~\.config\opencode\` | zasady zwięzłości dla modelu |
| `sound.js` | `~\.config\opencode\plugins\` | dźwięki + auto-wznawianie urwanych odpowiedzi |
| `package.json` | `~\.config\opencode\` | dep `@opencode-ai/plugin` |
| `pomoc.js` / generowany `pomoc.json` | `%APPDATA%\opencode-telegram-bot\local-commands\` | komenda `/pomoc` w bocie |
| `tray.ps1` + `launch-tray.vbs` | — (zostają w folderze) | ikona w tray: stan serwera i bota, restart, logi |
| `install-tray.ps1` | — | rejestruje autostart ikony tray (`opencode-tray`) |

## Uruchomienie (Windows)

```powershell
cd D:\kody\code-remote
.\install.ps1 -TelegramToken "123456:ABC-DEF..." -TelegramUserId "TWOJE-ID"
```

Token i User ID są też brane interaktywnie, jeśli nie podasz parametrów.
Skrypt zapyta tylko o brakujące dane.

Co robi skrypt (kolejno):
1. sprawdza/instaluje Node.js 22+ (winget, LTS),
2. `npm install -g opencode-ai` + `@grinev/opencode-telegram-bot`,
3. kopiuje configi do `~\.config\opencode\`, dopasowuje ścieżki usera, usuwa wpis MCP jeśli nie dotyczy, instaluje dep pluginu,
4. tworzy `%APPDATA%\opencode-telegram-bot\.env` (token, whitelist, model) + `/pomoc`,
5. rejestruje autostart serwera (zadanie `opencode-serve`, przy logowaniu) i startuje go,
6. startuje bota (daemon) i wypisuje PID,
7. rejestruje ikonę tray (zadanie `opencode-tray`, przy logowaniu) — zielona ikona `OC` = serwer i bot działają.

Po zakończeniu: otwórz czat z botem w Telegramie → `/status`.

### Ikona w tray (tylko Windows)

Po instalacji w zasobniku (obok zegara) siedzi ikona **`OC`**:
- **zielona** = serwer 4096 + bot działają, **żółta** = tylko serwer, **czerwona** = serwer stop,
- dwuklik = otwórz czat z botem; prawy przycisk = menu (restart bota/serwera, logi, folder konfiguracji, włącz/wyłącz autostart).

Ręczna instalacja/odinstalowanie ikony:
```powershell
cd D:\kody\code-remote
.\install-tray.ps1              # zarejestruj autostart i pokaż ikonę
.\install-tray.ps1 -Uninstall   # usuń autostart i zamknij ikonę
.\install-tray.ps1 -NoStart     # tylko autostart, bez uruchamiania teraz
```

## Po instalacji

- **Nowy token bota** na każdy komputer (patrz: „Pozyskanie identyfikatorów” wyżej). Whitelist ID: Twoje numeryczne ID z @userinfobot — bot odpowiada tylko Tobie.
- Autostart: na Windows bot działa jako daemon w tle, a ikona tray (`opencode-tray`) startuje serwer i bota przy logowaniu oraz pilnuje ich stanu — po restarcie komputera nie trzeba nic robić (ręcznie: prawy przycisk na ikonie → „Uruchom wszystko”). Na Linux robią to usługi systemd (`opencode-serve` + `opencode-bot`).
- Model zmienisz w czacie (przycisk w statusie); domyślny: `-DefaultModelProvider deepseek -DefaultModelId deepseek-v4-flash`.
- Serwer opencode wymaga zalogowanych providerów: na nowej maszynie uruchom `opencode` (TUI) i zaloguj się do providera (Anthropic/OpenAI/Google/opencode zen), inaczej bot pokaże brak modeli.
- Restart bota po zmianie plików: Windows → `opencode-telegram stop` + `opencode-telegram start --daemon` (albo ikona tray → „Restart bota”); Linux → `systemctl --user restart opencode-bot`.

## Co dalej ręcznie

- `opencode` w TUI — logowanie do providerów (klucze/API), ulubione modele (Ctrl+F) — widoczne potem w bocie,
- opcjonalnie STT/TTS (głosówki): zmienne `STT_API_URL`, `TTS_*` w `.env` bota,
- pełna dokumentacja: `D:\kody\OPENCODE_HOWTO.md` (skopiuj go też na nowy komputer).

## Rozwiązywanie problemów

| Objaw | Przyczyna / fix |
|---|---|
| Bot nie odpowiada na `/status` | sprawdz log (Win: `%APPDATA%\opencode-telegram-bot\logs\`, Lin: `journalctl --user -u opencode-bot -f`); whitelist ID w `.env` musi się zgadzać z Twoim ID (sec. „Pozyskanie identyfikatorów”); zły token = bot nie startuje |
| Zły token / bot wypada z błędem 401 | token od @BotFather skopiowany niecały — wygeneruj `/token` w @BotFather dla istniejącego bota i wklej do `.env`, restart bota |
| `Command failed` przy `/pomoc` | w `pomoc.json` `exec` musi mieć pełną ścieżkę (bez `%APPDATA%`) |
| Brak modeli w bocie | nie zalogowany provider — uruchom `opencode` w TUI i zaloguj się |
| Serwer nie startuje po restarcie | `Start-ScheduledTask opencode-serve`; log: `Get-ScheduledTaskInfo opencode-serve` |
| Bot działa tylko do restartu | Windows: ikona tray startuje go przy logowaniu (prawy przycisk → „Uruchom wszystko”), lub `opencode-telegram start --daemon`; Linux: `systemctl --user enable --now opencode-bot` |
| Brak ikony w tray po restarcie | `Start-ScheduledTask opencode-tray`; sprawdź `Get-ScheduledTask -TaskName opencode-tray`; instalacja: `.\install-tray.ps1` |