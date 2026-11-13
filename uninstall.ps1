<#
.SYNOPSIS
    Removes SuperWhisper Autosend: stops it, removes the sign-in task/shortcut, the installed files, the log
    and the settings backups the installer made. SuperWhisper and its settings are not touched.
    Works from any folder, so it can also be run from a fresh download when the installed copy is gone.
#>
$ErrorActionPreference = 'Stop'

$scriptName = 'superwhisper-autosend.ps1'
$installDir = Join-Path $env:LOCALAPPDATA 'SuperWhisperAutosend'
$startupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'SuperWhisper Autosend.lnk'
$logPath = Join-Path $env:TEMP 'superwhisper-autosend.log'
$superWhisperDir = Join-Path $env:LOCALAPPDATA 'com.superwhisper.app'
$powershellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

# Same as in install.ps1: from inside a packaged app (MSIX, for example the Claude desktop app) this
# script would only see and remove that app's private copy, so it runs itself again as a normal
# process (created through WMI) from a copy in TEMP and relays the output.
$probeName = "superwhisper-autosend-probe-$([guid]::NewGuid().ToString('N'))"
$probe = Join-Path $env:LOCALAPPDATA $probeName
New-Item -ItemType Directory -Path $probe | Out-Null
$isRedirected = @(Get-Item -Path (Join-Path $env:LOCALAPPDATA "Packages\*\LocalCache\Local\$probeName") -Force -ErrorAction SilentlyContinue).Count -gt 0
Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
if ($isRedirected)
{
    $stage = Join-Path ([IO.Path]::GetTempPath()) "superwhisper-autosend-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $stage | Out-Null
    $stagedScript = Join-Path $stage 'uninstall.ps1'
    Copy-Item -LiteralPath $PSCommandPath -Destination $stagedScript
    $quote = { param($text) "'" + ($text -replace "'", "''") + "'" }
    $outputPath = Join-Path $stage 'output.txt'
    $exitPath = Join-Path $stage 'exitcode.txt'
    $command = "`$code = 0; try { & $(& $quote $stagedScript) *>&1 | Out-File -LiteralPath $(& $quote $outputPath) -Encoding utf8 -Width 4096 } " +
        "catch { `$_ | Out-File -LiteralPath $(& $quote $outputPath) -Encoding utf8 -Width 4096 -Append; `$code = 1 }; " +
        "[IO.File]::WriteAllText($(& $quote $exitPath), [string]`$code)"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $commandLine = "`"$powershellPath`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $encoded"
    $result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $commandLine }
    if ($result.ReturnValue -ne 0)
    {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
        throw "Could not start a normal PowerShell process (Win32_Process.Create returned $($result.ReturnValue)). Run this script from a normal PowerShell window instead."
    }
    $deadline = (Get-Date).AddMinutes(2)
    while ((Get-Process -Id $result.ProcessId -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline)
    {
        Start-Sleep -Milliseconds 300
    }
    if (Test-Path -LiteralPath $outputPath) { Get-Content -LiteralPath $outputPath -Encoding UTF8 }
    $exitCode = 1
    if (Test-Path -LiteralPath $exitPath) { $exitCode = [int](Get-Content -LiteralPath $exitPath -Raw) }
    else { Write-Output 'The uninstall process did not finish in time.' }
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    exit $exitCode
}

Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" |
    Where-Object { $_.CommandLine -like "*$scriptName*" -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Unregister-ScheduledTask -TaskName 'SuperWhisper Autosend' -Confirm:$false -ErrorAction SilentlyContinue
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
