---
type: imported-signal
status: unconfirmed
source: README.md
captured: 2026-05-17
---

# Signal: README — product framing & spec

The repo README is the de-facto product spec. Captured as unconfirmed signal,
not as truth.

## Claims

- Artichoke is "an open-source, per-app data firewall for macOS — a focused
  clone of TripMode's three features that matter on a metered hotspot."
- Scope is deliberately four jobs: (1) per-app firewall, default-block, user
  ticks apps in; (2) live monitor + running daily total; (3) hard data cap
  that blocks ALL traffic when hit + notifies; (4) auto-on when macOS reports
  an expensive/tethered link (Personal Hotspot).
- Positioning: the only supported macOS mechanism for per-app blocking is a
  Network System Extension; Artichoke is the minimal honest implementation of
  that.
- MIT licensed, single-developer, no backend/account/telemetry implied.
- Cap is "hard-block by design" — "notify only" cap mode explicitly out of
  scope.

## Tensions / open questions

- The README is written as if shipped, but the author's separate status note
  says the end-to-end filtering path is unverified. Tension between
  "documented as working" and "not verified end to end."
- "Focused clone of TripMode" — is fidelity to TripMode the product north
  star, or is TripMode just the reference point for an opinionated minimal
  tool? (manifesto-level question)
- Stated limitations (in-path metering cost for heavy apps, no cross-restart
  usage persistence, approximated in/out split) are framed as acceptable for
  "a deliberately-small hotspot working set" — is that scope assumption a
  permanent product stance or a temporary MVP cut?
- Default-block-by-default is asserted as the right model (TripMode-style) —
  worth confirming this is the intended product opinion vs. an implementation
  default.

## Candidate questions for clarity session

- What is the single sentence this product exists to deliver?
- Is "clone of TripMode" the ambition ceiling, or a starting reference?
- Is the small-hotspot-working-set assumption a deliberate scope boundary?
- What does "done" mean for v1 — verified end-to-end filtering, or shipped
  binary?
