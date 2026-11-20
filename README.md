# ABI Hours

Tracks your hours at work without ever opening the app. Shows up right next to ABI when you search "abi".

- **Clock in/out:** scan your ID at the ABI scanner, then tap your phone to the NFC sticker on the back of your ID. It runs in the background: just a quick "Clocked in for Martin Lawrence · 4:02 PM" banner, no timer on screen. Tap again when you leave.
- **Lunch:** press and hold the Action button (about a second). You get a heads-up 5 minutes before lunch ends and a reminder at 30, both with an **End lunch** button. Press again to end lunch.
- **Schedule:** ⋯ → Paste schedule. Paste the plain-text schedule and every shift gets labeled with that day's event automatically. The main screen goes **week → events → your hours for each event**.

## Build the IPA (GitHub Actions)

1. Create a new private GitHub repo and push this folder to `main`.
2. **Actions → Build IPA** runs automatically (or press *Run workflow*).
3. When it's green, download the **ABIHours-ipa** artifact (a zip containing `ABIHours.ipa`).
4. Sideload it the same way as your other IPAs. The IPA is unsigned; your sideloader signs it.
5. Open the app once (so Shortcuts and the Action button can see its actions) and allow notifications.

## Setup on the phone

**Badge sticker → Clock In/Out**
1. Stick an NFC sticker (NTAG213 or NTAG215) on the back of your ID. Nothing needs to be written to it.
2. Shortcuts → Automation → + → NFC → Scan → hold the top of the phone to the sticker → name it "Work badge".
3. Choose **Run Immediately**, turn off **Notify When Run**.
4. Add action → search **ABI Hours** → **Clock In/Out**.

**Action button → Lunch**
Settings → Action Button → Shortcut → Choose a Shortcut → ABI Hours → **Lunch**.
The Action button always needs a press-and-hold (Apple doesn't allow a single click), but it's about a second, and the action runs right away with no app opening.

The same steps are in the app under ⚙︎ → *Set up the badge sticker & Action button*.

## Schedule format

The parser accepts most plain-text layouts, for example:

```
Thu 11/20 — Martin Lawrence — call 5:00 PM
Sat 11/22
- Reign vs. Gulls 1:00 PM
- Tyler Childers 8:00 PM
**Sunday, November 23**
- Event: Harlem Globetrotters
- Call: 12:30 PM
- Position: Usher
```

Headers ("Week of 11/17"), days off ("OFF") and note lines ("Wear black", "Position: …") are skipped. Pasting days you already loaded replaces them. You see what it found before saving and can rename or remove anything.

## Safety nets

- A second sticker tap within 10 seconds is ignored, so a bump won't clock you back out.
- A shift left open for 16 hours is flagged "Missing clock-out". Tap it to set the real time; your next tap starts a fresh shift.
- Any shift can be edited (times, lunches, which event it belongs to) or added by hand. ⋯ → Export CSV backs everything up.
- Everything is stored on the phone only.

## Repo layout

- `ABIHours/`: SwiftUI app (iOS 17+)
  - `Intents.swift`: the background Clock In/Out and Lunch actions (Shortcuts, Action button, Spotlight)
  - `ClockActions.swift`: what those actions do
  - `ScheduleParser.swift`: reads pasted schedules
  - `ShiftStore.swift`: saved shifts and events, matching shifts to events
- `tools/parser_reference.py`: Python copy of the schedule parser with test cases (`python3 tools/parser_reference.py`). Add a real schedule as a case there if one doesn't read right.
- `project.yml`: XcodeGen project spec
- `.github/workflows/build-ipa.yml`: builds the unsigned IPA
