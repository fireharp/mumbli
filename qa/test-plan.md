# Mumbli Test Plan

## Overview

This document defines how each user story is tested, organized by test type.
See `user-stories.md` for full acceptance criteria.
See `manual-tests.md` for step-by-step manual test procedures.

---

## 1. UI Tests (XCUITest — Automatable)

These tests use Xcode's UI testing framework via accessibility identifiers.

| Test ID | Story | What to Test | How |
|---------|-------|-------------|-----|
| UI-01 | US-8 | Menu bar icon is visible | Launch app, query for NSStatusItem accessibility element |
| UI-02 | US-8 | Menu bar dropdown shows history, settings, quit | Click menu bar icon, verify menu items exist |
| UI-03 | US-7 | History list shows entries | Pre-populate history, open menu, verify entries are displayed |
| UI-04 | US-7 | History entry shows preview + timestamp | Check entry content format in menu |
| UI-05 | US-7 | Click history entry copies to clipboard | Click entry, verify pasteboard content |
| UI-06 | US-7 | History is scrollable, most recent first | Add multiple entries, verify ordering |
| UI-07 | US-9 | Overlay appears during dictation | Simulate dictation start, verify overlay window exists |
| UI-08 | US-9 | Overlay shows listening indicator | Check for waveform/pulsing dot element |
| UI-09 | US-9 | Overlay dismisses after finalization | Simulate dictation end, verify overlay gone |
| UI-10 | US-10 | First launch shows permission prompts | Fresh install, verify permission dialogs appear |
| UI-11 | US-8 | No Dock icon visible | Verify LSUIElement behavior — app not in Dock |
| UI-12 | US-8 | Settings accessible from menu | Click settings in menu, verify settings view appears |
| UI-13 | US-7 | Copy feedback shown on history click | Click entry, verify checkmark/highlight feedback |

---

## 2. Integration Tests

These test the interaction between the macOS app and backend services.

| Test ID | Story | What to Test | How |
|---------|-------|-------------|-----|
| INT-01 | US-16 | WebSocket connects to /ws/transcribe | Start dictation, verify WS connection opened |
| INT-02 | US-16 | Auth token sent as first frame | Capture first text frame, verify auth payload |
| INT-03 | US-16 | Audio chunks sent as binary frames | Monitor WS traffic during dictation |
| INT-04 | US-16 | "start" and "stop" frames sent | Verify text frames at session start/end |
| INT-05 | US-16 | Server responds with "listening" | Verify server acknowledgment after start |
| INT-06 | US-16 | Server responds with "final" text | Verify polished text received after stop |
| INT-07 | US-16 | Server responds with "error" on failure | Simulate backend error, verify error frame |
| INT-08 | US-13 | Network failure handled gracefully | Drop network mid-dictation, verify recovery or error |
| INT-09 | US-5 | Filler words removed by polishing | Send audio with fillers, verify cleaned output |
| INT-10 | US-5 | Self-corrections resolved | Send "at 4, actually 3", verify "at 3" output |
| INT-11 | US-11 | Multi-language detection | Send non-English audio, verify correct transcription |
| INT-12 | US-7 | History persists across restart | Add entries, restart app, verify entries remain |

---

## 3. Manual Tests (Require Real Hardware)

These require a real Mac with microphone, accessibility permissions, and target apps installed.
Full step-by-step procedures are in `manual-tests.md`.

| Test ID | Story | What to Test |
|---------|-------|-------------|
| MAN-01 | US-1 | Fn hold mode with actual speech |
| MAN-02 | US-2 | Fn double-tap hands-free mode |
| MAN-03 | US-3 | Text injection into Safari |
| MAN-04 | US-3 | Text injection into Notes |
| MAN-05 | US-3 | Text injection into Slack |
| MAN-06 | US-3 | Text injection into VS Code |
| MAN-07 | US-3 | Text injection into Terminal |
| MAN-08 | US-3 | Text injection into Chrome |
| MAN-09 | US-3 | Text injection into Mail |
| MAN-10 | US-4 | Extended dictation session (5+ minutes) |
| MAN-11 | US-6 | Quick reply in messaging app |
| MAN-12 | US-12 | Microphone permission denied |
| MAN-13 | US-12 | Microphone disconnected mid-dictation |
| MAN-14 | US-14 | Dictation with no text field focused |
| MAN-15 | US-15 | Switch apps during dictation |
| MAN-16 | US-10 | First launch permission flow |
| MAN-17 | US-9 | Overlay position near cursor in various apps |
| MAN-18 | US-5 | Long stream-of-consciousness dictation |

---

## 4. Acceptance Criteria Matrix

Summary mapping stories to test coverage:

| Story | UI Tests | Integration Tests | Manual Tests | Status |
|-------|----------|------------------|--------------|--------|
| US-1 Hold mode | - | - | MAN-01 | Pending |
| US-2 Hands-free mode | - | - | MAN-02 | Pending |
| US-3 Universal text input | - | - | MAN-03 to MAN-09 | Pending |
| US-4 Accessibility | - | - | MAN-10 | Pending |
| US-5 Thinking out loud | - | INT-09, INT-10 | MAN-18 | Pending |
| US-6 Quick replies | - | - | MAN-11 | Pending |
| US-7 History | UI-03 to UI-06, UI-13 | INT-12 | - | Pending |
| US-8 Menu bar | UI-01, UI-02, UI-11, UI-12 | - | - | Pending |
| US-9 Overlay | UI-07 to UI-09 | - | MAN-17 | Pending |
| US-10 First launch | UI-10 | - | MAN-16 | Pending |
| US-11 Multi-language | - | INT-11 | - | Pending |
| US-12 No microphone | - | - | MAN-12, MAN-13 | Pending |
| US-13 No network | - | INT-08 | - | Pending |
| US-14 No text field | - | - | MAN-14 | Pending |
| US-15 Focus loss | - | - | MAN-15 | Pending |
| US-16 WebSocket | - | INT-01 to INT-07 | - | Pending |
