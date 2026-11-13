<#
.SYNOPSIS
    Presses Enter after a SuperWhisper dictation is pasted into the message box
    of the Claude or ChatGPT/Codex desktop app, so the message is sent automatically.

.DESCRIPTION
    Runs in the background. When the SuperWhisper shortcut is pressed while an empty
    message box of a supported app is focused, it waits for the dictated text to appear,
    waits until the text stops changing, and presses Enter once.

    The shortcuts are read from SuperWhisper's own settings
    (%LOCALAPPDATA%\com.superwhisper.app\preferences.json) and followed live.
    Optional overrides live in config.json next to this script.

    Privacy: a keyboard hook is used only to know whether the shortcut keys are held.
    No keys and no message text are logged or stored; there are no network calls.

.PARAMETER Check
    Prints the detected shortcuts, the Auto Paste state and the supported apps, then exits.
#>
param(
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

$configPath = Join-Path $PSScriptRoot 'config.json'
$superWhisperDir = Join-Path $env:LOCALAPPDATA 'com.superwhisper.app'
$preferencesPath = Join-Path $superWhisperDir 'preferences.json'
$logPath = Join-Path $env:TEMP 'superwhisper-autosend.log'
$defaultApps = @('claude', 'ChatGPT', 'Codex')

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class AutosendKeys
{
    private delegate IntPtr KeyboardHook(int code, IntPtr message, IntPtr data);

    private static readonly KeyboardHook callback = OnKey;
    private static readonly bool[] down = new bool[256];
    private static IntPtr hook;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int type, KeyboardHook callback, IntPtr module, uint thread);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
    private static extern IntPtr GetModuleHandle(string name);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);

    [DllImport("user32.dll")]
    private static extern int GetMessage(out Msg message, IntPtr window, uint min, uint max);

    [StructLayout(LayoutKind.Sequential)]
    private struct Msg
    {
        public IntPtr Window;
        public uint Message;
        public IntPtr WParam;
        public IntPtr LParam;
        public uint Time;
        public int X;
        public int Y;
    }

    // The hook runs on its own thread with its own message loop. Windows silently removes a
    // low-level hook whose thread does not answer in time, and the main loop can block for a
    // while in UI Automation calls, so the hook must not share that thread.
    public static void Install()
    {
        int error = 0;
        var ready = new System.Threading.ManualResetEvent(false);
        var thread = new System.Threading.Thread(() =>
        {
            hook = SetWindowsHookEx(13, callback, GetModuleHandle(null), 0);
            if (hook == IntPtr.Zero)
            {
                error = Marshal.GetLastWin32Error();
            }
            ready.Set();
            if (hook == IntPtr.Zero)
            {
                return;
            }
            Msg message;
            while (GetMessage(out message, IntPtr.Zero, 0, 0) > 0)
            {
            }
        });
        thread.IsBackground = true;
        thread.Start();
        ready.WaitOne();
        if (hook == IntPtr.Zero)
        {
            throw new System.ComponentModel.Win32Exception(error);
        }
    }

    public static bool IsDown(int key)
    {
        return key >= 0 && key < 256 && down[key];
    }

    public static void SendEnter()
    {
        keybd_event(0x0D, 0, 0, UIntPtr.Zero);
        keybd_event(0x0D, 0, 2, UIntPtr.Zero);
    }

    // Only remembers whether each physical key is currently held; nothing is recorded.
    private static IntPtr OnKey(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0 && (Marshal.ReadInt32(data, 8) & 0x10) == 0)
        {
            int key = Marshal.ReadInt32(data);
            int kind = message.ToInt32();
            if (key >= 0 && key < 256)
            {
                down[key] = kind == 0x100 || kind == 0x104;
            }
        }
        return CallNextHookEx(hook, code, message, data);
    }
}
"@

# ---------------------------------------------------------------- shortcuts

$modifierKeys = [ordered]@{
    Control = @(0xA2, 0xA3)
    Shift   = @(0xA0, 0xA1)
    Alt     = @(0xA4, 0xA5)
    Win     = @(0x5B, 0x5C)
}
$keyAliases = @{ Ctrl = 'Control'; Option = 'Alt'; Meta = 'Win'; Super = 'Win'; Command = 'Win'; Cmd = 'Win' }
$namedKeys = @{
    Space = 0x20; Enter = 0x0D; Tab = 0x09; Escape = 0x1B; Esc = 0x1B; Backspace = 0x08
    Insert = 0x2D; Delete = 0x2E; Home = 0x24; End = 0x23; PageUp = 0x21; PageDown = 0x22
    ArrowLeft = 0x25; ArrowUp = 0x26; ArrowRight = 0x27; ArrowDown = 0x28
    CapsLock = 0x14; Pause = 0x13; ScrollLock = 0x91
    Backquote = 0xC0; Minus = 0xBD; Equal = 0xBB; BracketLeft = 0xDB; BracketRight = 0xDD
    Backslash = 0xDC; Semicolon = 0xBA; Quote = 0xDE; Comma = 0xBC; Period = 0xBE; Slash = 0xBF
    ControlLeft = 0xA2; ControlRight = 0xA3; ShiftLeft = 0xA0; ShiftRight = 0xA1
    AltLeft = 0xA4; AltRight = 0xA5; MetaLeft = 0x5B; MetaRight = 0x5C
}

# Returns the virtual-key codes for one shortcut part; any of them counts as pressed.
function ConvertTo-KeyGroup([string]$token)
{
    $name = $token.Trim()
    if ($keyAliases.ContainsKey($name)) { $name = $keyAliases[$name] }
    if ($modifierKeys.Contains($name)) { return , $modifierKeys[$name] }
    if ($namedKeys.ContainsKey($name)) { return , @($namedKeys[$name]) }
    if ($name -match '^(?:Key)?([A-Za-z])$') { return , @([int][char]$Matches[1].ToUpper()) }
    if ($name -match '^(?:Digit)?([0-9])$') { return , @(0x30 + [int]$Matches[1]) }
    if ($name -match '^Numpad([0-9])$') { return , @(0x60 + [int]$Matches[1]) }
    if ($name -match '^F([1-9]|1[0-9]|2[0-4])$') { return , @(0x6F + [int]$Matches[1]) }
    throw "Unsupported key '$token'."
}

# Parses SuperWhisper's shortcut format, e.g. "Control+Space" or "Control+Shift+KeyM".
function New-Shortcut([string]$text, [string]$mode)
{
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $groups = @()
    foreach ($token in $text.Split('+'))
    {
        $groups += , (ConvertTo-KeyGroup $token)
    }
    $used = @()
    foreach ($modifier in $modifierKeys.Keys)
    {
        foreach ($group in $groups)
        {
            if (@($group | Where-Object { $modifierKeys[$modifier] -contains $_ }).Count -gt 0) { $used += $modifier }
        }
    }
    $shortcut = [pscustomobject]@{ Text = $text; Mode = $mode; Groups = $groups; UsedModifiers = $used; WasHeld = $false }
    $shortcut.WasHeld = Test-Held $shortcut
    return $shortcut
}

function Test-GroupDown($group)
{
    foreach ($key in $group)
    {
        if ([AutosendKeys]::IsDown($key)) { return $true }
    }
    return $false
}

# Exact match: every part is held and no extra modifier is held.
function Test-Held($shortcut)
{
    foreach ($group in $shortcut.Groups)
    {
        if (-not (Test-GroupDown $group)) { return $false }
    }
    foreach ($modifier in $modifierKeys.Keys)
    {
        if ($shortcut.UsedModifiers -notcontains $modifier -and (Test-GroupDown $modifierKeys[$modifier])) { return $false }
    }
    return $true
}

function Test-AnyDown($shortcut)
{
    foreach ($group in $shortcut.Groups)
    {
        if (Test-GroupDown $group) { return $true }
    }
    return $false
}

function Test-AnyModifierDown
{
    foreach ($modifier in $modifierKeys.Keys)
    {
        if (Test-GroupDown $modifierKeys[$modifier]) { return $true }
    }
    return $false
}

# ---------------------------------------------------------------- settings

function Read-JsonFile([string]$path)
{
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-Setting($config, $preferences, [string]$name, $default)
{
    if ($null -ne $config -and $config.PSObject.Properties.Name -contains $name) { return $config.$name }
    if ($null -ne $preferences -and $preferences.PSObject.Properties.Name -contains $name) { return $preferences.$name }
    return $default
}

function Get-FileStamp([string]$path)
{
    if (Test-Path -LiteralPath $path) { return (Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks }
    return 0
}

function New-SafeShortcut([string]$text, [string]$mode)
{
    try
    {
        return New-Shortcut $text $mode
    }
    catch
    {
        $message = "Shortcut '$text' ignored: $($_.Exception.Message)"
        if ($Check) { Write-Host $message } else { Trace $message }
        return $null
    }
}

function Update-Settings([switch]$Force)
{
    $stamp = "$(Get-FileStamp $preferencesPath)/$(Get-FileStamp $configPath)"
    if (-not $Force -and $stamp -eq $script:settingsStamp) { return }

    $config = Read-JsonFile $configPath
    $preferences = Read-JsonFile $preferencesPath
    $shortcuts = @()
    $push = New-SafeShortcut (Get-Setting $config $preferences 'pushToTalkShortcut' '') 'hold'
    if ($null -ne $push) { $shortcuts += $push }
    $toggle = New-SafeShortcut (Get-Setting $config $preferences 'toggleRecordingShortcut' '') 'toggle'
    if ($null -ne $toggle) { $shortcuts += $toggle }

    $script:shortcuts = $shortcuts
    $script:cancelShortcut = New-SafeShortcut (Get-Setting $config $preferences 'cancelRecordingShortcut' 'Escape') 'cancel'
    $script:apps = @(Get-Setting $config $null 'apps' $defaultApps)
    $script:timeoutSeconds = [double](Get-Setting $config $null 'timeoutSeconds' 30)
    $script:stableMilliseconds = [double](Get-Setting $config $null 'stableMilliseconds' 600)
    $script:settingsStamp = $stamp
    Trace ("Shortcuts: " + (($shortcuts | ForEach-Object { "$($_.Text) ($($_.Mode))" }) -join ', '))
}

# ---------------------------------------------------------------- message box

$processNames = @{}

function Get-ProcessName([int]$id)
{
    if (-not $processNames.ContainsKey($id))
    {
        $processNames[$id] = (Get-Process -Id $id -ErrorAction SilentlyContinue).ProcessName
    }
    return $processNames[$id]
}

# The message boxes of Claude and ChatGPT/Codex are ProseMirror editors.
function Test-Composer($element)
{
    $info = $element.Current
    if ($info.ControlType -ne [Windows.Automation.ControlType]::Edit) { return $false }
    if ($info.ClassName -notmatch '(?:^|\s)ProseMirror(?:\s|$)') { return $false }
    return $script:apps -contains (Get-ProcessName $info.ProcessId)
}

function Get-Composer
{
    try
    {
        $element = [Windows.Automation.AutomationElement]::FocusedElement
        if ($null -ne $element -and (Test-Composer $element)) { return $element }
    }
    catch
    {
    }
    return $null
}

# Returns the message text; a placeholder reported as text counts as empty.
function Get-ComposerText($element)
{
    $pattern = $null
    if ($element.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern, [ref]$pattern))
    {
        $value = $pattern.Current.Value
    }
    elseif ($element.TryGetCurrentPattern([Windows.Automation.TextPattern]::Pattern, [ref]$pattern))
    {
        $value = $pattern.DocumentRange.GetText(-1)
    }
    else
    {
        throw 'Message text is temporarily unavailable.'
    }
    $text = "$value".Trim()
    if ($text -ceq $element.Current.Name) { return '' }
    if ($element.Current.HelpText -and $text -ceq $element.Current.HelpText) { return '' }
    return $text
}

# ---------------------------------------------------------------- logging

function Trace([string]$message)
{
    if ($Check) { return }
    Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') $message"
}

# ---------------------------------------------------------------- check mode

if ($Check)
{
    if (-not (Test-Path -LiteralPath $preferencesPath))
    {
        Write-Output "SuperWhisper settings not found ($preferencesPath). Is SuperWhisper installed and opened once?"
    }
    Update-Settings -Force
    if ($script:shortcuts.Count -eq 0) { Write-Output 'Shortcuts: NONE - set a shortcut in SuperWhisper.' }
    foreach ($shortcut in $script:shortcuts) { Write-Output "Shortcut: $($shortcut.Text) ($($shortcut.Mode))" }

    $preferences = Read-JsonFile $preferencesPath
    if ($null -ne $preferences)
    {
        Write-Output "SuperWhisper Auto Paste: $($preferences.autoPasteEnabled)"
    }

    foreach ($app in $script:apps)
    {
        $process = Get-Process $app -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
        if ($null -eq $process)
        {
            Write-Output "${app}: not running."
            continue
        }
        $root = [Windows.Automation.AutomationElement]::FromHandle($process.MainWindowHandle)
        $condition = [Windows.Automation.PropertyCondition]::new(
            [Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Edit)
        $field = $root.FindAll([Windows.Automation.TreeScope]::Descendants, $condition) |
            Where-Object { $_.Current.ProcessId -eq $process.Id -and (Test-Composer $_) } | Select-Object -First 1
        if ($null -eq $field)
        {
            Write-Output "${app}: running, message box not visible (open a chat to test)."
        }
        else
        {
            Write-Output "${app}: message box found, empty: $((Get-ComposerText $field) -eq '')"
        }
    }
    return
}

# ---------------------------------------------------------------- main loop

$mutex = New-Object System.Threading.Mutex($false, 'Local\SuperWhisperAutosend')
if (-not $mutex.WaitOne(0))
{
    Write-Output 'SuperWhisper Autosend is already running.'
    return
}

if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -gt 512KB)
{
    Remove-Item -LiteralPath $logPath -Force
}

[AutosendKeys]::Install()
Trace 'Started'
Update-Settings -Force
Write-Host 'SuperWhisper Autosend is running. Close this window to stop.'

$state = 'idle'
$armedShortcut = $null
$cancelWasHeld = $false
$recentField = $null
$recentTime = [DateTime]::MinValue
$nextSettingsCheck = [DateTime]::UtcNow

while ($true)
{
    [Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 15
    $now = [DateTime]::UtcNow

    try
    {
        if ($now -ge $nextSettingsCheck)
        {
            $nextSettingsCheck = $now.AddSeconds(2)
            try { Update-Settings } catch { Trace "Settings not read: $($_.Exception.Message)" }
        }

        $pressed = $null
        $anyDown = $false
        foreach ($shortcut in $script:shortcuts)
        {
            $held = Test-Held $shortcut
            if ($held -and -not $shortcut.WasHeld) { $pressed = $shortcut }
            $shortcut.WasHeld = $held
            if (Test-AnyDown $shortcut) { $anyDown = $true }
        }
        $cancelHeld = $null -ne $script:cancelShortcut -and (Test-Held $script:cancelShortcut)
        $cancelPressed = $cancelHeld -and -not $cancelWasHeld
        $cancelWasHeld = $cancelHeld

        # Remember the last focused empty message box: the shortcut can move focus briefly.
        if ($state -eq 'idle' -and -not $anyDown)
        {
            $field = Get-Composer
            if ($null -ne $field -and (Get-ComposerText $field) -eq '')
            {
                $recentField = $field
                $recentWindow = [AutosendKeys]::GetForegroundWindow()
                $recentTime = $now
            }
        }

        if ($cancelPressed -and $state -ne 'idle')
        {
            Trace 'Cancelled'
            $state = 'idle'
        }
        elseif ($null -ne $pressed)
        {
            if ($state -eq 'recording' -and $armedShortcut.Mode -eq 'toggle' -and $pressed -eq $armedShortcut)
            {
                $state = 'waiting'
            }
            else
            {
                Trace "Shortcut pressed ($($pressed.Mode))"
                $state = 'idle'
                $targetField = Get-Composer
                $targetWindow = [AutosendKeys]::GetForegroundWindow()
                $isEmpty = $null -ne $targetField -and (Get-ComposerText $targetField) -eq ''
                if ($null -eq $targetField -and $null -ne $recentField -and ($now - $recentTime).TotalSeconds -lt 2)
                {
                    $targetField = $recentField
                    $targetWindow = $recentWindow
                    $isEmpty = $true
                }
                if ($isEmpty)
                {
                    Trace 'Armed'
                    $state = 'recording'
                    $armedShortcut = $pressed
                    $recordingDeadline = $now.AddMinutes(15)
                }
            }
        }

        if ($state -eq 'recording')
        {
            if ($armedShortcut.Mode -eq 'hold' -and -not (Test-AnyDown $armedShortcut))
            {
                $state = 'waiting'
            }
            elseif ($now -gt $recordingDeadline)
            {
                Trace 'Recording timed out'
                $state = 'idle'
            }
        }

        if ($state -eq 'waiting' -and $null -eq $waitDeadline)
        {
            Trace 'Waiting for text'
            $waitDeadline = $now.AddSeconds($script:timeoutSeconds)
            $lastText = $null
            $stableSince = $now
            $baseline = ''
            if ($armedShortcut.Mode -eq 'toggle')
            {
                try { $baseline = Get-ComposerText $targetField } catch { $baseline = '' }
            }
        }

        if ($state -eq 'waiting')
        {
            $current = Get-Composer
            if ($now -gt $waitDeadline)
            {
                Trace 'Timed out'
                $state = 'idle'
            }
            elseif ([AutosendKeys]::GetForegroundWindow() -eq $targetWindow -and
                $null -ne $current -and $current.Equals($targetField))
            {
                $text = Get-ComposerText $current
                if ($text -cne $lastText)
                {
                    if ($text -and -not $lastText) { Trace 'Text appeared' }
                    $lastText = $text
                    $stableSince = $now
                }
                if ($text -and $text -cne $baseline -and -not (Test-AnyModifierDown) -and
                    ($now - $stableSince).TotalMilliseconds -ge $script:stableMilliseconds)
                {
                    $state = 'idle'
                    if ($current.Equals((Get-Composer)))
                    {
                        Trace 'Sending Enter'
                        [AutosendKeys]::SendEnter()
                    }
                }
            }
        }

        if ($state -ne 'waiting')
        {
            $waitDeadline = $null
        }
    }
    catch
    {
        Trace ("Error at line " + $_.InvocationInfo.ScriptLineNumber + ": " + $_.Exception.GetBaseException().GetType().Name)
    }
}
