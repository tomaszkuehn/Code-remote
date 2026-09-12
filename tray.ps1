# Tray dla zdalnego opencode: serwer (4096) + bot Telegram
# Uruchamiany przez launch-tray.vbs (bez okna). Startuje z systemem (zadanie opencode-tray).

$ErrorActionPreference = "SilentlyContinue"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$botDir    = Join-Path $env:APPDATA "opencode-telegram-bot"
$logsDir   = Join-Path $botDir "logs"
$envFile   = Join-Path $botDir ".env"
$opencodeCfg = Join-Path $env:USERPROFILE ".config\opencode"

function Resolve-Cmd($name) {
  $c = Get-Command "$name.cmd" -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  try { return (Join-Path ((npm prefix -g).Trim()) "$name.cmd") } catch { return $null }
}
$script:botCmd    = Resolve-Cmd "opencode-telegram"
$script:serverCmd = Resolve-Cmd "opencode"

function Test-Server {
  $client = New-Object System.Net.Sockets.TcpClient
  try {
    $iar = $client.BeginConnect("127.0.0.1", 4096, $null, $null)
    if ($iar.AsyncWaitHandle.WaitOne(400)) { $client.EndConnect($iar); return $true }
    return $false
  } catch { return $false } finally { $client.Close() }
}

function Get-BotPid {
  $f = Join-Path $botDir "run\bot-service.json"
  if (Test-Path $f) {
    try {
      $j = Get-Content $f -Raw | ConvertFrom-Json
      if ($j.pid -and (Get-Process -Id $j.pid -ErrorAction SilentlyContinue)) { return [int]$j.pid }
    } catch {}
  }
  return 0
}

function Get-TelegramUser {
  try {
    $line = Get-Content $envFile | Where-Object { $_ -match '^TELEGRAM_BOT_TOKEN=' } | Select-Object -First 1
    $token = ($line -split '=', 2)[1].Trim()
    if ($token) { return (Invoke-RestMethod "https://api.telegram.org/bot$token/getMe" -TimeoutSec 5).result.username }
  } catch {}
  return $null
}

function Start-Bot {
  if (-not $script:botCmd) { return }
  if (Get-BotPid) { return }
  Start-Process -FilePath $script:botCmd -ArgumentList "start", "--daemon" -WindowStyle Hidden -Wait
}
function Stop-Bot {
  if (-not $script:botCmd) { return }
  Start-Process -FilePath $script:botCmd -ArgumentList "stop" -WindowStyle Hidden -Wait
}
function Restart-Bot { Stop-Bot; Start-Sleep -Seconds 1; Start-Bot }

function Start-Server {
  if (Test-Server) { return }
  Start-ScheduledTask -TaskName "opencode-serve" -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 3
  if (-not (Test-Server) -and $script:serverCmd) {
    Start-Process -FilePath $script:serverCmd -ArgumentList "serve", "--port", "4096" -WindowStyle Hidden
    Start-Sleep -Seconds 3
  }
}
function Restart-Server {
  $conn = Get-NetTCPConnection -LocalPort 4096 -State Listen -ErrorAction SilentlyContinue
  if ($conn) { Stop-Process -Id $conn.OwningProcess -Force }
  Start-Sleep -Seconds 1
  Start-Server
}

function New-StatusIcon([System.Drawing.Color]$color) {
  $bmp = New-Object System.Drawing.Bitmap 32, 32
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.Clear([System.Drawing.Color]::Transparent)
  $brush = New-Object System.Drawing.SolidBrush $color
  $g.FillEllipse($brush, 1, 1, 30, 30)
  $font = New-Object System.Drawing.Font "Segoe UI", 11, ([System.Drawing.FontStyle]::Bold)
  $sf = New-Object System.Drawing.StringFormat
  $sf.Alignment = [System.Drawing.StringAlignment]::Center
  $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
  $rect = New-Object System.Drawing.RectangleF 0, 0, 32, 32
  $g.DrawString("OC", $font, [System.Drawing.Brushes]::White, $rect, $sf)
  $g.Dispose()
  return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}
$script:iconGreen  = New-StatusIcon ([System.Drawing.Color]::FromArgb(46,160,67))
$script:iconYellow = New-StatusIcon ([System.Drawing.Color]::FromArgb(230,160,20))
$script:iconRed    = New-StatusIcon ([System.Drawing.Color]::FromArgb(210,50,50))

$script:telegramUser = Get-TelegramUser

$form = New-Object System.Windows.Forms.Form
$form.ShowInTaskbar = $false
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$statusItem = $menu.Items.Add("Status: ...")
$statusItem.Enabled = $false
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$openTgItem   = $menu.Items.Add("Otworz czat w Telegramie")
$restartBot   = $menu.Items.Add("Restart bota Telegram")
$restartSrv   = $menu.Items.Add("Restart serwera opencode")
$startAllItem = $menu.Items.Add("Uruchom wszystko")
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$logsItem     = $menu.Items.Add("Logi bota")
$cfgItem      = $menu.Items.Add("Folder konfiguracji")
$autoItem     = $menu.Items.Add("Autostart z systemem")
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$exitItem     = $menu.Items.Add("Zamknij ikone w tray")

$openTgItem.Add_Click({
  if ($script:telegramUser) { Start-Process "https://t.me/$script:telegramUser" }
  else { Start-Process "tg://" }
})
$restartBot.Add_Click({ Restart-Bot })
$restartSrv.Add_Click({ Restart-Server })
$startAllItem.Add_Click({ Start-Server; Start-Bot })
$logsItem.Add_Click({
  $latest = Get-ChildItem $logsDir -Filter *.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($latest) { Start-Process notepad.exe $latest.FullName } else { Start-Process explorer.exe $logsDir }
})
$cfgItem.Add_Click({ Start-Process explorer.exe $opencodeCfg })
$autoItem.Add_Click({
  $t = Get-ScheduledTask -TaskName "opencode-tray" -ErrorAction SilentlyContinue
  if ($t -and $t.State -eq "Disabled") { Enable-ScheduledTask -TaskName "opencode-tray" | Out-Null }
  elseif ($t) { Disable-ScheduledTask -TaskName "opencode-tray" | Out-Null }
  Refresh-Status
})
$exitItem.Add_Click({
  $tray.Visible = $false
  $tray.Dispose()
  $form.Close()
  [System.Windows.Forms.Application]::Exit()
})

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.ContextMenuStrip = $menu
$tray.Visible = $true

function Refresh-Status {
  $srv = Test-Server
  $bot = (Get-BotPid) -ne 0
  if ($srv -and $bot) {
    $tray.Icon = $script:iconGreen
    $tray.Text = "OpenCode Remote: serwer OK, bot OK"
  } elseif ($srv) {
    $tray.Icon = $script:iconYellow
    $tray.Text = "OpenCode Remote: serwer OK, bot STOP"
  } else {
    $tray.Icon = $script:iconRed
    $tray.Text = "OpenCode Remote: serwer STOP"
  }
  $statusItem.Text = "Serwer: $(if($srv){'dziala'}else{'stop'})   |   Bot: $(if($bot){'dziala'}else{'stop'})"
  $t = Get-ScheduledTask -TaskName "opencode-tray" -ErrorAction SilentlyContinue
  $autoItem.Text = "Autostart z systemem: $(if($t -and $t.State -ne 'Disabled'){'wlaczony'}else{'wylaczony'})"
}
$tray.Add_MouseDoubleClick({ if ($script:telegramUser) { Start-Process "https://t.me/$script:telegramUser" } })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 10000
$timer.Add_Tick({ Refresh-Status })
$timer.Start()

Start-Server
Start-Bot
Refresh-Status

[System.Windows.Forms.Application]::Run($form)
