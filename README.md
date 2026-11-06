# Meetball

A native SwiftUI macOS Google Calendar app with a menu-bar countdown and "Meeting Guardian" alerts.
Independent implementation; written from observed behavior and public APIs, not from another app's source.

## Features
- Google sign-in (OAuth 2.0 PKCE, loopback redirect), multiple accounts, tokens in Keychain
- Apple Calendar (EventKit) source, read-only: shows calendars already configured in the macOS Calendar app (Exchange, iCloud, …)
  with no OAuth, so it works when an org admin blocks Google sign-in. Enable via the connect screen or Settings › Accounts.
  Meet/Zoom/Teams/Webex join links are detected from the event URL, location and notes. Feeds the menu bar and Meeting Guardian.
- Day / Week / Month views (⌘1/⌘2/⌘3, remembered): time grid with hour gutter, now-line, overlap column packing,
  all-day row (meetings that run past midnight stay on the grid, split across both days), drag to create, auto-scroll to now/working hours; keyboard ←/→ prev/next, T today, J/K next/previous day
- Month grid with multi-day event bars (lane-packed), per-day list, per-calendar visibility
- Create events (attendees, Google Meet link, focus blocks) and delete events
- Menu-bar extra: next-meeting countdown, mini month with event dots (click a day to scope the agenda), hero card for the
  next/in-progress meeting, agenda grouped by day with a "now" line, all-day chips, declined events dimmed
- One-click join: global shortcut (default ⌃⌥⌘J, recordable) joins the nearest meeting; Join buttons show the service
  (Meet, Zoom, Teams, Webex) and open the native app (zoommtg://, msteams://) or a chosen browser per service; copy link /
  open in Google Calendar; "Join" action on alert notifications
- Meeting Guardian: soft notification, heads-up overlay, hard overlay (+sound), timings, "Are you still joining?" prompt,
  Focus break-through (time-sensitive), screen-share suppression (heuristic), quiet hours, sleep/shutdown warning, per-calendar rules
- Pro tier via StoreKit 2 (soft alerts are free; heads-up/hard/per-calendar rules are Pro)
- Launch at login, refresh interval, per-account accent color
- SK-1 look via [SK1Kit](https://github.com/jsonify/SK1Kit) 0.4+ (cream/charcoal chassis, sunken trays, raised keys,
  olive LCD), laid out after Skreener: the popover is a launcher (an LCD strip that shows the next meeting or the key
  under the pointer, big Join / Calendar / Refresh tiles, a tray of captioned keys with charcoal Settings and Quit);
  the main window has captioned key trays (View, Go, New) over an LCD display (the meeting on now or next, and the
  meetings left today); Settings use knobs and ◀ chip ▶ pickers; the heads-up card is an SK-1 plate with an LCD
  countdown. The full-screen hard alert keeps its own dark overlay.

## Build
Requires Xcode 16+ and XcodeGen (`brew install xcodegen`). `Meetball.xcodeproj` is generated from `project.yml` and isn't
tracked in git, so run `xcodegen generate` after cloning and whenever you pull or change `project.yml` (`make dist` does it for
you). Add new files on disk and in `project.yml` only; edits made to the project in Xcode are lost on the next generate.
SK1Kit (0.4.0 or later) is a Swift package dependency (`packages:` in `project.yml`); Xcode resolves it on first build. The
resolved version is pinned in `Meetball.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, the one file in
the project folder that is committed: commit it when it changes. To work on
SK1Kit alongside Meetball, point `project.yml` at a local checkout (`path: ../SK1Kit`) and regenerate.
```
xcodegen generate
xcodebuild -project Meetball.xcodeproj -scheme Meetball build
xcodebuild -project Meetball.xcodeproj -scheme MeetballTests test   # or ⌘U in Xcode
```
### Run it without Xcode
`make dist` (or `Scripts/dist.sh`) regenerates the project, does a Release build into `build/`, and copies the app to
`dist/Meetball.app` (both folders are gitignored). Then `open dist/Meetball.app`, or use one of these:

| Command | What it does |
|---|---|
| `make dist` | Build `dist/Meetball.app` |
| `make run` | Build, quit any running Meetball, and open the new build |
| `make install` | Build, copy to `/Applications/Meetball.app`, and open it |
| `make universal` | Build for arm64 + x86_64 (`Scripts/dist.sh --universal`) |
| `make clean` | Delete `build/` and `dist/` |

The app is signed with your Apple Development identity (`-allowProvisioningUpdates`), the same as an Xcode build. If the
build fails, the errors are printed and the full log is at `build/dist.log`.
### CI
`.github/workflows/ci.yml` builds the app and runs `MeetballTests` on a macOS runner (newest Xcode, signed ad hoc, no
secrets) on every push and pull request, and runs `Scripts/sk1-audit.sh` on Linux. The build and test logs and the
`.xcresult` are uploaded as the `meetball-ci-logs` artifact. The `ios` job builds `MeetballPhone` for a device (unsigned) and runs
`MeetballPhoneTests` on the newest iPhone simulator (`meetball-ios-ci-logs`).

### SK-1 look
`Scripts/sk1-audit.sh Meetball` lists anything still drawn natively (it should report nothing; a native control kept on
purpose ends its line with `// sk1-audit: ignore (reason)`). `.claude/skills/adopt-sk1kit` is SK1Kit's adoption skill
for Claude Code sessions. Both come from SK1Kit: refresh them with its `Scripts/install-adoption-kit.sh <this repo>`.

## Meetball for iPhone (MeetballPhone)
A personal iPhone version of Meetball (not for the App Store) with the Mac app's SK-1 look and its fun. It reads the
calendars in the iPhone's Calendar app through EventKit (a work Google calendar added via iCloud included), sharing the
Mac app's calendar client, change detector, layout builders, quick-add parser, countdown LCD, "Starts in" urgency
styling and confetti (the shared files are listed under `MeetballPhone` in `project.yml` and must stay AppKit-free).

- **Today**: the MB-1 display (next meeting, meetings left today), the "Starts in" card that turns orange, glows and
  blinks as the meeting nears, with a big Join key, cards for moved/re-linked/cancelled meetings until you dismiss
  them, and the rest of today and tomorrow.
- **Week**: an LED meeting-load meter for the next seven days (tap a day to show only it) and each day's meetings.
- **Month**: dots per day, trips and on-call stretches as ribbons, and the chosen day's meetings. Swipe to change month.
- **Quick add** (the + key): one line of plain English, read back on an LCD as you type, saved to a calendar you pick. Lengths can be spelled out ("for about three minutes", "an hour and a half").
- **Confetti** when a meeting is cancelled (shown the next time you open Meetball if it was found in the background).
- **Settings**: everything from the notifier below, the theme (System/Light/Dark) and the fun switches.

- **Widgets** (MeetballWidgets extension): the next meeting on an MB-1 LCD for the Home Screen (small, medium) and the
  Lock Screen (rectangular, circular, inline). Tapping joins a meeting that's on or starts within 10 minutes. The app
  saves the next two days to the App Group `group.app.meetball.MeetballPhone` after each refresh; the widgets read that.
- **Live Activity**: in the hour before a meeting, a countdown on the Lock Screen and in the Dynamic Island, counting up
  once it starts, with a Join button. iOS only lets it start while Meetball is open, so open Meetball in that hour;
  background refreshes then keep it right (a moved meeting moves it, a cancelled one ends it). Switch it off in
  Settings › Alerts.

- **Siri, Shortcuts, Action Button**: "Join my meeting in Meetball" opens the meeting that's on or starts within 10
  minutes; "What's my next meeting in Meetball" says it (good in the car). Both are App Shortcuts, so they can go on the
  Action Button (Settings › Action Button › Shortcut › Meetball). A **Join Meeting** control does the same from Control
  Center. They use the meetings Meetball last saved for the widgets.
- **StandBy**: the small widget becomes an MB-1 desk clock counting down to your next meeting.
- **Shake** for the rest of your day: meetings left, hours booked, and your next free stretch (before 6 PM).
- **Countdown moment**: with Meetball open in the last minute before a meeting, a full-screen seven-segment countdown,
  a tick every second for the last ten, a thunk at zero, and the Join key.
- **Pre-flight card**: five minutes before a meeting (with Meetball open), a card with who's in it, the last meeting
  like it in the past 90 days (same series, else same title, else mostly the same people) and your Echo note from then,
  and the invite's links and notes without the dial-in boilerplate. The event screen shows the same "Last time" and
  links, and so does the Mac's event popover.
- **Echo**: when a meeting ends, a banner above the tab bar (for half an hour) and a notification offer one tap to record
  a 20-second voice note. It's transcribed on the iPhone (Speech framework, on-device only), can be fixed up, and is
  saved in Meetball against that meeting (the work calendar is a read-only feed, so nothing is written to it) and, unless
  switched off in Settings, added to Reminders due the next working morning. Notes show on the event screen and in the
  next pre-flight card for that meeting.
- Needs iOS 18 or later.

### Alerts and CarPlay
Meetball reminds you before meetings and tells you when one moves, gets a new link, or is cancelled.

**How alerts reach CarPlay.** Every alert is a Time Sensitive local notification. CarPlay only draws banners for apps
Apple has approved for CarPlay, which a calendar isn't, so in the car Siri *reads* Meetball's alerts (Announce
Notifications) rather than showing them. That works for any app's Time Sensitive notifications.

**What's reliable and what isn't.** Reminders are handed to iOS ahead of time (up to 48 per refresh, 48 hours out), so
they fire on time even when Meetball isn't running. Changes are only noticed when Meetball gets to run: when you open
it, when the Calendar database changes while it's still in memory, and when iOS grants a background app refresh
(requested every 15 minutes; iOS decides, often every 30 min to a few hours, less in Low Power Mode or if you rarely
open the app). So a meeting moved an hour ahead is usually caught; one moved five minutes before it starts may not be,
and the old reminder can still fire. Opening Meetball, or pulling down to refresh, always checks right away.

### Install it on your iPhone
1. On the Mac: `git pull`, `xcodegen generate`, `open Meetball.xcodeproj`.
2. Connect the iPhone with a cable (after the first run it also works over Wi-Fi) and tap **Trust** on the phone.
3. In Xcode pick the **MeetballPhone** scheme and your iPhone as the destination. Under the target's *Signing &
   Capabilities*, the team is already TS339TNM5P with automatic signing; Xcode registers the phone and creates the
   `app.meetball.MeetballPhone` App ID with the Time Sensitive Notifications capability. Do the same for the
   **MeetballWidgets** target (`app.meetball.MeetballPhone.Widgets`); Xcode also registers the App Group
   `group.app.meetball.MeetballPhone` for both. If it says the bundle ID is
   taken, change `PRODUCT_BUNDLE_IDENTIFIER` for `MeetballPhone` in `project.yml` and regenerate.
4. Press ⌘R. The first time, iOS asks you to turn on **Developer Mode** (Settings › Privacy & Security › Developer
   Mode, then restart the phone) and Xcode may need a minute to prepare the device. Run again afterwards.
5. On first launch, allow **Full Access** to calendars and allow notifications.
6. On the iPhone, check:
   - Settings › Notifications › Meetball: Allow, **Time Sensitive Notifications** on, **Announce Notifications** on.
   - Settings › Notifications › Announce Notifications: on, and **CarPlay** on (choose "Announce" rather than "Off").
   - Settings › Focus › Driving › Apps: **Time Sensitive Notifications** on, so Driving Focus lets them through.
   - Settings › General › Background App Refresh: on, and on for Meetball.
7. Tap **Test alert in 10 s**, then lock the phone (or start it just before you get in the car) to hear how it sounds.

With a paid developer account the install lasts a year; reinstall from Xcode after that (or after any update you pull).

## Configuration (use your own credentials)
Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` (gitignored; never commit it) and set `GOOGLE_CLIENT_ID` (a Google Cloud "Desktop app" OAuth client, Calendar API enabled),
optional `GOOGLE_CLIENT_SECRET`, and `PRO_PRODUCT_IDS` (comma-separated App Store product IDs).
Pro is unlocked by default for personal builds (`PRO_UNLOCKED: "YES"` in `project.yml`; set to `NO` to enforce StoreKit). Also `MEETBALL_FORCE_PRO=1` in the scheme environment to test Pro features without StoreKit.

## Known gaps vs. the original
Not recovered (no decompiler was used): exact alert timings/copy, Supabase push-sync backend (this app polls Google directly),
RevenueCat/Mixpanel telemetry, App Attest. Screen-share detection is a heuristic.
