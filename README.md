# SuperWhisper Autosend

Dictate with [SuperWhisper](https://superwhisper.com) and your message is **sent automatically** in the
**Claude desktop app**, the **ChatGPT / Codex desktop app** and **Claude Code in Windows Terminal**
on Windows. No more pressing Enter.

Hold your SuperWhisper shortcut in an empty message box, speak, release. SuperWhisper pastes the text
and Autosend presses Enter for you.

## Install in one step

Paste this into an AI agent that can run commands on your PC (Claude Code, the Code tab of the
Claude desktop app, or Codex):

```text
Install https://github.com/JaksaBrzovic/superwhisper-autosend
```

The agent reads the instructions below, asks you one or two short questions, and sets everything up.

**You need:** Windows 10/11 and [SuperWhisper](https://superwhisper.com). You can also set up Autosend
first and install SuperWhisper afterwards; Autosend picks it up as soon as SuperWhisper has been opened
once.

The setup also checks whether SuperWhisper starts with Windows and offers to turn that on.

> **Note:** if SuperWhisper is not running during setup, its start with Windows may not work until you
> open SuperWhisper by hand once. Open it after installing to be safe.

## Use

1. Click into the **empty** message box in Claude or ChatGPT/Codex, or into a Windows Terminal tab
   where Claude Code is waiting with an empty prompt.
2. Dictate with your SuperWhisper shortcut as usual (hold-to-talk or toggle).
3. The message is sent as soon as the text is pasted.

Press **Escape** (SuperWhisper's cancel shortcut) to cancel. If the message box already had text in it,
nothing is sent automatically, so you can still dictate into a draft.

## What it does and does not do

- Runs in the background as a small PowerShell script, for your Windows user only. No admin rights.
- Reads your shortcuts from SuperWhisper's settings and follows changes automatically.
- Uses a keyboard hook **only** to know whether your shortcut keys are held. It does not record,
  log or store keys or message text, and it makes **no network connections**.
- Presses Enter only in the Claude and ChatGPT/Codex desktop apps and in Claude Code in Windows
  Terminal, only after you used the shortcut in an empty message box, and only within 30 seconds after recording stops.
- Writes a small status log (no keys, no text) to `%TEMP%\superwhisper-autosend.log`.

Antivirus software may warn about the keyboard hook. That is expected for this kind of tool; the full
source is in this repository.

## Uninstall

Paste this into your agent:

```text
Uninstall https://github.com/JaksaBrzovic/superwhisper-autosend
```

Or run in PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\SuperWhisperAutosend\uninstall.ps1"
```

This stops Autosend and removes it from Windows sign-in, its files, its log and the settings backups
the installer made. SuperWhisper and its settings (including Auto Paste) stay as they are.

## Manual install

Download the [latest release](https://github.com/JaksaBrzovic/superwhisper-autosend/releases/latest)
source ZIP, extract it, and in that folder run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -EnableAutoPaste
```

## Troubleshooting

- Check what Autosend sees:
  `powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\SuperWhisperAutosend\superwhisper-autosend.ps1" -Check`
- See what happened during your last dictation: open `%TEMP%\superwhisper-autosend.log`.
  A working dictation shows `Armed`, `Waiting for text`, `Text appeared`, `Sending Enter`.
- No `Armed`? The message box was not empty or not focused when you pressed the shortcut.
- No `Text appeared`? SuperWhisper's **Auto Paste** is off, or the transcription took longer than 30 seconds.

Optional settings go in `%LOCALAPPDATA%\SuperWhisperAutosend\config.json`
(all keys optional; anything left out follows SuperWhisper):

```json
{
  "pushToTalkShortcut": "Control+Space",
  "toggleRecordingShortcut": "Control+Shift+Space",
  "apps": ["claude", "ChatGPT", "Codex"],
  "terminals": ["WindowsTerminal"],
  "timeoutSeconds": 30,
  "stableMilliseconds": 600
}
```

---

## Instructions for AI agents

You are installing SuperWhisper Autosend for the user on **Windows** (if the user asked to
**uninstall**, skip to [Uninstall](#uninstall-for-agents)). Keep it short and friendly, talk
in the user's language, and do not ask more than needed. All commands are **Windows PowerShell**; if
your shell is bash, run each through `powershell -NoProfile -Command "..."`. No admin rights are needed.
You may read the scripts first; they are short.

### 1. Download (pinned version)

```powershell
$version = '1.0.4'
$dir = Join-Path $env:TEMP "superwhisper-autosend-setup"
Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $dir | Out-Null
Invoke-WebRequest "https://github.com/JaksaBrzovic/superwhisper-autosend/archive/refs/tags/v$version.zip" -OutFile "$dir\src.zip" -UseBasicParsing
Expand-Archive "$dir\src.zip" $dir -Force
$src = Join-Path $dir "superwhisper-autosend-$version"
```

### 2. Detect (changes nothing)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\install.ps1" -Detect
```

It prints JSON. Use it like this:

- `superWhisperInstalled: false` → tell the user: "SuperWhisper is not installed. Autosend only works
  together with it, and you have to install it yourself: https://superwhisper.com. We can still set up
  Autosend now; once you install SuperWhisper and open it, Autosend picks it up automatically, no need
  to run this again." Then ask: **Continue now** / **Stop, I'll install SuperWhisper first**. On
  Continue, skip questions 1, 2 and 3 below (there are no shortcuts or settings to read yet) and go to
  question 4. Leave out `-EnableAutoPaste` and `-EnableSuperWhisperStartup`; in the final message
  remind the user to turn on **Auto Paste** and **Launch at login** in SuperWhisper's settings after
  installing it.
- `superWhisperInstalled: true` but `superWhisperOpenedOnce: false` → ask the user to open SuperWhisper
  once (and finish its setup), then run Detect again.
- `pushToTalkShortcut` / `toggleRecordingShortcut` are the user's SuperWhisper shortcuts
  (format `Control+Space`, `Control+Shift+KeyM`; empty means not set).
- `autoPasteEffective: false` → SuperWhisper's Auto Paste is off; Autosend needs it on.
- `superWhisperStartsAtSignIn: false` → SuperWhisper does not start with Windows, so dictation (and
  Autosend) won't work after a restart until the user opens SuperWhisper by hand.

### 3. Ask the user (short wizard)

Ask these questions in order and wait for the answers before installing. If you have a
multiple-choice question tool, use it with exactly the options listed. Such tools usually add their
own free-text **Other** choice; question 1 relies on it for entering different keys.

1. **Shortcut.** Ask: "Which SuperWhisper shortcut do you use to dictate? If it is a different one,
   choose Other and type it, for example: Ctrl+Alt+Space, hold."
   Write shortcuts in plain words, e.g. "Ctrl+Space (hold to talk)", "Ctrl+Shift+Space (press to
   start/stop)". Options:
   - Two shortcuts detected: **Both (as in SuperWhisper)** / **Only &lt;hold shortcut&gt;** /
     **Only &lt;toggle shortcut&gt;**. "Only ..." installs with the other one disabled
     (`-ToggleRecordingShortcut none` or `-PushToTalkShortcut none`).
   - One shortcut detected: **&lt;that shortcut&gt;** / **Not sure, keep it** (both keep the detected one).
   - **Other (typed by the user):** convert it to the format `Control+Alt+Space` (keys: Control, Shift,
     Alt, Win, Space, letters as `KeyA`, digits as `Digit1`, F1-F24). "Hold" or no mode given means
     `-PushToTalkShortcut`; "press to start/stop" means `-ToggleRecordingShortcut`. Repeat it back once
     in plain words to confirm.
   - No shortcut detected, or no multiple-choice tool: ask the same in a normal chat message
     ("Reply *yes* to keep these, or type your shortcut").
2. **Auto Paste** (only if `autoPasteEffective` is false). "Autosend needs SuperWhisper's Auto Paste
   turned on. May I turn it on? SuperWhisper will restart for a moment."
   Options: **Yes** / **No** / **Back** (Back returns to question 1).
3. **SuperWhisper at sign-in** (only if `superWhisperStartsAtSignIn` is false). "SuperWhisper does not
   start with Windows, so after a restart dictation only works once you open it yourself. Should
   SuperWhisper start automatically when you sign in?"
   Options: **Yes** / **No** / **Back** (Back returns to the previous question).
   If the user says **Yes** and `superWhisperRunning` is false, add: "SuperWhisper is not running right
   now. Please open it once after the setup, otherwise it may not start with Windows until you do."
4. **Start with Windows.** "May I install Autosend now so it runs in the background and starts
   automatically when you sign in to Windows? You can remove it any time."
   Options: **Yes, install** / **Install without auto-start** / **Back** (Back returns to the
   previous question).

### 4. Install

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\install.ps1" -EnableAutoPaste
```

- Leave out `-EnableAutoPaste` if the user said no (then tell them to turn on Auto Paste in SuperWhisper
  settings themselves, otherwise nothing will be sent).
- Add `-EnableSuperWhisperStartup` if the user said yes to question 3 (it turns on SuperWhisper's own
  "Launch at login"; SuperWhisper restarts for a moment).
- Only if the user uses a **different** shortcut than SuperWhisper reports, add
  `-PushToTalkShortcut "Control+Alt+Space"` (hold to talk) or `-ToggleRecordingShortcut "..."` (press to
  start, press to stop), using the same format.
- Add `-NoStartup` only if the user does not want it to start with Windows.

The installer copies the files to `%LOCALAPPDATA%\SuperWhisperAutosend`, stops any older copy, starts it
hidden, adds it to Windows sign-in (a scheduled task for the current user that starts it 20 seconds
after sign-in; the Startup folder if the task cannot be created) and prints a check. Success looks like
`Running: True` plus `Shortcut: ...` lines. `message box not visible` is fine.

Some agent apps are packaged Windows apps (for example the Claude desktop app). Windows gives the
commands they run a private copy of new files under AppData and of user registry entries, invisible to
the rest of Windows. The installer and uninstaller detect this and run themselves again as a normal
process, so you do not need to do anything; this is also why `-Detect` and install can take a few
seconds longer there.

Then remove the download: `Remove-Item $dir -Recurse -Force`.

### 5. Tell the user

In two or three sentences: it is running and starts with Windows; click into an empty message box in
Claude or ChatGPT/Codex, dictate with their shortcut, and the message sends by itself; to uninstall,
ask an agent or run the uninstall command above. If the installer printed `SuperWhisper is not running`,
remind the user to open SuperWhisper once now so it also starts with Windows.

### If your permission system blocks a step

Some agents' safety systems block installing a program that starts with Windows, even after the user
said yes. Do not try to work around a block. Instead give the user the exact command to run themselves,
for example:

> I'm not allowed to set up auto-start myself. Please press **Win + R**, type `powershell`, press Enter,
> paste this line and press Enter:
>
> `powershell -NoProfile -ExecutionPolicy Bypass -File "<full path to install.ps1>" -EnableAutoPaste`

Fill in the real path and the same options you would have used, keep the download folder until the user
has run it, then check the result with `install.ps1 -Detect` (`autosendRunning` and
`autosendStartsAtSignIn` should be `true`) and continue with step 5.

### Uninstall (for agents)

No questions needed; the user already asked for it. Run the installed uninstaller:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\SuperWhisperAutosend\uninstall.ps1"
```

If that file does not exist, download the pinned version as in step 1 and run
`"$src\uninstall.ps1"` instead (it works from any folder), then remove the download.
It prints `SuperWhisper Autosend removed.` Tell the user in one sentence that Autosend is removed and
SuperWhisper itself is unchanged. If your permission system blocks it, give the user the command to run
themselves, as described above.

### Rules

- Do not change any other SuperWhisper setting. `-EnableAutoPaste` only flips Auto Paste and saves a
  backup next to each changed file (`*.before-autosend.bak`).
- If something fails, show the error to the user and point to Troubleshooting above.
- To update, repeat the steps with the newer version; the installer replaces the old copy.
