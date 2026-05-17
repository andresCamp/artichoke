# Artichoke

A source-available, per-app data firewall for macOS — a focused, open
alternative to TripMode, covering the three things that matter on a metered
hotspot:

- **Per-app firewall** — every app is listed; only the ones you tick get
  network access, everything else is dropped.
- **Live monitor + usage totals** — real-time per-app throughput and a running
  daily total.
- **Hard data cap** — set an MB limit; when you hit it, *all* traffic is
  blocked and you get a notification.
- **Auto-on for hotspots** — when macOS reports an expensive/tethered link
  (Personal Hotspot), the filter switches itself on.

## License & how to get it

Source-available under the [PolyForm Noncommercial 1.0.0](LICENSE) license:
read it, build it, and use it yourself for any non-commercial purpose, free,
forever. You may not sell it or use it commercially.

- **Build it yourself** — clone, follow the build steps below, run it. Free.
- **Official build — $10 once** — a signed, notarized, auto-updating binary
  from [the project site]. One-time, perpetual. No subscription, no account,
  no telemetry. It just pays for the work.

Not on the Mac App Store, and it can't be: Artichoke is a NetworkExtension
*system extension*, which Apple distributes via Developer ID + notarization
only (the same reason TripMode and Little Snitch aren't on the App Store).

## How it works

macOS has no way to block traffic per-app from a normal process — the only
supported mechanism is a **Network System Extension**. Artichoke is a
SwiftUI menu-bar app that embeds an `NEFilterDataProvider` content-filter
system extension.

```
┌────────────────────────┐         ┌──────────────────────────────┐
│ Artichoke.app        │  XPC    │ ArtichokeFilter.appex      │
│ (menu bar, SwiftUI)     │◀───────▶│ (NEFilterDataProvider)        │
│  • ruleset + UI         │telemetry│  • handleNewFlow → allow/drop │
│  • data-cap enforcement │         │  • byte metering              │
│  • hotspot auto-on      │         └──────────────┬───────────────┘
└────────────┬────────────┘                        │ reads rules
             │ writes ruleset                       ▼
             └────────────────▶  App Group container (filter.json)
```

Verdicts never wait on XPC: the extension reads the ruleset straight from the
shared App Group file (cached ~0.5 s). XPC is used only for the extension to
report newly-seen apps and coalesced byte deltas back to the app.

| File | Role |
|---|---|
| `Sources/Shared/*` | Models, App Group resolver, shared store, XPC contract — compiled into both targets |
| `Sources/Extension/FilterDataProvider.swift` | The verdict + metering core |
| `Sources/App/AppState.swift` | Observable model: ruleset, usage, cap, rollover |
| `Sources/App/Views/*` | The menu-bar popover |

## Prerequisites

- macOS 14+
- Xcode 26 (installed at `/Applications/Xcode.app`)
- A **paid Apple Developer account** (Network System Extensions must be signed
  with a Developer ID — there is no free path with SIP enabled)
- [XcodeGen](https://github.com/yonyz/XcodeGen): `brew install xcodegen`

## Setup

1. **Point the build at your Developer team.** Edit `project.yml` and set
   `DEVELOPMENT_TEAM:` to your 10-character Team ID
   (`security find-identity -v -p codesigning`, or Xcode ▸ Settings ▸
   Accounts). Nothing else needs editing — the App Group and XPC service
   names derive from the signing team at runtime.

2. **Generate the Xcode project:**
   ```sh
   cd artichoke
   xcodegen generate
   ```

3. **Build & run.** Either open `Artichoke.xcodeproj` in Xcode and run, or:
   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
     xcodebuild -project Artichoke.xcodeproj \
     -scheme Artichoke -configuration Release build
   ```

4. **Install to /Applications.** With SIP enabled, a Developer-ID system
   extension only loads from an app inside `/Applications`. Copy the built
   `Artichoke.app` there and launch it from there.

5. **Approve the extension.** First launch triggers a system prompt — approve
   it in **System Settings ▸ Privacy & Security**. Then toggle the switch in
   the menu bar.

## Dev loop

Because of the `/Applications` requirement, iterate with:

```sh
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Artichoke.xcodeproj -scheme Artichoke -configuration Release \
  -derivedDataPath build build
rm -rf /Applications/Artichoke.app
cp -R build/Build/Products/Release/Artichoke.app /Applications/
open /Applications/Artichoke.app
```

Inspect the extension's logs:
`log stream --predicate 'subsystem == "dev.serdna.artichoke"' --level debug`

## Known limitations / next steps

- Byte metering uses `peekBytes: .max`, which keeps allowed flows in-path.
  Fine for a deliberately-small hotspot working set; revisit if you allow
  heavy apps. (`continueVerdict` in `FilterDataProvider.swift` is the knob.)
- Per-app in/out split for the *live rate* is approximated as a combined
  delta; raw totals are exact.
- No persistence of cumulative usage across app restarts within a day (resets
  on relaunch). The daily rollover wipes counters at local midnight.
- "Notify only" cap mode is not implemented — cap is hard-block by design.
