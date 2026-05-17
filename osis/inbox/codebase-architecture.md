---
type: imported-signal
status: unconfirmed
source: Sources/, project.yml, Config/
captured: 2026-05-17
---

# Signal: codebase architecture as observed

Captured by reading the source. Describes what is built; status of whether it
works end to end is unconfirmed.

## Claims (observed in code)

- Two-process design: `Artichoke.app` (SwiftUI `MenuBarExtra`, owns ruleset +
  UI + cap + hotspot auto-on) and `ArtichokeFilter.appex`
  (`NEFilterDataProvider`, run as a system extension), bundle ids
  `dev.serdna.artichoke` / `dev.serdna.artichoke.filter`.
- Shared ruleset (`FilterDocument`) is written by the app to an App Group
  file (`filter.json`) and read by the extension with a 0.5s cache. Verdicts
  never cross XPC — a deliberate hot-path latency decision.
- XPC (`AppXPC` protocol) is one-directional in practice: extension →
  app, carrying discovered apps and coalesced per-app byte deltas (~1 msg/s).
  Mach service name == App Group id.
- App identity for verdicts is the code-signing identifier resolved from the
  flow's audit token via the Security framework (`AppResolver`), cached.
- Cap enforcement is app-driven: app flips `capReached` in the shared file;
  the extension's `isAllowed()` then drops everything.
- Build is XcodeGen-driven with a single `DEVELOPMENT_TEAM` knob; App Group
  and mach service derive from the signing team at runtime (no hardcoded
  Team ID). Swift 6, hardened runtime, manual Developer ID + notarization,
  unsandboxed.

## Tensions / open questions

- Author's status note: code is fully wired and the app builds/signs/launches
  with working UI, but the end-to-end filtering path
  (activation/approval → flows → enforce → byte reporting → cap → hotspot
  auto-on) is NOT verified end to end. This is the single biggest open risk
  and the stated next work.
- Allowed flows are kept in-path with `peekBytes: .max` purely to keep
  metering accurate — explicit perf/accuracy tradeoff scoped to "few flows."
- Usage is in-memory only; resets on app relaunch and at local midnight. No
  persistence layer. Possible product gap vs. user expectation of a daily
  total surviving restarts.
- Hotspot detection uses `isExpensive || isConstrained`, which also matches
  cellular generally, not only Personal Hotspot — behavior may be broader
  than the README's "Personal Hotspot" framing.

## Candidate questions for clarity session

- Is verifying the end-to-end filtering path the v1 definition of done?
- Should daily usage persist across restarts, or is per-session acceptable?
- Is the in-path metering tradeoff a permanent stance for the target use case?
- Is broad expensive-link auto-on (incl. cellular) intended, or should it be
  scoped tighter to tethered hotspots?
