# Registers the tray icon (opencode server + Telegram bot) as an autostart entry at logon.
# Run: .\install-tray.ps1
param(
  [switch]$Uninstall,
  [switch]$NoStart
)

$ErrorActionPreference = "Stop"
function Ok($m)   { Write-Host "    OK: $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    WARNING: $m" -ForegroundColor Yellow }

$taskName = "opencode-tray"
$vbs = Join-Path $PSScriptRoot "launch-tray.vbs"
$ps1 = Join-Path $PSScriptRoot "tray.ps1"

if ($Uninstall) {
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -match 'tray\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Ok "Tray autostart removed"
  return
}

if (-not (Test-Path $vbs) -or -not (Test-Path $ps1)) { throw "Missing launch-tray.vbs / tray.ps1 next to this script" }

$action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "//B `"$vbs`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "OpenCode Remote tray (server 4096 + Telegram bot)" -Force | Out-Null
Ok "Autostart '$taskName' registered (icon at logon)"

if (-not $NoStart) {
  Start-Process -FilePath "wscript.exe" -ArgumentList "//B `"$vbs`""
  Start-Sleep -Seconds 2
  $alive = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -match 'tray\.ps1' }
  if ($alive) { Ok "Tray icon started" } else { Warn "Could not confirm startup - check manually: wscript $vbs" }
}
