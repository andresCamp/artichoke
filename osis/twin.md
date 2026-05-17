# Artichoke — Operational Twin

Mechanical map of what the product is and how its parts connect. Present tense,
descriptive. Read in 2-3 minutes.

## What it is

Artichoke is an open-source (MIT), per-app data firewall for macOS 14+. It is a
focused clone of TripMode's three jobs on a metered hotspot: per-app traffic
gating, a live usage monitor with a running daily total, and a hard data cap
that blocks everything when hit. It also auto-enables itself when macOS reports
an expensive/tethered link (Personal Hotspot).

Distributed as a single signed/notarized `.app` installed into `/Applications`.
No backend, no account, no telemetry off-device. State lives entirely on the
local machine.

## Two-process architecture

macOS only allows per-app socket blocking through a Network System Extension,
so the product is split across two processes that ship in one bundle:

```
┌──────────────────────────────────────┐        ┌────────────────────────────────────┐
│ Artichoke.app (Artichoke target)     │        │ ArtichokeFilter.appex              │
│ SwiftUI MenuBarExtra, LSUIElement     │        │ (NEFilterDataProvider, app-extension│
│ dev.serdna.artichoke                  │        │  run as a system extension)         │
│                                       │        │ dev.serdna.artichoke.filter         │
│ • AppState: ruleset, usage, cap,      │        │                                     │
│   day rollover, hotspot policy        │        │ • handleNewFlow → allow / .drop()   │
│ • ExtensionManager: activates the     │        │ • per-flow byte metering            │
│   sysext via OSSystemExtensionRequest │        │ • AppResolver: audit-token → signing│
│ • FilterController: NEFilterManager   │        │   identifier (verdict key)          │
│   on/off (filterSockets)              │        │                                     │
│ • HotspotMonitor: NWPathMonitor       │        │                                     │
│ • AppXPCListener: NSXPC server        │        │ ExtensionIPCClient: NSXPC client    │
└───────────────┬───────────────────────┘       └──────┬───────────────────────┬──────┘
                │ writes FilterDocument (owner)         │ reads ruleset         │ XPC push
                ▼                                       ▼ (cached ~0.5s)        │ (discovered
   App Group container: filter.json  ◀────────── reads only ────────────────   │  apps + byte
   group.<team>.dev.serdna.artichoke                                           │  deltas, ~1/s)
                ▲                                                               │
                └───────────────────────────────────────────────────────────────┘
                            NSXPC mach service name == App Group id
```

Key design choice: **verdicts never wait on XPC**. The extension reads the
ruleset straight from the shared App Group file (`SharedStore`, 0.5s TTL
cache), so a block/allow decision never blocks on a round trip. XPC carries
only two things, extension → app: newly discovered apps, and coalesced
per-app byte deltas (batched to ~1 message/sec).

## Source layout

- `Sources/Shared/*` — compiled into both targets:
  - `Models.swift`: `AppEntry`, `UsageCounter`, `FilterDocument`
    (`enabled`, `capBytes`, `capReached`, `allowUnknownByDefault`, `apps`;
    `isAllowed()` is the verdict rule — disabled ⇒ allow all, capReached ⇒
    drop all, else per-app entry or `allowUnknownByDefault`).
  - `AppGroup.swift`: resolves the App Group id from the running process's
    entitlements at runtime (no hardcoded Team ID); doubles as the mach
    service name.
  - `SharedStore.swift`: atomic file-backed `FilterDocument` store; app
    writes, extension reads (cached).
  - `IPC.swift`: `@objc AppXPC` protocol contract.
- `Sources/App/*` — `ArtichokeApp` (`@main`, `MenuBarExtra` with ON/OFF
  template icons), `AppState` (`@MainActor @Observable` single model),
  `ExtensionManager`, `FilterController`, `HotspotMonitor`,
  `AppXPCListener`, `Views/MenuView.swift` + `Views/AppRow.swift`.
- `Sources/Extension/*` — `FilterDataProvider` (verdict + metering core),
  `AppResolver` (audit-token → code-signing identifier via Security
  framework), `ExtensionIPCClient` (coalescing XPC client).
- `Config/*` — Info.plists + entitlements. App holds
  `system-extension.install`, `networkextension`
  (content-filter-provider-systemextension), and the app-group
  (`$(TeamIdentifierPrefix)dev.serdna.artichoke`). Extension holds the
  networkextension + app-group entitlements and declares
  `NEProviderClasses` → `FilterDataProvider`.
- `icons/` + `Assets.xcassets` — app icon set and ON/OFF menu-bar template
  SVGs (identical 18×18 viewBox so the status item never shifts width).

## How the four features map to code

- **Per-app firewall**: extension `handleNewFlow` resolves app id, reads
  cached `FilterDocument`, returns `.drop()` or an in-path filter verdict.
  Unseen apps are reported to the app and added to `apps` with
  `allowUnknownByDefault` (default block-by-default).
- **Live monitor + daily total**: allowed flows stay in-path with
  `peekBytes: .max`; `handleInbound/OutboundData` meter byte counts,
  `ExtensionIPCClient` coalesces and pushes deltas; `AppState`
  accumulates per-app `UsageCounter`s, samples a 1s live rate, and rolls
  counters over at local midnight.
- **Hard data cap**: `AppState.enforceCap()` flips `FilterDocument.capReached`
  in the shared store when `totalBytes >= capMB`; the extension's
  `isAllowed()` then drops all flows. Hard-block only ("notify only" not
  implemented). Fires a `UNUserNotification`.
- **Auto-on for hotspots**: `HotspotMonitor` (`NWPathMonitor`,
  `isExpensive || isConstrained`) → `AppState.hotspotChanged` enables the
  filter and notifies.

## Build & ship

XcodeGen-driven (`project.yml`, single `DEVELOPMENT_TEAM` knob; everything
else derives from the signing team at runtime). Swift 6, hardened runtime,
manual Developer ID signing + notarization, App Sandbox off (Developer ID
firewall app). Extension is `type: app-extension` embedded into the app and
activated at runtime as a system extension (entry point `_NSExtensionMain`).
Dev loop requires copying to `/Applications` (SIP requirement for Developer ID
system extensions). Logs under subsystem `dev.serdna.artichoke`.

## Honest status

The code is fully wired and the app builds, signs, notarizes, and launches
with a working menu-bar UI and ON/OFF icons. The end-to-end filtering path —
system-extension activation/approval → flows reaching `handleNewFlow` →
enforced allow/drop → byte reporting over XPC → cap enforcement → hotspot
auto-on — has **not been verified end to end**. That verification is the next
work.

Known limitations noted by the author: byte metering keeps allowed flows
in-path (`peekBytes: .max`) — fine for small hotspot working sets, costly for
heavy apps; live in/out split is approximated (raw totals exact); cumulative
usage does not persist across app restarts within a day (resets on relaunch,
plus a midnight rollover); "notify only" cap mode is intentionally absent.
