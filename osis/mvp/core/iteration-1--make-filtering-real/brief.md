# Make Filtering Real Brief

**Version:** mvp
**Date:** 2026-05-17
**Status:** active

## Signals

- Author status note: the code is fully wired and the app builds, signs,
  notarizes, and launches with a working UI and ON/OFF icons, but the
  end-to-end filtering path has never been verified.
- The README documents Artichoke as if shipped and working; the author's own
  note contradicts that the filtering path is proven. Documented behavior and
  verified behavior have diverged.
- Every stage between the user approving the extension and a byte being dropped
  is currently debugged blind: there is no in-product way to see whether the
  extension activated, whether flows arrive, what verdict was returned, or
  whether bytes were counted.
- One manual step (first-launch System Settings approval of the system
  extension) is unavoidable and is the first thing that can silently fail with
  no visible signal.

## Insight

Artichoke today is a convincing UI sitting on top of a control path that has
never been observed doing its job. The product's entire promise (block by
default, allow what I tick, stop at the cap) reduces to a single chain of
six handoffs, any one of which could be silently broken. The reason it cannot
be trusted is not that a stage is known to be wrong; it is that no stage is
observable. The fix is not more features. It is making each handoff visible and
then walking the chain until every link provably holds.

## Bet

If we make each stage of the filtering path observable from inside the app and
then drive real traffic through it, we will find and fix the specific broken
links, and Artichoke will provably control traffic rather than just render it.
The load-bearing assumption is that the architecture is sound and the failures
are integration bugs (entitlements, attribution, verdict wiring, XPC delivery),
not a design that cannot work. This is wrong if a stage fails for a structural
reason the architecture cannot support; in that case the brief upward-propagates
and the architecture is reopened. It is right when, with the filter on, an
unchecked app is provably blocked, a checked app works, usage numbers move, and
the cap stops all traffic when hit.

## What Changes

| Area | Before | After |
|---|---|---|
| Extension activation | Unverified whether the sysext approves and activates | First-launch approval is guided and activation state is confirmed |
| Filtering | No evidence flows are seen, attributed, or enforced | Unchecked app provably blocked, checked app provably works |
| Usage | Byte reporting path unproven | Real traffic moves the per-app and total numbers |
| Cap | Cap enforcement never observed | Hitting the cap provably stops all traffic and notifies |
| Hotspot auto-on | Never observed firing | Expensive-link detection provably switches the filter on |
| Observability | Path debugged blind | In-UI diagnostics show extension state, flows seen, verdicts, bytes |

## What Doesn't Change

The two-process architecture, the App Group shared-file ruleset, the
verdicts-never-wait-on-XPC hot path, the SwiftUI menu-bar UI, the ON/OFF
icons, and the XcodeGen + Developer ID signing/notarization pipeline. All are
proven and deliberately untouched. The product scope stays the four jobs; no
new capability is added. "Notify only" cap mode stays out of scope.

## Shared Decisions

- Diagnostics: ship visible in-UI diagnostics (extension state, flows seen,
  verdicts, byte counts) as the verification instrument, not throwaway logging.
  Each stage must be observable before it is declared fixed.
- Verification order follows the data path, not build convenience: a later
  stage is only tested once the stage feeding it is observably correct.
- Fixes are integration repairs within the existing architecture; any fix that
  would require an architecture change triggers upward propagation instead.

## Phases

| Spec | Name | Depends on | Status |
|---|---|---|---|
| 01-diagnostics-surface | In-UI diagnostics surface (extension state, flows, verdicts, bytes) | — | not started |
| 02-activate-extension | Guide and confirm one-time sysext approval + activation | 01-diagnostics-surface | not started |
| 03-flows-and-attribution | Verify flows reach the extension and resolve to the correct app | 02-activate-extension | not started |
| 04-enforce-verdicts | Verify allow/drop enforced per ruleset (unchecked blocked, checked works) | 03-flows-and-attribution | not started |
| 05-byte-reporting | Verify bytes metered, reported over XPC, and displayed | 04-enforce-verdicts | not started |
| 06a-cap-enforcement | Verify hitting the cap stops all traffic and notifies | 05-byte-reporting | not started |
| 06b-hotspot-auto-on | Verify expensive-link detection switches the filter on | 04-enforce-verdicts | not started |

The path is mostly linear because each stage feeds the next. 06a (cap) and 06b
(hotspot) are siblings: cap needs the byte path proven first; hotspot only
needs enforcement working, so they can be verified in parallel once their
prerequisites land. The iteration ships when every row reads done.

## Success Criteria

- [ ] With the filter ON, an unchecked app is provably blocked from the network.
- [ ] With the filter ON, a checked app works normally.
- [ ] Driving real traffic moves the per-app usage and the running total.
- [ ] Reaching the data cap stops all traffic and posts a notification.
- [ ] Connecting to an expensive/tethered link switches the filter on automatically.
- [ ] The in-UI diagnostics show extension state, flows seen, verdicts, and bytes.

---

## Sessions

- 2026-05-17 — Initial capture from build session · `claude -r 5f0d9ee9-4359-4cbc-8d56-539a114c4fad`
