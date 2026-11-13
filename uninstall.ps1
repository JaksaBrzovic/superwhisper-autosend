<#
.SYNOPSIS
    Removes SuperWhisper Autosend: stops it, removes the sign-in shortcut, the installed files, the log
    and the settings backups the installer made. SuperWhisper and its settings are not touched.
    Works from any folder, so it can also be run from a fresh download when the installed copy is gone.
#>
$ErrorActionPreference = 'Stop'

$scriptName = 'superwhisper-autosend.ps1'
$installDir = Join-Path $env:LOCALAPPDATA 'SuperWhisperAutosend'
$startupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'SuperWhisper Autosend.lnk'
$logPath = Join-Path $env:TEMP 'superwhisper-autosend.log'
$superWhisperDir = Join-Path $env:LOCALAPPDATA 'com.superwhisper.app'

Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" |
    Where-Object { $_.CommandLine -like "*$scriptName*" -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Remove-Item -LiteralPath $startupLink -Force -ErrorAction SilentlyContinue

foreach ($file in @($scriptName, 'uninstall.ps1', 'config.json'))
{
    Remove-Item -LiteralPath (Join-Path $installDir $file) -Force -ErrorAction SilentlyContinue
}
if ((Test-Path -LiteralPath $installDir) -and -not (Get-ChildItem -LiteralPath $installDir -Force))
{
    Remove-Item -LiteralPath $installDir -Force
}

Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

# Backups of SuperWhisper settings files made when the installer turned on Auto Paste or Launch at login.
foreach ($folder in @($superWhisperDir, (Join-Path $superWhisperDir 'modes')))
{
    if (Test-Path -LiteralPath $folder)
    {
        Get-ChildItem -LiteralPath $folder -Filter '*.before-autosend.bak' -File -Force |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

Write-Output 'SuperWhisper Autosend removed.'
