<div align="center">

<img src="docs/icon.png" width="128" alt="TodayStrip app icon">

# TodayStrip

**One line in your menu bar, showing whatever matters most right now.**

[![Latest release](https://img.shields.io/github/v/release/timk2003/TodayStrip?label=release&color=blue&cacheSeconds=1800)](https://github.com/timk2003/TodayStrip/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/timk2003/TodayStrip/total?color=blue&cacheSeconds=1800)](https://github.com/timk2003/TodayStrip/releases)
[![License](https://img.shields.io/github/license/timk2003/TodayStrip?color=blue)](LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-lightgrey)

[**Download**](https://github.com/timk2003/TodayStrip/releases/latest) · [Features](#features) · [Automation](#automation) · [Development](#development)

</div>

TodayStrip shows a single item at a time and rotates between them by relevance — a meeting two
minutes out takes the strip and holds it, a running timer does the same, the weather waits its
turn. No account, no analytics, no background service.

## Features

**The strip**
- One item at a time, rotating by priority, with a cross-fade between them
- A meeting about to start or a running timer pins the strip until it resolves
- Something that becomes urgent cuts in instead of waiting its turn
- Scroll over the strip to step through manually; rotation pauses while the panel is open

**Next event**
- Leads with your free time when the next meeting is far off — "Free until 14:00" — and switches
  to a countdown inside the last hour
- Detects Zoom, Meet, Teams, Webex, Whereby, Jitsi, Slack and Discord links in the invitation
- When the call is minutes away, clicking the strip joins it directly
- All-day, cancelled and declined events are skipped; calendars are individually selectable

**Timer**
- Countdown with presets, or a stopwatch, with a notification and sound when time is up
- Owns the strip while it runs

**Weather**
- Reports what changes: rain starting within the hour, frost tonight — and falls back to plain
  conditions when nothing is happening
- Current location (coarse) or a place you pick, in Celsius or Fahrenheit

**Focus, battery, today's note**
- The active Focus, read from the files Control Center writes — see [the caveat](#the-focus-caveat)
- Battery percentage and remaining time, loud only when it is actually low
- One line per day, with the previous week a click away

Every module can be switched off, and a module with nothing to report drops out of the rotation
on its own.

## Install

Download the latest `TodayStrip.dmg` from [Releases](https://github.com/timk2003/TodayStrip/releases)
and drag **TodayStrip** to your Applications folder.

Releases are signed and notarized by Apple, so they open without Gatekeeper warnings.

On first launch, TodayStrip asks for calendar access. Weather asks for location only if you leave
it on "current location" — pick a city in Settings instead and it never asks.

### The Focus caveat

macOS exposes no public API for the active Focus. TodayStrip reads the same JSON files Control
Center writes under `~/Library/DoNotDisturb/`, which means two things:

1. **The app cannot be sandboxed**, so it will never ship on the Mac App Store.
2. **It may break.** If Apple moves or reshapes those files, the module reports nothing and
   disappears from the strip. Nothing else is affected.

Turn the module off in Settings if you would rather not rely on it.

## Automation

Two global shortcuts, registered through Carbon so they need no Accessibility permission:

| Shortcut | Action |
| --- | --- |
| ⌥⌘T | Open the panel |
| ⌥⌘R | Start or pause the timer |

And a URL scheme, so Shortcuts, Raycast, Alfred or a shell script can drive it:

```sh
open "todaystrip://timer/25"
open "todaystrip://stopwatch"
open "todaystrip://timer/stop"
open "todaystrip://note?text=Ship%20the%20release"
open "todaystrip://open"
```

## Development

Open `TodayStrip.xcodeproj` in Xcode and run the `TodayStrip` scheme.

```sh
xcodebuild -project TodayStrip.xcodeproj -scheme TodayStrip -configuration Debug build
xcodebuild -project TodayStrip.xcodeproj -scheme TodayStrip -destination 'platform=macOS' test
```

No API keys, no accounts, no entitlements to provision — clone and run. Weather comes from
[Open-Meteo](https://open-meteo.com), which needs none.

### Layout

```
StatusItemController  ← the NSStatusItem, cross-fades between items
        ↑
   StripRotator       ← priority + rotation, pure logic, no AppKit
        ↑
   AppModel           ← the only object that knows all six sources exist
        ↑
   StripSource × 6    ← Calendar, Timer, Focus, Battery, Weather, Note
```

Sources know nothing about rotation, the menu bar, or each other. Each observes one thing and
publishes a `StripItem` when its answer changes.

Two conventions make the interesting parts testable without a clock or a network:

- Wording and priority live in pure static functions — `WeatherHeadline.of`, `CalendarHeadline.of`,
  `CalendarSource.item(for:now:)`, `AppModel.clickAction` — that take `now` as a parameter.
- `StripRotator` takes all its time through `tick(_:)`.

AppKit rather than SwiftUI's `MenuBarExtra` for the status item: the rotation needs to cross-fade,
which `MenuBarExtra`'s label does not expose. The panel and settings are SwiftUI.

### Releasing

```sh
xcrun notarytool store-credentials todaystrip-notary \
  --key AuthKey_XXXX.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>

./scripts/build_release.sh
```

Runs the tests, archives, signs with Developer ID, notarizes and staples both the app and the
disk image, then verifies Gatekeeper acceptance. Credentials are checked before anything is built.
The result lands in `build/TodayStrip-<version>.dmg`.

## Privacy

Nothing leaves your Mac except a weather request to Open-Meteo, containing coordinates rounded to
four decimal places and no identifier. Calendar data, notes and Focus state are read locally and
never transmitted.

## Licence

MIT — see [LICENSE](LICENSE). Weather data by [Open-Meteo.com](https://open-meteo.com) (CC BY 4.0).

---

<div align="center">

If TodayStrip made your day a little easier to read, consider giving it a ⭐.

</div>
