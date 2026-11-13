<#
.SYNOPSIS
    Removes SuperWhisper Autosend: stops it, removes the sign-in shortcut and the installed files.
    SuperWhisper and its settings are not touched.
#>
$ErrorActionPreference = 'Stop'

$scriptName = 'superwhisper-autosend.ps1'
$installDir = Join-Path $env:LOCALAPPDATA 'SuperWhisperAutosend'
$startupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'SuperWhisper Autosend.lnk'

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

Write-Output 'SuperWhisper Autosend removed.'
