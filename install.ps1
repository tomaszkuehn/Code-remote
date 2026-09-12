# Instalator srodowiska opencode + Telegram bot na nowym komputerze (Windows)
# Uruchomic w PowerShell: .\install.ps1 [-TelegramToken "..." -TelegramUserId "..."]
# Wymaga: uprawnien administratora NIE trzeba; internet; Windows 10/11

param(
  [string]$TelegramToken = "",
  [string]$TelegramUserId = "",
  [string]$DefaultModelProvider = "deepseek",
  [string]$DefaultModelId = "deepseek-v4-flash",
  [string]$BotLocale = "en"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    UWAGA: $msg" -ForegroundColor Yellow }
function Die($msg)  { Write-Host "BLAD: $msg" -ForegroundColor Red; exit 1 }

# ---------- 0. Podstawy ----------
Step "Sprawdzanie srodowiska"
if ($PSVersionTable.PSVersion.Major -lt 5) { Die "Wymagany PowerShell 5+" }
$is64 = [Environment]::Is64BitOperatingSystem
if (-not $is64) { Warn "System 32-bit - Node.js 22 wymaga 64-bit; instalacja moze sie nie powiesc" }
Ok "PowerShell $($PSVersionTable.PSVersion.Major), win$([Environment]::OSVersion.Version)"

# ---------- 1. Node.js 22+ ----------
Step "Sprawdzanie Node.js"
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
$nodeVersion = $null
if ($nodeCmd) {
  try { $nodeVersion = [version]((& node --version) -replace "^v", "") } catch {}
}
if ($nodeVersion -and $nodeVersion -ge [version]"22.14") {
  Ok "Node.js v$nodeVersion juz zainstalowany"
} else {
  Step "Instalacja Node.js 22 LTS przez winget"
  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if ($winget) {
    & winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { Warn "winget nie mial opcji LTS; probuje NodeJS 22"; & winget install --id OpenJS.NodeJS -e --accept-source-agreements --accept-package-agreements }
    # odswiezenie PATH dla biezacej sesji
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if (-not $nodeCmd) { Die "Node nie jest widoczny po instalacji - uruchom skrypt ponownie w nowym oknie PowerShell" }
    Ok "Zainstalowano Node.js $(& node --version)"
  } else {
    Die "Brak winget. Zainstaluj recznie Node.js 22+ z https://nodejs.org i uruchom skrypt ponownie."
  }
}

# ---------- 2. npm: opencode + telegram bot ----------
Step "Instalacja pakietow npm (opencode-ai, @grinev/opencode-telegram-bot)"
npm install -g opencode-ai@latest
if ($LASTEXITCODE -ne 0) { Die "npm install opencode-ai nie powiodl sie" }
npm install -g "@grinev/opencode-telegram-bot@latest"
if ($LASTEXITCODE -ne 0) { Die "npm install telegram bot nie powiodl sie" }
Ok "Pakiety globalne zainstalowane"
npm list -g --depth=0 | Select-String "opencode"

# ---------- 3. Config opencode ----------
Step "Konfiguracja opencode (~/.config/opencode)"
$ocCfgDir = Join-Path $env:USERPROFILE ".config\opencode"
$ocPlugDir = Join-Path $ocCfgDir "plugins"
New-Item -ItemType Directory -Force -Path $ocCfgDir, $ocPlugDir | Out-Null

$srcDir = $PSScriptRoot
$files = @(
  @{ src = "opencode.json";       dst = "$ocCfgDir\opencode.json" },
  @{ src = "instructions.md";     dst = "$ocCfgDir\instructions.md" },
  @{ src = "sound.js";            dst = "$ocPlugDir\sound.js" },
  @{ src = "package.json";        dst = "$ocCfgDir\package.json" }
)
foreach ($f in $files) {
  $src = Join-Path $srcDir $f.src
  if (Test-Path $src) {
    if (Test-Path $f.dst) {
      Copy-Item $src $f.dst -Force
      Ok "Nadpisano $($f.dst)"
    } else {
      Copy-Item $src $f.dst
      Ok "Skopiowano $($f.dst)"
    }
  } else {
    Warn "Brak pliku zrodlowego $($src) - pominieto"
  }
}

# poprawka sciezek usera w opencode.json (na innym komputerze user moze byc inny)
$ocJson = Get-Content "$ocCfgDir\opencode.json" -Raw
$ocJson = $ocJson -replace "C:\\\\Users\\\\[^\\\\]+", ($env:USERPROFILE -replace "\\", "\\\\")
Set-Content "$ocCfgDir\opencode.json" $ocJson -Encoding UTF8
Ok "Sciezki w opencode.json dopasowane do $env:USERNAME"

# MCP z configu wskazuje na C:\Users\<user>\.ijfw\mcp-server\src\server.js
# Jesli na tym komputerze go nie ma, wylaczamy wpis, zeby opencode nie errorowal
if (-not (Test-Path (Join-Path $env:USERPROFILE ".ijfw\mcp-server\src\server.js"))) {
  Warn "Brak .ijfw mcp-server - usuwam wpis MCP z configu"
  $cfg = Get-Content "$ocCfgDir\opencode.json" -Raw | ConvertFrom-Json
  $cfg.PSObject.Properties.Remove("mcp")
  $cfg | ConvertTo-Json -Depth 10 | Set-Content "$ocCfgDir\opencode.json" -Encoding UTF8
}

# dep pluginu dla importu sound.js
$pkg = Join-Path $ocCfgDir "package.json"
if (Test-Path $pkg) {
  Push-Location $ocCfgDir
  npm install --no-fund --no-audit "@opencode-ai/plugin@latest" 2>$null | Out-Null
  Pop-Location
  Ok "Zainstalowano @opencode-ai/plugin (dep sound.js)"
}

# ---------- 4. Bot: .env ----------
Step "Konfiguracja bota Telegram (%APPDATA%\opencode-telegram-bot)"
$botDir = Join-Path $env:APPDATA "opencode-telegram-bot"
$botLcDir = Join-Path $botDir "local-commands"
New-Item -ItemType Directory -Force -Path $botDir, $botLcDir | Out-Null

$envFile = Join-Path $botDir ".env"
if (-not $TelegramToken) { $TelegramToken = Read-Host "Podaj token bota z @BotFather" }
if (-not $TelegramUserId) { $TelegramUserId = Read-Host "Podaj Twoje Telegram User ID (z @userinfobot)" }
if (-not $TelegramToken) { Die "Token bota wymagany" }

@"
TELEGRAM_BOT_TOKEN=$TelegramToken
TELEGRAM_ALLOWED_USER_ID=$TelegramUserId
OPENCODE_API_URL=http://localhost:4096
OPENCODE_MODEL_PROVIDER=$DefaultModelProvider
OPENCODE_MODEL_ID=$DefaultModelId
BOT_LOCALE=$BotLocale
LOG_LEVEL=info
"@ | Set-Content $envFile -Encoding ASCII
Ok "Zapisano $envFile"

# komenda /pomoc
$pomocSrc = Join-Path $srcDir "pomoc.js"
if (Test-Path $pomocSrc) {
  Copy-Item $pomocSrc $botLcDir -Force
  # exec: pelna sciezka (%APPDATA% nie dziala w cmd /s /c)
  $pomocJson = Join-Path $botLcDir "pomoc.json"
  @{
    description = "Krotki samouczek bota: sesje, projekty, komendy"
    exec        = "node $(Join-Path $botLcDir 'pomoc.js')"
    allowWhenBusy = $true
  } | ConvertTo-Json | Set-Content $pomocJson -Encoding ASCII
  Ok "Komenda /pomoc zainstalowana"
}

# ---------- 5. Autostart serwera opencode (zaplanowane zadanie) ----------
Step "Rejestracja autostartu opencode serve (zadanie 'opencode-serve')"
$npmPrefix = (npm prefix -g).Trim()
$opencodeCmd = Join-Path $npmPrefix "opencode.cmd"
if (Test-Path $opencodeCmd) {
  $action  = New-ScheduledTaskAction -Execute $opencodeCmd -Argument "serve --port 4096"
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
  Register-ScheduledTask -TaskName "opencode-serve" -Action $action -Trigger $trigger -Description "OpenCode server port 4096 (Telegram bot)" -Force | Out-Null
  Ok "Zadanie opencode-serve zarejestrowane"
  Start-ScheduledTask -TaskName "opencode-serve"
  Start-Sleep -Seconds 4
} else {
  Warn "Nie znaleziono $opencodeCmd - autostart pominieto"
}

# ---------- 6. Weryfikacja ----------
Step "Weryfikacja"
$health = $false
try {
  $r = Invoke-WebRequest -Uri "http://localhost:4096/app" -UseBasicParsing -TimeoutSec 5
  $health = ($r.StatusCode -eq 200)
} catch {}
if ($health) { Ok "Serwer opencode: http://localhost:4096 odpowiada" }
else { Warn "Serwer opencode nie odpowiada - sprawdz: Get-ScheduledTaskInfo opencode-serve" }

$botCmd = Join-Path $npmPrefix "opencode-telegram.cmd"
if (Test-Path $botCmd) {
  Start-Process -FilePath $botCmd -ArgumentList "start", "--daemon" -WindowStyle Hidden -Wait
  Start-Sleep -Seconds 6
  if (Test-Path (Join-Path $botDir "run\bot-service.json")) {
    Ok "Bot (daemon) dziala - logi: $botDir\logs"
  } else {
    Warn "Bot nie wystartowal - sprawdz logi: $botDir\logs"
  }
}

# ---------- 7. Ikona tray + autostart (serwer + bot) ----------
Step "Instalacja ikony tray i autostartu (opencode-tray)"
$trayInstaller = Join-Path $srcDir "install-tray.ps1"
if (Test-Path $trayInstaller) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File $trayInstaller
} else {
  Warn "Brak install-tray.ps1 - ikona tray pominięta"
}

Write-Host ""
Write-Host "GOTOWE. Otworz czat z botem w Telegramie i wyslij /status" -ForegroundColor Magenta
Write-Host "Ikona tray 'OC' pokazuje stan serwera i bota." -ForegroundColor Magenta
Write-Host "Wiecej w README-INSTALACJA.md obok skryptu" -ForegroundColor Magenta