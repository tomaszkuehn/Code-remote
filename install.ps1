# Installer for the opencode + Telegram bot environment on a new computer (Windows)
# Run in PowerShell: .\install.ps1 [-TelegramToken "..." -TelegramUserId "..."]
# Requires: no administrator rights; internet; Windows 10/11

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
function Warn($msg) { Write-Host "    WARNING: $msg" -ForegroundColor Yellow }
function Die($msg)  { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# ---------- 0. Basics ----------
Step "Checking environment"
if ($PSVersionTable.PSVersion.Major -lt 5) { Die "PowerShell 5+ required" }
$is64 = [Environment]::Is64BitOperatingSystem
if (-not $is64) { Warn "32-bit system - Node.js 22 requires 64-bit; installation may fail" }
Ok "PowerShell $($PSVersionTable.PSVersion.Major), win$([Environment]::OSVersion.Version)"

# ---------- 1. Node.js 22+ ----------
Step "Checking Node.js"
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
$nodeVersion = $null
if ($nodeCmd) {
  try { $nodeVersion = [version]((& node --version) -replace "^v", "") } catch {}
}
if ($nodeVersion -and $nodeVersion -ge [version]"22.14") {
  Ok "Node.js v$nodeVersion already installed"
} else {
  Step "Installing Node.js 22 LTS via winget"
  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if ($winget) {
    & winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { Warn "winget had no LTS option; trying NodeJS 22"; & winget install --id OpenJS.NodeJS -e --accept-source-agreements --accept-package-agreements }
    # refresh PATH for the current session
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if (-not $nodeCmd) { Die "Node is not visible after installation - run this script again in a new PowerShell window" }
    Ok "Installed Node.js $(& node --version)"
  } else {
    Die "No winget. Install Node.js 22+ manually from https://nodejs.org and run the script again."
  }
}

# ---------- 2. npm: opencode + telegram bot ----------
Step "Installing npm packages (opencode-ai, @grinev/opencode-telegram-bot)"
npm install -g opencode-ai@latest
if ($LASTEXITCODE -ne 0) { Die "npm install opencode-ai failed" }
npm install -g "@grinev/opencode-telegram-bot@latest"
if ($LASTEXITCODE -ne 0) { Die "npm install telegram bot failed" }
Ok "Global packages installed"
npm list -g --depth=0 | Select-String "opencode"

# ---------- 3. opencode config ----------
Step "Configuring opencode (~/.config/opencode)"
$ocCfgDir = Join-Path $env:USERPROFILE ".config\opencode"
$ocPlugDir = Join-Path $ocCfgDir "plugins"
New-Item -ItemType Directory -Force -Path $ocCfgDir, $ocPlugDir | Out-Null

$srcDir = $PSScriptRoot
$files = @(
  @{ src = "opencode.json";       dst = "$ocCfgDir\opencode.json" },
  @{ src = "sound.js";            dst = "$ocPlugDir\sound.js" },
  @{ src = "package.json";        dst = "$ocCfgDir\package.json" }
)
foreach ($f in $files) {
  $src = Join-Path $srcDir $f.src
  if (Test-Path $src) {
    if (Test-Path $f.dst) {
      Copy-Item $src $f.dst -Force
      Ok "Overwrote $($f.dst)"
    } else {
      Copy-Item $src $f.dst
      Ok "Copied $($f.dst)"
    }
  } else {
    Warn "Missing source file $($src) - skipped"
  }
}

# fix user paths in opencode.json (the username may differ on another computer)
$ocJson = Get-Content "$ocCfgDir\opencode.json" -Raw
$ocJson = $ocJson -replace "C:\\\\Users\\\\[^\\\\]+", ($env:USERPROFILE -replace "\\", "\\\\")
Set-Content "$ocCfgDir\opencode.json" $ocJson -Encoding UTF8
Ok "Paths in opencode.json adjusted to $env:USERNAME"

# MCP from the config points to C:\Users\<user>\.ijfw\mcp-server\src\server.js
# If it is missing on this computer, disable the entry so opencode does not error out
if (-not (Test-Path (Join-Path $env:USERPROFILE ".ijfw\mcp-server\src\server.js"))) {
  Warn "No .ijfw mcp-server - removing MCP entry from config"
  $cfg = Get-Content "$ocCfgDir\opencode.json" -Raw | ConvertFrom-Json
  $cfg.PSObject.Properties.Remove("mcp")
  $cfg | ConvertTo-Json -Depth 10 | Set-Content "$ocCfgDir\opencode.json" -Encoding UTF8
}

# plugin dependency for the sound.js import
$pkg = Join-Path $ocCfgDir "package.json"
if (Test-Path $pkg) {
  Push-Location $ocCfgDir
  npm install --no-fund --no-audit "@opencode-ai/plugin@latest" 2>$null | Out-Null
  Pop-Location
  Ok "Installed @opencode-ai/plugin (sound.js dependency)"
}

# ---------- 4. Bot: .env ----------
Step "Configuring the Telegram bot (%APPDATA%\opencode-telegram-bot)"
$botDir = Join-Path $env:APPDATA "opencode-telegram-bot"
$botLcDir = Join-Path $botDir "local-commands"
New-Item -ItemType Directory -Force -Path $botDir, $botLcDir | Out-Null

$envFile = Join-Path $botDir ".env"
if (-not $TelegramToken) { $TelegramToken = Read-Host "Enter the bot token from @BotFather" }
if (-not $TelegramUserId) { $TelegramUserId = Read-Host "Enter your Telegram User ID (from @userinfobot)" }
if (-not $TelegramToken) { Die "Bot token is required" }

@"
TELEGRAM_BOT_TOKEN=$TelegramToken
TELEGRAM_ALLOWED_USER_ID=$TelegramUserId
OPENCODE_API_URL=http://localhost:4096
OPENCODE_MODEL_PROVIDER=$DefaultModelProvider
OPENCODE_MODEL_ID=$DefaultModelId
BOT_LOCALE=$BotLocale
LOG_LEVEL=info
"@ | Set-Content $envFile -Encoding ASCII
Ok "Saved $envFile"

# /guide command
$guideSrc = Join-Path $srcDir "guide.js"
if (Test-Path $guideSrc) {
  Copy-Item $guideSrc $botLcDir -Force
  # exec: full path (%APPDATA% does not work in cmd /s /c)
  $guideJson = Join-Path $botLcDir "guide.json"
  @{
    description = "Short bot tutorial: sessions, projects, commands"
    exec        = "node $(Join-Path $botLcDir 'guide.js')"
    allowWhenBusy = $true
  } | ConvertTo-Json | Set-Content $guideJson -Encoding ASCII
  Ok "/guide command installed"
}

# ---------- 5. opencode server autostart (scheduled task) ----------
Step "Registering opencode serve autostart (task 'opencode-serve')"
$npmPrefix = (npm prefix -g).Trim()
$opencodeCmd = Join-Path $npmPrefix "opencode.cmd"
if (Test-Path $opencodeCmd) {
  $action  = New-ScheduledTaskAction -Execute $opencodeCmd -Argument "serve --port 4096"
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
  Register-ScheduledTask -TaskName "opencode-serve" -Action $action -Trigger $trigger -Description "OpenCode server port 4096 (Telegram bot)" -Force | Out-Null
  Ok "Task opencode-serve registered"
  Start-ScheduledTask -TaskName "opencode-serve"
  Start-Sleep -Seconds 4
} else {
  Warn "Not found: $opencodeCmd - autostart skipped"
}

# ---------- 6. Verification ----------
Step "Verification"
$health = $false
try {
  $r = Invoke-WebRequest -Uri "http://localhost:4096/app" -UseBasicParsing -TimeoutSec 5
  $health = ($r.StatusCode -eq 200)
} catch {}
if ($health) { Ok "opencode server: http://localhost:4096 responds" }
else { Warn "opencode server not responding - check: Get-ScheduledTaskInfo opencode-serve" }

$botCmd = Join-Path $npmPrefix "opencode-telegram.cmd"
if (Test-Path $botCmd) {
  Start-Process -FilePath $botCmd -ArgumentList "start", "--daemon" -WindowStyle Hidden -Wait
  Start-Sleep -Seconds 6
  if (Test-Path (Join-Path $botDir "run\bot-service.json")) {
    Ok "Bot (daemon) running - logs: $botDir\logs"
  } else {
    Warn "Bot did not start - check logs: $botDir\logs"
  }
}

# ---------- 7. Tray icon + autostart (server + bot) ----------
Step "Installing tray icon and autostart (opencode-tray)"
$trayInstaller = Join-Path $srcDir "install-tray.ps1"
if (Test-Path $trayInstaller) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File $trayInstaller
} else {
  Warn "Missing install-tray.ps1 - tray icon skipped"
}

Write-Host ""
Write-Host "DONE. Open the bot chat in Telegram and send /status" -ForegroundColor Magenta
Write-Host "The 'OC' tray icon shows the server and bot status." -ForegroundColor Magenta
Write-Host "See README.md next to this script for details" -ForegroundColor Magenta
