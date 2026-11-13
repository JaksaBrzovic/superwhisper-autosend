# SuperWhisper Autosend

Dictate with [SuperWhisper](https://superwhisper.com) and your message is **sent automatically** in the
**Claude desktop app** and the **ChatGPT / Codex desktop app** on Windows. No more pressing Enter.

Hold your SuperWhisper shortcut in an empty message box, speak, release. SuperWhisper pastes the text
and Autosend presses Enter for you.

## Install in one step

Paste this into an AI agent that can run commands on your PC (Claude Code, the Code tab of the
Claude desktop app, or Codex):

```text
Install https://github.com/JaksaBrzovic/superwhisper-autosend
```

The agent reads the instructions below, asks you one or two short questions, and sets everything up.

**You need:** Windows 10/11 and SuperWhisper installed and opened at least once.

## Use

1. Click into the **empty** message box in Claude or ChatGPT/Codex.
2. Dictate with your SuperWhisper shortcut as usual (hold-to-talk or toggle).
3. The message is sent as soon as the text is pasted.

Press **Escape** (SuperWhisper's cancel shortcut) to cancel. If the message box already had text in it,
nothing is sent automatically, so you can still dictate into a draft.

## What it does and does not do

- Runs in the background as a small PowerShell script, for your Windows user only. No admin rights.
- Reads your shortcuts from SuperWhisper's settings and follows changes automatically.
- Uses a keyboard hook **only** to know whether your shortcut keys are held. It does not record,
  log or store keys or message text, and it makes **no network connections**.
- Presses Enter only in the Claude and ChatGPT/Codex desktop apps, only after you used the shortcut
  in an empty message box, and only within 30 seconds after recording stops.
- Writes a small status log (no keys, no text) to `%TEMP%\superwhisper-autosend.log`.

Antivirus software may warn about the keyboard hook. That is expected for this kind of tool; the full
source is in this repository.

## Uninstall

Ask your agent to "uninstall SuperWhisper Autosend", or run in PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\SuperWhisperAutosend\uninstall.ps1"
```

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
  "timeoutSeconds": 30,
  "stableMilliseconds": 600
}
```

---

## Instructions for AI agents

You are installing SuperWhisper Autosend for the user on **Windows**. Keep it short and friendly, talk
in the user's language, and do not ask more than needed. All commands are **Windows PowerShell**; if
your shell is bash, run each through `powershell -NoProfile -Command "..."`. No admin rights are needed.
You may read the scripts first; they are short.

### 1. Download (pinned version)

```powershell
$version = '1.0.0'
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

- `superWhisperInstalled: false` → tell the user to install SuperWhisper from https://superwhisper.com,
  open it once, and come back. Stop here.
- `pushToTalkShortcut` / `toggleRecordingShortcut` are the user's SuperWhisper shortcuts
  (format `Control+Space`, `Control+Shift+KeyM`; empty means not set).
- `autoPasteEffective: false` → SuperWhisper's Auto Paste is off; Autosend needs it on.

### 3. Ask the user (one message)

Ask both in one short message:

1. **Shortcut:** "SuperWhisper uses `<shortcut>` to dictate. Is that the shortcut you use?"
   If neither shortcut is set, ask which shortcut they use for SuperWhisper.
2. **Auto Paste** (only if `autoPasteEffective` is false): "Autosend needs SuperWhisper's Auto Paste
   turned on. May I turn it on? SuperWhisper will restart for a moment."

### 4. Install

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\install.ps1" -EnableAutoPaste
```

- Leave out `-EnableAutoPaste` if the user said no (then tell them to turn on Auto Paste in SuperWhisper
  settings themselves, otherwise nothing will be sent).
- Only if the user uses a **different** shortcut than SuperWhisper reports, add
  `-PushToTalkShortcut "Control+Alt+Space"` (hold to talk) or `-ToggleRecordingShortcut "..."` (press to
  start, press to stop), using the same format.
- Add `-NoStartup` only if the user does not want it to start with Windows.

The installer copies the files to `%LOCALAPPDATA%\SuperWhisperAutosend`, stops any older copy, starts it
hidden, adds it to Windows sign-in (Startup folder) and prints a check. Success looks like
`Running: True` plus `Shortcut: ...` lines. `message box not visible` is fine.

Then remove the download: `Remove-Item $dir -Recurse -Force`.

### 5. Tell the user

In two or three sentences: it is running and starts with Windows; click into an empty message box in
Claude or ChatGPT/Codex, dictate with their shortcut, and the message sends by itself; to uninstall,
ask an agent or run the uninstall command above.

### Rules

- Do not change any other SuperWhisper setting. `-EnableAutoPaste` only flips Auto Paste and saves a
  backup next to each changed file (`*.before-autosend.bak`).
- If something fails, show the error to the user and point to Troubleshooting above.
- To update, repeat the steps with the newer version; the installer replaces the old copy.
