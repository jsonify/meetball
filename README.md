# Meetball

A native SwiftUI macOS Google Calendar app with a menu-bar countdown and "Meeting Guardian" alerts.
Independent implementation; written from observed behavior and public APIs, not from another app's source.

## Features
- Google sign-in (OAuth 2.0 PKCE, loopback redirect), multiple accounts, tokens in Keychain
- Apple Calendar (EventKit) source, read-only: shows calendars already configured in the macOS Calendar app (Exchange, iCloud, …)
  with no OAuth, so it works when an org admin blocks Google sign-in. Enable via the connect screen or Settings › Accounts.
  Meet/Zoom/Teams/Webex join links are detected from the event URL, location and notes. Feeds the menu bar and Meeting Guardian.
- Month grid with multi-day event bars (lane-packed), per-day list, per-calendar visibility
- Create events (attendees, Google Meet link, focus blocks) and delete events
- Menu-bar extra: next-meeting countdown, upcoming list with Join buttons
- Meeting Guardian: soft notification, heads-up overlay, hard overlay (+sound), timings, "Are you still joining?" prompt,
  Focus break-through (time-sensitive), screen-share suppression (heuristic), quiet hours, sleep/shutdown warning, per-calendar rules
- Pro tier via StoreKit 2 (soft alerts are free; heads-up/hard/per-calendar rules are Pro)
- Launch at login, refresh interval, per-account accent color

## Build
Requires Xcode 16+ and XcodeGen.
```
xcodegen generate
xcodebuild -project Meetball.xcodeproj -scheme Meetball build
xcodebuild -project Meetball.xcodeproj -scheme MeetballTests test   # or ⌘U in Xcode
```
## Configuration (use your own credentials)
Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` (gitignored; never commit it) and set `GOOGLE_CLIENT_ID` (a Google Cloud "Desktop app" OAuth client, Calendar API enabled),
optional `GOOGLE_CLIENT_SECRET`, and `PRO_PRODUCT_IDS` (comma-separated App Store product IDs).
Pro is unlocked by default for personal builds (`PRO_UNLOCKED: "YES"` in `project.yml`; set to `NO` to enforce StoreKit). Also `MEETBALL_FORCE_PRO=1` in the scheme environment to test Pro features without StoreKit.

## Known gaps vs. the original
Not recovered (no decompiler was used): exact alert timings/copy, Supabase push-sync backend (this app polls Google directly),
RevenueCat/Mixpanel telemetry, App Attest. Screen-share detection is a heuristic.
