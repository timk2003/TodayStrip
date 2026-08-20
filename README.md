# TodayStrip

Everything that matters about today, in one line of your menu bar.

TodayStrip shows a single item at a time — the next event, a running timer, your
Focus, battery, weather, today's note — and rotates between them by relevance. A
meeting two minutes out takes the strip and holds it. A running timer does the
same. Weather waits its turn.

Click it for the details panel: join the meeting, start a timer, jot the one line
you want to remember about today.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16 or later to build

## Building

```sh
git clone https://github.com/<you>/TodayStrip.git
cd TodayStrip
open TodayStrip.xcodeproj
```

No API keys, no accounts, no entitlements to provision — clone and run. Weather
comes from [Open-Meteo](https://open-meteo.com), which needs neither.

## The six modules

| Module | Source | Notes |
| --- | --- | --- |
| Next event | EventKit | Detects Zoom/Meet/Teams/Webex links and offers a join button. All-day, cancelled and declined events are skipped. |
| Timer | — | Countdown and stopwatch. Owns the strip while running. |
| Focus | `~/Library/DoNotDisturb/DB` | See the caveat below. |
| Battery | IOKit | Hidden on machines without one. |
| Weather | Open-Meteo | Current location (coarse) or a place you pick. |
| Today's note | JSON in Application Support | One line per day, previous days kept. |

Every module can be switched off in Settings, and a module with nothing to
report drops out of the rotation on its own.

### The Focus caveat

macOS exposes no public API for the active Focus. TodayStrip reads the same JSON
files Control Center writes, which means two things:

1. **The app cannot be sandboxed**, so it cannot ship on the Mac App Store.
2. **It may break.** If Apple moves or reshapes those files, the module reports
   nothing and disappears from the strip — nothing else is affected.

Turn the module off in Settings if you would rather not rely on it.

## How the rotation works

Each module publishes at most one `StripItem` carrying a priority:

- `ambient` — weather, today's note
- `normal` — an event later today, an active Focus
- `elevated` — event within 15 minutes, battery under 20%
- `urgent` — event within 5 minutes, battery under 10%
- `pinned` — running timer, event within 2 minutes

Items rotate in priority order and dwell longer the more urgent they are. Two
rules break the round-robin: a `pinned` item stops rotation entirely, and an item
that *becomes* `urgent` cuts in immediately instead of waiting its turn. Scroll
over the strip to step through manually; the rotation also pauses while the panel
is open.

## Architecture

```
StatusItemController  ← the NSStatusItem, cross-fades between items
        ↑
   StripRotator       ← priority + rotation, pure logic, no AppKit
        ↑
   AppModel           ← the only object that knows all six sources exist
        ↑
   StripSource × 6    ← Calendar, Timer, Focus, Battery, Weather, Note
```

Sources know nothing about rotation, the menu bar, or each other. They observe
one thing, and publish a `StripItem` when their answer changes. `StripRotator`
takes all its time through `tick(_:)`, so its behaviour is testable without
waiting on a clock.

AppKit rather than SwiftUI's `MenuBarExtra` for the status item itself: the
rotation needs to cross-fade, which `MenuBarExtra`'s label does not expose. The
popover and settings are SwiftUI.

## Privacy

Nothing leaves your Mac except a weather request to Open-Meteo, containing
coordinates rounded to four decimal places and no identifier. Calendar data,
notes and Focus state are read locally and never transmitted.

## Licence

MIT. Weather data by [Open-Meteo.com](https://open-meteo.com) (CC BY 4.0).
