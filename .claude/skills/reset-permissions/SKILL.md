---
name: reset-permissions
description: Reset macOS TCC accessibility permissions for Mumbli after a rebuild or reinstall. Use when dictation works but text injection fails, CGEvent tap fails, or the user says "reset permissions".
user_invocable: true
---

# Reset Mumbli Accessibility Permissions

After rebuilding or reinstalling Mumbli, the macOS TCC database may have a stale code signature hash. This causes silent failures: the Accessibility toggle shows ON but the app can't read focused elements or post key events.

## Step 1: Confirm the problem

Check the log for permission errors:
```bash
tail -20 ~/Library/Application\ Support/Mumbli/mumbli.log
```

Look for:
- `CGEvent tap failed` — permissions broken
- `No focused element (error: -25211)` — TCC csreq mismatch
- `CGPreflightListenEventAccess() returned false` — not trusted

If the log shows `CGEvent tap created successfully`, permissions are fine — the issue is elsewhere.

## Step 2: Reset TCC

```bash
tccutil reset Accessibility com.mumbli.app
```

## Step 3: Quit Mumbli

```bash
osascript -e 'tell application "Mumbli" to quit' 2>/dev/null
pkill -f "Mumbli.app/Contents/MacOS/Mumbli" 2>/dev/null
sleep 2
```

## Step 4: Relaunch

For the installed app:
```bash
open /Applications/Mumbli.app
```

For a debug build:
```bash
~/Library/Developer/Xcode/DerivedData/MumbliApp-*/Build/Products/Debug/Mumbli.app/Contents/MacOS/Mumbli &>/dev/null &disown
```

The app should prompt for Accessibility permission. Tell the user to grant it.

## Step 5: Verify

Wait a few seconds, then check:
```bash
sleep 3
tail -10 ~/Library/Application\ Support/Mumbli/mumbli.log
```

Confirm:
- `CGPreflightListenEventAccess() OK`
- `CGEvent tap created successfully`

If it still shows `CGEvent tap failed`, the user needs to manually add the app in System Settings > Privacy & Security > Accessibility via the `+` button.

## Why this happens

Ad-hoc signed apps (Xcode builds without a Development Team) get a Designated Requirement based on the exact binary hash (`cdhash`). Every rebuild changes the hash, so macOS silently invalidates the TCC grant even though the toggle still shows ON. The permanent fix is to set a Development Team in Xcode signing settings.
