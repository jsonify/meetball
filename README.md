# Meetball

A native SwiftUI macOS Google Calendar app with a menu-bar countdown and "Meeting Guardian" alerts.
Independent implementation; written from observed behavior and public APIs, not from another app's source.

## Features
- Google sign-in (OAuth 2.0 PKCE, loopback redirect), multiple accounts, tokens in Keychain
- Apple Calendar (EventKit) source, read-only: shows calendars already configured in the macOS Calendar app (Exchange, iCloud, …)
  with no OAuth, so it works when an org admin blocks Google sign-in. Enable via the connect screen or Settings › Accounts.
  Meet/Zoom/Teams/Webex join links are detected from the event URL, location and notes. Feeds the menu bar and Meeting Guardian.
- Day / Week / Month views (⌘1/⌘2/⌘3, remembered): time grid with hour gutter, now-line, overlap column packing,
  all-day row, drag to create, auto-scroll to now/working hours; keyboard ←/→ prev/next, T today, J/K next/previous day
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
Requires Xcode 16+ and XcodeGen.
SK1Kit (0.4.0 or later) is a Swift package dependency (`packages:` in `project.yml`); Xcode resolves it on first build. To work on
SK1Kit alongside Meetball, point `project.yml` at a local checkout (`path: ../SK1Kit`) and regenerate.
```
xcodegen generate
xcodebuild -project Meetball.xcodeproj -scheme Meetball build
xcodebuild -project Meetball.xcodeproj -scheme MeetballTests test   # or ⌘U in Xcode
```
### CI
`.github/workflows/ci.yml` builds the app and runs `MeetballTests` on a macOS runner (newest Xcode, signed ad hoc, no
secrets) on every push and pull request, and runs `Scripts/sk1-audit.sh` on Linux. The build and test logs and the
`.xcresult` are uploaded as the `meetball-ci-logs` artifact.

### SK-1 look
`Scripts/sk1-audit.sh Meetball` lists anything still drawn natively (it should report nothing; a native control kept on
purpose ends its line with `// sk1-audit: ignore (reason)`). `.claude/skills/adopt-sk1kit` is SK1Kit's adoption skill
for Claude Code sessions. Both come from SK1Kit: refresh them with its `Scripts/install-adoption-kit.sh <this repo>`.

## Configuration (use your own credentials)
Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` (gitignored; never commit it) and set `GOOGLE_CLIENT_ID` (a Google Cloud "Desktop app" OAuth client, Calendar API enabled),
optional `GOOGLE_CLIENT_SECRET`, and `PRO_PRODUCT_IDS` (comma-separated App Store product IDs).
Pro is unlocked by default for personal builds (`PRO_UNLOCKED: "YES"` in `project.yml`; set to `NO` to enforce StoreKit). Also `MEETBALL_FORCE_PRO=1` in the scheme environment to test Pro features without StoreKit.

## Known gaps vs. the original
Not recovered (no decompiler was used): exact alert timings/copy, Supabase push-sync backend (this app polls Google directly),
RevenueCat/Mixpanel telemetry, App Attest. Screen-share detection is a heuristic.
