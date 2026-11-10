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
- Work calendars: mark calendars as work with the briefcase beside them in the sidebar (or right-click › Mark as Work
  Calendar), then flip **Work only** (sidebar switch, the menu bar's Work key, or ⇧⌘O) to show just those everywhere:
  calendar views, menu bar, Upcoming, Meeting Guardian alerts and auto-join
- Auto-join: from a meeting's details, open it automatically shortly after the start if you haven't joined (this one, or
  every one in a recurring series). Settings › Join › Recurring meetings makes every recurring meeting auto-join by
  default; turn a series off from its details
- Create events (attendees, Google Meet link, focus blocks) and delete events
- Menu-bar extra: next-meeting countdown, mini month with event dots (click a day to scope the agenda), hero card for the
  next/in-progress meeting, agenda grouped by day with a "now" line, all-day chips, declined events dimmed
- Overlapping meetings: when another meeting overlaps the one featured (on now or up next), the hero card in the popover,
  the Upcoming card in the main window, and the iPhone's Up next and Today cards list it under the main meeting
  ("Also on now" or "1 overlap") with its own Join key. The menu bar title, the popover's LCD strip and the main window's
  display add a count ("Standup +1 · 20m left") so a clash isn't hidden behind the one meeting they name
- One-click join: global shortcut (default ⌃⌥⌘J, recordable) joins the nearest meeting; Join buttons show the service
  (Meet, Zoom, Teams, Webex) and open the native app (zoommtg://, msteams://) or a chosen browser per service; copy link /
  open in Google Calendar; "Join" action on alert notifications
- Meeting Guardian: soft notification, heads-up overlay, hard overlay (+sound), timings, "Are you still joining?" prompt,
  Focus break-through (time-sensitive), screen-share suppression (heuristic), quiet hours, sleep/shutdown warning, per-calendar rules
- Silence a calendar: set it to **Off** in Settings › Meeting Guardian › Calendars (a family calendar, say). Its events
  stay visible but never alert, including change notifications. To be alerted for one of them anyway, press the bell in the event's popover (or
  **Alert me** under the next meeting); a muted event's bell does the opposite on any other calendar. Works on any plan.
- Pro tier via StoreKit 2 (soft alerts and silencing a calendar are free; heads-up/hard/per-calendar strength rules are Pro)
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
| `make phone` | Build MeetballPhone (Release), install it on your paired iPhone, and open it (`PHONE="name"` picks one when several are reachable) |
| `make universal` | Build for arm64 + x86_64 (`Scripts/dist.sh --universal`) |
| `make clean` | Delete `build/` and `dist/` |

The app is signed with your Apple Development identity (`-allowProvisioningUpdates`), the same as an Xcode build. If the
build fails, the errors are printed and the full log is at `build/dist.log`.
### CI
`.github/workflows/ci.yml` builds the app and runs `MeetballTests` on a macOS runner (newest Xcode, signed ad hoc, no
secrets) on every push and pull request, and runs `Scripts/sk1-audit.sh` on Linux. The build and test logs and the
`.xcresult` are uploaded as the `meetball-ci-logs` artifact. The `ios` job builds `MeetballPhone` for a device (unsigned) and runs
`MeetballPhoneTests` on the newest iPhone simulator (`meetball-ios-ci-logs`).
`.github/workflows/testflight.yml` uploads MeetballPhone to TestFlight (see "TestFlight" under Meetball for iPhone).

### SK-1 look
`Scripts/sk1-audit.sh Meetball` lists anything still drawn natively (it should report nothing; a native control kept on
purpose ends its line with `// sk1-audit: ignore (reason)`). `.claude/skills/adopt-sk1kit` is SK1Kit's adoption skill
for Claude Code sessions. Both come from SK1Kit: refresh them with its `Scripts/install-adoption-kit.sh <this repo>`.

## Meetball for iPhone (MeetballPhone)
A personal iPhone version of Meetball (not for the App Store) with the Mac app's SK-1 look and its fun. It reads the
calendars in the iPhone's Calendar app through EventKit (a work Google calendar added via iCloud included), sharing the
Mac app's calendar client, change detector, layout builders, quick-add parser, countdown LCD, "Starts in" urgency
styling and confetti (the shared files are listed under `MeetballPhone` in `project.yml` and must stay AppKit-free).

- **The dock**: a small rounded plate in the bottom corner, floating over the screen, with the screen key and the
  orange + key. The screen key opens a quick menu of the screens (Today, Day, Week, Month, then Settings); swipe it
  sideways to step to the next or previous screen.
- **Moving between screens**: Day, Week and Month are the same days seen closer or further off, so going between
  them zooms in or out (tap a day on Month and the Day grid grows out of that day). Today comes down over the calendar
  like a lid and lifts off again, and Settings is on the back of the chassis: the screen turns over to reach it. With
  Reduce Motion on, screens cross-fade instead.
- **Today**: the MB-1 display (next meeting, meetings left today), the "Starts in" card that turns orange, glows and
  blinks as the meeting nears, with a big Join key, cards for moved/re-linked/cancelled meetings until you dismiss
  them, and the rest of today and tomorrow.
- **Week**: an LED meeting-load meter for the next seven days (tap a day to show only it) and each day's meetings.
- **Month**: dots per day, trips and on-call stretches as ribbons, and the chosen day's meetings. Swipe to change month.
- **Quick add** (the + key): one line of plain English, read back on an LCD as you type, saved to a calendar you pick. Lengths can be spelled out ("for about three minutes", "an hour and a half").
- **Confetti** when a meeting is cancelled (shown the next time you open Meetball if it was found in the background).
- **Settings**: in sections, picked from a tray of keys under the settings LCD: General (calendar access, can alerts
  reach the car, test alert), Alerts, Events, Calendars, Prep (pre-flight and Echo), Trips, Style (theme, Today tab,
  the fun) and About. The LCD always shows the version and build; About adds the commit, the build time, a Copy key
  and a scrolling What's new change log (`ChangeLog.swift`, shared with the Mac app's About).
- **Event filters** (Settings › Events, or the filter key on Today): the Mac's meeting-first rules (hide declined, all-day, no join link, only you,
  titles with ignored keywords; fade tentative) with per-source overrides (default rules, custom rules or show
  everything), using the same `EventFilter` code. They apply to Today, Up next, alerts, change alerts, the Live
  Activity, widgets and Siri; the Day, Week and Month grids show everything. **Show anyway** on Today lists what was
  hidden, faded, with the reason.

- **Widgets** (MeetballWidgets extension): the MB-1 for the Home Screen (small, medium) and the Lock Screen
  (rectangular, circular, inline). Tapping joins a meeting that's on or starts within 10 minutes. The display shows
  the start time ("TOMORROW AT 8:00 AM") until a meeting is within the hour, then counts down, then counts down to its
  end. The small widget is the LCD itself, glass from edge to edge in a dark bezel: the lamp and caption, the digits as
  big as they fit, the title, the tape (eight hours as half-hour LEDs with an hour scale, lit where there are
  meetings), and a bottom line that counts to a far-off meeting by the second ("IN 9:51:07") beside JOIN when it's
  time, a clash, or when the next one is. The tape starts now while the next meeting is today; otherwise it shows the
  day that meeting is on, from an hour before its first. Medium is the instrument on its chassis with what comes
  later. The Lock Screen rectangle is the same display on a glass plate in one colour, with a twelve-hour tape,
  and it always reads something: with nothing ahead it says all clear and when it last checked, and once what the
  app saved has run out it asks you to open Meetball. The circle rings the digits with twelve LED ticks. The app
  saves the next two days to the App Group `group.app.meetball.MeetballPhone` after each refresh; the widgets read that.
- **Live Activity**: in the hour before a meeting, a countdown on the Lock Screen and in the Dynamic Island, counting up
  once it starts. The Lock Screen card is LCD glass in a dark bezel: the times, the title beside the timer, and two
  bars that fill by themselves (the hour before, then the meeting, with the start marked between), over an orange
  Join key. iOS only lets it start while Meetball is open, so open Meetball in that hour;
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
- **Echo**: when a meeting ends, a banner above the dock (for half an hour) and a notification offer one tap to record
  a 20-second voice note. It's transcribed on the iPhone (Speech framework, on-device only), can be fixed up, and is
  saved in Meetball against that meeting (the work calendar is a read-only feed, so nothing is written to it) and, unless
  switched off in Settings, added to Reminders due the next working morning. Notes show on the event screen and in the
  next pre-flight card for that meeting.
- **Delete**: the event screen's **Delete Event** key asks once (for a repeating meeting: this one only, or every one
  after it) and closes; Meetball doesn't then announce your own delete as a cancellation. Deleting from inside Apple's
  editor (Edit) works too. Shown for calendars the iPhone can change; the read-only work feed is edited in Google Calendar.
- **Trips**: a meeting at a real place (an address or a venue, not a link, a call or a meeting room) gets a
  **Directions** key on the event screen, the Up next card and the Day grid's next-meeting strip. It opens driving
  directions in Google Maps by default (Settings › Trips › Directions in: Google, Apple or Waze; Google Maps and Waze
  open their website when the app isn't installed). A game, match, party or appointment with no place gets
  **Where's this?** instead: it suggests where meetings like it were (same series, or the same title without the
  opponent, so "U12 Soccer vs Eagles" finds "U12 Soccer @ Hawks"), searches Apple's maps as you type, and saves the pick
  to the event's location, with coordinates so Calendar shows its map and travel time (for a repeating event: this one
  only, or every one after it). **Not a trip** stops it asking for that series or title (Settings › Trips › Ask again
  undoes it). On the read-only work feed a pick opens directions but can't be saved. `TravelPlanner` holds the rules.
- **Leave-by times and Leave now alerts**: for trips in the next day, Meetball works out the drive from where you are
  with Apple's directions (MapKit, with the traffic expected when you'd leave; no API key) and shows "Leave by 5:36 ·
  24 min drive" on the Up next card, "leave 5:36" on the Day grid's strip, and the drive on the event screen. At the
  leave-by time a Time Sensitive **Leave now** alert fires (Siri reads it in CarPlay); tapping it, or its Directions
  action, starts the drive in your maps app. Drive times are checked every 10 minutes in the two hours before a trip
  (every 30 before that) whenever Meetball runs, at most six trips at a time. Settings › Trips: Leave-by times, Leave now
  alert, and Time to park (0–15 min added to the drive, 5 by default). Needs location While Using the App (asked the
  first time there's a trip); a background refresh uses the last location iOS has, so open Meetball before you set off
  from somewhere new.
- Needs iOS 18 or later.

### Alerts and CarPlay
Meetball reminds you before meetings and tells you when one moves, gets a new link, or is cancelled.

**Silencing a calendar.** In Settings › Calendars, press a calendar's bell to keep its meetings on screen but drop their
reminders, Echo nudges, Live Activity, countdown moment and pre-flight card (a family calendar, say); the switch beside
it still hides a calendar entirely. Open one of its meetings and turn on **Alert me** to be reminded about just that
one; on any other calendar the same switch turns one meeting's alerts off. A silenced calendar's moved, re-linked and
cancelled meetings don't notify either (they still get a card on Today).

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
Once the phone has been set up below (paired, trusted, Developer Mode on, signed once from Xcode), later builds go on
from the terminal with `make phone` (`Scripts/phone.sh`): it finds the paired iPhone that's reachable by cable or
Wi-Fi, builds, installs and opens Meetball. Keep the phone unlocked. The build log is at `build/phone.log`.

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

### TestFlight (no Mac build needed)
`.github/workflows/testflight.yml` archives MeetballPhone on a GitHub macOS runner, signs it for the App Store and
uploads it to TestFlight. It runs on every push to `main` that touches the iPhone app (its folders, the shared files
listed under `MeetballPhone` in `project.yml`, or `project.yml` itself), and by hand from Actions › TestFlight › Run
workflow. The build number is the commit count, so each upload is newer than the last. Install the **TestFlight** app
on the iPhone; new builds then arrive (and install automatically, if you turn that on) about 10 minutes after a run.
TestFlight builds expire after 90 days, and nothing is submitted for App Store review: internal testing skips it.

One-time setup:
1. **App record.** In [App Store Connect](https://appstoreconnect.apple.com) › Apps › **+** › New App: platform iOS,
   any name not already taken on the App Store (it isn't shown to anyone but you), bundle ID `app.meetball.MeetballPhone`
   (it's listed once Xcode has registered it, step 3 above), any SKU. Under the app's **TestFlight** tab, add an
   Internal Testing group with yourself in it.
2. **API key.** App Store Connect › Users and Access › Integrations › App Store Connect API › Team Keys › **+**, role
   **Admin** (each run creates fresh App Store provisioning profiles, named "Meetball CI <bundle ID>", through the
   API with `Scripts/appstore-profiles.py`; they replace the previous run's). Download the `.p8` (only offered once) and note its Key ID and the Issuer ID.
3. **Distribution certificate.** On the Mac: Xcode › Settings › Accounts › your team › Manage Certificates › **+** ›
   Apple Distribution (skip if you already have one). Then in Keychain Access, under My Certificates, right-click
   "Apple Distribution: …" › Export, save as `.p12` with a password, and `base64 -i dist.p12 | pbcopy`.
4. **Secrets.** GitHub › the repo › Settings › Secrets and variables › Actions › New repository secret:

   | Secret | Value |
   | --- | --- |
   | `APP_STORE_CONNECT_KEY_ID` | the key's Key ID |
   | `APP_STORE_CONNECT_ISSUER_ID` | the Issuer ID |
   | `APP_STORE_CONNECT_KEY` | the whole `.p8` file, `-----BEGIN PRIVATE KEY-----` lines included |
   | `DISTRIBUTION_CERTIFICATE_P12` | the base64 from step 3 |
   | `DISTRIBUTION_CERTIFICATE_PASSWORD` | the `.p12` password |

5. Run the workflow from the Actions tab. Until every secret is set, a run warns and uploads nothing.

`ITSAppUsesNonExemptEncryption` is `false` in the Info.plist (the app uses only HTTPS), so builds don't wait on the
export-compliance question. If a run fails, `meetball-testflight-logs` has the archive and upload logs.

## Configuration (use your own credentials)
Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` (gitignored; never commit it) and set `GOOGLE_CLIENT_ID` (a Google Cloud "Desktop app" OAuth client, Calendar API enabled),
optional `GOOGLE_CLIENT_SECRET`, and `PRO_PRODUCT_IDS` (comma-separated App Store product IDs).
Pro is unlocked by default for personal builds (`PRO_UNLOCKED: "YES"` in `project.yml`; set to `NO` to enforce StoreKit). Also `MEETBALL_FORCE_PRO=1` in the scheme environment to test Pro features without StoreKit.

## Known gaps vs. the original
Not recovered (no decompiler was used): exact alert timings/copy, Supabase push-sync backend (this app polls Google directly),
RevenueCat/Mixpanel telemetry, App Attest. Screen-share detection is a heuristic.
