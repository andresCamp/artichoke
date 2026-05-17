# Artichoke MVP Product

## Definition

Artichoke is a free, open-source macOS menu-bar app that gives you a per-app
network switch for when you are on a metered or tethered connection. It lists
every app that wants the internet, blocks everything by default, and lets you
tick the few apps you actually need. It shows how much data each app is using,
enforces a hard total cap that stops all traffic when hit, and turns itself on
automatically when macOS reports an expensive link. It is for one person on one
Mac rationing data on a phone hotspot. No account, no backend, no telemetry.

## The Analogy

Think of what TripMode does for a metered connection, but free, open source,
notarized, and scoped to only the three jobs that matter on a hotspot.

## Core Concepts

| Concept | Definition |
|---|---|
| App entry | One application that has asked for the network, with an allow/block state. The unit the user reasons about. |
| Allow / block | The per-app verdict. Checked means traffic passes; unchecked means it is dropped. |
| Block by default | New or unseen apps start blocked. The user opts apps in, never out. |
| Master toggle | The artichoke icon. Closed = filter on (protecting), open = filter off (everything passes). |
| Usage | Bytes counted per app, plus a running total. "Today" is cumulative; "Live" is current bytes per second. |
| Data cap | A user-set MB ceiling. When the total reaches it, all traffic is blocked and a notification fires. |
| Hotspot auto-on | When macOS reports an expensive/tethered link, the filter switches itself on. |

## Structure

Two processes shipped in one bundle, split because macOS only permits per-app
socket blocking through a Network System Extension:

```
Artichoke.app (SwiftUI MenuBarExtra)        ArtichokeFilter.appex (NEFilterDataProvider,
  owns: ruleset, UI, data-cap logic,   ──►    run as a system extension)
  hotspot detection                            reads ruleset for per-flow allow/drop,
  writes ruleset → App Group file                counts bytes
                          ▲                              │
                          └──── XPC: discovered apps + byte deltas (~1/s) ────┘
```

The app owns all decisions and writes the ruleset to a shared App Group file.
The extension reads that file on the hot path (no round-trip per flow) to allow
or drop each connection and meter bytes, and reports telemetry back over NSXPC.
Distribution: XcodeGen build, Swift 6, manual Developer ID signing +
notarization, installed to /Applications, activated as a system extension via
`OSSystemExtensionRequest`.

## Flow

1. User installs Artichoke to /Applications and launches it. The artichoke icon
   appears in the menu bar.
2. First launch only: macOS prompts to approve the system extension in System
   Settings ▸ Privacy & Security. The user approves it once. This step is
   unavoidable for every user.
3. User connects via phone hotspot (or flips the master toggle on). The filter
   is now protecting; every app is blocked by default.
4. User opens the menu-bar panel, sees the list of apps requesting the network,
   and ticks the one or two they actually need (e.g. their browser).
5. Traffic for ticked apps passes; everything else is silently dropped. The
   panel shows per-app usage and a running total, switchable between Today and
   Live.
6. User optionally sets a data cap. When the total hits it, all traffic stops
   and a notification fires.

## UX / Surfaces

| Surface | Purpose | Key Elements |
|---|---|---|
| Menu-bar icon | At-a-glance state + master toggle | Closed artichoke = filter on, open = off |
| App list panel | The core control | Per-app rows with checkbox, per-app usage, running total at top |
| Usage switcher | Read consumption | Today (cumulative) vs Live (bytes/sec) |
| Cap control | Set the ceiling | MB limit input |
| System notification | Overspend safety net | Fires when the cap is reached |
| System Settings (macOS) | One-time extension approval | Privacy & Security approval prompt, first launch only |

## Behavioral Rules

**Always:**
- Block apps that are new, unknown, or unchecked. The default is deny.
- Make the user opt apps in, never opt them out.
- Stop all traffic the moment the data cap is reached, and post a notification.
- Turn the filter on automatically when macOS reports an expensive/tethered link.
- Keep all state on the local machine.

**Never:**
- Default any app to allowed for a smoother first run.
- Offer a "notify only" cap mode that watches overspend instead of stopping it.
- Send telemetry, require an account, or talk to a backend.
- Grow beyond the three hotspot jobs into a general firewall.

## Honest Status

All four capabilities are coded and wired. The app builds, signs, notarizes,
and launches; the UI and the ON/OFF menu-bar icons work.

Not yet verified end to end: extension approval/activation → flows reaching the
extension → correct app attribution → allow/drop enforcement → byte reporting →
cap enforcement → hotspot auto-on. This whole path is currently unproven and is
the subject of iteration 1.

One manual step is unavoidable for every user: the first-launch System Settings
▸ Privacy & Security approval of the system extension.

## Known Rough Spots

- Byte metering peeks all bytes of allowed flows. Overhead is acceptable for
  the small hotspot working set, costly for heavy apps.
- Live per-app in/out split is approximated. Cumulative totals are exact.
- Usage counters are in-memory only. They reset on app relaunch and at local
  midnight; there is no intra-day persistence yet.
- Hotspot detection keys on macOS reporting the link as expensive/constrained,
  which is broader than Personal Hotspot alone (e.g. matches cellular).

## Boundaries

Artichoke is NOT a general-purpose firewall, a security tool, a bandwidth
shaper, a per-domain or per-port filter, a multi-device or multi-user product,
or a network analytics dashboard. It is not a TripMode feature-parity project;
TripMode is the reference point for three jobs, not a spec to match. It does
not persist usage history, schedule rules, or run on iOS.

---

*2026-05-17*

---

## Sessions

- 2026-05-17 — Initial capture from build session · `claude -r 5f0d9ee9-4359-4cbc-8d56-539a114c4fad`
