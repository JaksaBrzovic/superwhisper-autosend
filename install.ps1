<#
.SYNOPSIS
    Installs SuperWhisper Autosend for the current Windows user (no admin rights needed).

.DESCRIPTION
    Copies the script to %LOCALAPPDATA%\SuperWhisperAutosend, starts it hidden and
    (unless -NoStartup) starts it automatically at Windows sign-in.

.PARAMETER Detect
    Changes nothing. Prints a JSON report: SuperWhisper shortcuts, Auto Paste state,
    and whether Autosend is installed/running. Use it before installing.

.PARAMETER EnableAutoPaste
    Turns on SuperWhisper's Auto Paste (required). SuperWhisper is restarted if running.
    A backup of each changed settings file is saved next to it (*.before-autosend.bak).

.PARAMETER PushToTalkShortcut
    Optional override, e.g. "Control+Space". Leave out to follow SuperWhisper's own setting.
    "none" (or an empty string) disables this shortcut. Use "none" when calling via
    powershell -File, which drops empty arguments.

.PARAMETER ToggleRecordingShortcut
    Optional override, e.g. "Control+Shift+Space". Same rules as above.

.PARAMETER NoStartup
    Do not start automatically at Windows sign-in.
#>
[CmdletBinding()]
param(
    [switch]$Detect,
    [switch]$EnableAutoPaste,
    [string]$PushToTalkShortcut,
    [string]$ToggleRecordingShortcut,
    [switch]$NoStartup
)

$ErrorActionPreference = 'Stop'

$scriptName = 'superwhisper-autosend.ps1'
$installDir = Join-Path $env:LOCALAPPDATA 'SuperWhisperAutosend'
$installedScript = Join-Path $installDir $scriptName
$configPath = Join-Path $installDir 'config.json'
$superWhisperDir = Join-Path $env:LOCALAPPDATA 'com.superwhisper.app'
$preferencesPath = Join-Path $superWhisperDir 'preferences.json'
$startupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'SuperWhisper Autosend.lnk'
$powershellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$launchArguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installedScript`""

function Read-JsonFile([string]$path)
{
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-TextFile([string]$path, [string]$text)
{
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $false))
}

function Get-ModePath($preferences)
{
    $mode = 'default'
    if ($null -ne $preferences -and $preferences.activeMode) { $mode = $preferences.activeMode }
    return Join-Path $superWhisperDir "modes\$mode.json"
}

function Get-AutosendProcesses
{
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" |
        Where-Object { $_.CommandLine -like "*$scriptName*" -and $_.ProcessId -ne $PID }
}

function Get-SuperWhisperProcess
{
    Get-Process Superwhisper -ErrorAction SilentlyContinue
}

function Get-Report
{
    $preferences = Read-JsonFile $preferencesPath
    $modePath = Get-ModePath $preferences
    $mode = Read-JsonFile $modePath
    $config = Read-JsonFile $configPath
    $globalAutoPaste = $null
    $modeAutoPaste = $null
    if ($null -ne $preferences) { $globalAutoPaste = $preferences.autoPasteEnabled }
    if ($null -ne $mode) { $modeAutoPaste = $mode.autoPaste }
    $effective = $globalAutoPaste
    if ($null -ne $modeAutoPaste) { $effective = $modeAutoPaste }

    [ordered]@{
        superWhisperInstalled   = $null -ne $preferences
        superWhisperRunning     = $null -ne (Get-SuperWhisperProcess)
        pushToTalkShortcut      = $(if ($null -ne $preferences) { $preferences.pushToTalkShortcut })
        toggleRecordingShortcut = $(if ($null -ne $preferences) { $preferences.toggleRecordingShortcut })
        cancelRecordingShortcut = $(if ($null -ne $preferences) { $preferences.cancelRecordingShortcut })
        autoPasteEnabled        = $globalAutoPaste
        activeMode              = $(if ($null -ne $preferences) { $preferences.activeMode })
        activeModeAutoPaste     = $modeAutoPaste
        autoPasteEffective      = $effective -eq $true
        autosendInstalled       = Test-Path -LiteralPath $installedScript
        autosendRunning         = @(Get-AutosendProcesses).Count -gt 0
        autosendStartsAtSignIn  = Test-Path -LiteralPath $startupLink
        autosendOverrides       = $config
    }
}

if ($Detect)
{
    Get-Report | ConvertTo-Json -Depth 4
    return
}

# ---------------------------------------------------------------- checks

if (-not (Test-Path -LiteralPath $preferencesPath))
{
    throw "SuperWhisper settings not found at $preferencesPath. Install SuperWhisper (https://superwhisper.com), open it once, then run this again."
}
$sourceScript = Join-Path $PSScriptRoot $scriptName
if (-not (Test-Path -LiteralPath $sourceScript))
{
    throw "$scriptName not found next to install.ps1. Run install.ps1 from the downloaded folder."
}

# ---------------------------------------------------------------- stop old copy, copy files

foreach ($process in Get-AutosendProcesses)
{
    Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Force -Path $installDir | Out-Null
foreach ($file in @($scriptName, 'uninstall.ps1'))
{
    $target = Join-Path $installDir $file
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $target -Force
    Unblock-File -LiteralPath $target
}

# ---------------------------------------------------------------- shortcut overrides

if ($PSBoundParameters.ContainsKey('PushToTalkShortcut') -or $PSBoundParameters.ContainsKey('ToggleRecordingShortcut'))
{
    $config = [ordered]@{}
    $existing = Read-JsonFile $configPath
    if ($null -ne $existing)
    {
        foreach ($property in $existing.PSObject.Properties) { $config[$property.Name] = $property.Value }
    }
    if ($PushToTalkShortcut -eq 'none') { $PushToTalkShortcut = '' }
    if ($ToggleRecordingShortcut -eq 'none') { $ToggleRecordingShortcut = '' }
    if ($PSBoundParameters.ContainsKey('PushToTalkShortcut')) { $config['pushToTalkShortcut'] = $PushToTalkShortcut }
    if ($PSBoundParameters.ContainsKey('ToggleRecordingShortcut')) { $config['toggleRecordingShortcut'] = $ToggleRecordingShortcut }
    Write-TextFile $configPath ($config | ConvertTo-Json)
}

# ---------------------------------------------------------------- Auto Paste

if ($EnableAutoPaste)
{
    $preferences = Read-JsonFile $preferencesPath
    $edits = @()
    $preferencesText = [IO.File]::ReadAllText($preferencesPath)
    if ($preferencesText -match '"autoPasteEnabled"\s*:\s*false')
    {
        $edits += , @($preferencesPath, ($preferencesText -replace '"autoPasteEnabled"(\s*):(\s*)false', '"autoPasteEnabled"$1:$2true'))
    }
    elseif ($preferencesText -notmatch '"autoPasteEnabled"\s*:\s*true')
    {
        Write-Warning 'Auto Paste setting not found in SuperWhisper settings. Turn it on in SuperWhisper > Settings.'
    }
    $modePath = Get-ModePath $preferences
    if (Test-Path -LiteralPath $modePath)
    {
        $modeText = [IO.File]::ReadAllText($modePath)
        if ($modeText -match '"autoPaste"\s*:\s*false')
        {
            $edits += , @($modePath, ($modeText -replace '"autoPaste"(\s*):(\s*)false', '"autoPaste"$1:$2true'))
        }
    }

    if ($edits.Count -gt 0)
    {
        $superWhisper = @(Get-SuperWhisperProcess)
        $superWhisperPath = $null
        if ($superWhisper.Count -gt 0)
        {
            $superWhisperPath = $superWhisper[0].Path
            $superWhisper | Stop-Process -Force
            $superWhisper | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
        }
        foreach ($edit in $edits)
        {
            Copy-Item -LiteralPath $edit[0] -Destination "$($edit[0]).before-autosend.bak" -Force
            Write-TextFile $edit[0] $edit[1]
        }
        if ($superWhisperPath)
        {
            Start-Process -FilePath $superWhisperPath
        }
        Write-Output 'SuperWhisper Auto Paste turned on.'
    }
    else
    {
        Write-Output 'SuperWhisper Auto Paste was already on.'
    }
}

# ---------------------------------------------------------------- start at sign-in

if ($NoStartup)
{
    Remove-Item -LiteralPath $startupLink -Force -ErrorAction SilentlyContinue
}
else
{
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($startupLink)
    $link.TargetPath = $powershellPath
    $link.Arguments = $launchArguments
    $link.WorkingDirectory = $installDir
    $link.WindowStyle = 7
    $link.Description = 'SuperWhisper Autosend'
    $link.Save()
}

# ---------------------------------------------------------------- start now (detached, hidden)

Start-Process -FilePath $powershellPath -ArgumentList $launchArguments -WorkingDirectory $installDir -WindowStyle Hidden
Start-Sleep -Seconds 2

Write-Output ''
Write-Output "Installed to $installDir"
Write-Output "Running: $(@(Get-AutosendProcesses).Count -gt 0)"
Write-Output "Starts at sign-in: $(-not $NoStartup)"
& $powershellPath -NoProfile -ExecutionPolicy Bypass -File $installedScript -Check
