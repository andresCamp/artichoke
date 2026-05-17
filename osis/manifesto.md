# Artichoke

## Your Mac spends your hotspot data behind your back, and macOS gives you no way to stop it.

---

## The Problem

You tether your laptop to your phone because there is no other network. You
have a few hundred megabytes before the plan throttles or the bill climbs, and
you are spending them carefully on the one thing you actually need to do.

Then the spinner appears. Photos decided now was the time to sync. The OS
started pulling a multi-gigabyte update. Dropbox woke up. A dozen apps you
never opened are quietly talking to the internet on a connection you are
rationing by the megabyte. By the time you notice, the data is gone. You did
not choose any of it, and macOS never asked.

## The Deeper Structure

This is not carelessness by app developers. Every one of those apps is doing
exactly what it was built to do on the assumption it has always been allowed to
make: that the network is free and unlimited. macOS does nothing to challenge
that assumption. There is no per-app network switch anywhere in System
Settings. The operating system knows when it is on a Personal Hotspot, it even
flags the link as expensive internally, and it still lets everything through.

The capability to do this correctly exists in macOS, but only as a low-level
Network System Extension primitive meant for security vendors, not as a feature
any normal person can reach. So the gap got filled by closed-source utilities
that rent you the control on a subscription. The control you need is reachable,
just not yours to inspect and not yours to keep.

## What Changed

The Network Extension framework is now stable and the system-extension
distribution path works for an independent developer with a Developer ID and
notarization. One person can now build the per-flow control that used to
require a commercial security stack, sign it, notarize it, and open the source
so anyone can read it, audit it, or build it themselves. The only thing
standing between a metered Mac user and per-app network control is somebody
deciding to write the honest minimal version, charge a fair one-time price
instead of a forever subscription, and stop hiding the code.

## The Declaration

Artichoke gives you a per-app switch for the network and defaults every switch
to off. On a constrained connection nothing reaches the internet until you tick
the box for the app you actually need. You set a hard ceiling and when it is
hit, everything stops. The source is open and readable: build it yourself for
free, for any personal non-commercial use, forever. Or pay ten dollars, once,
for the signed, notarized, auto-updating build, and own it outright. No
subscription, no account, no telemetry, no expiry. It does exactly the three
jobs that matter on a hotspot and nothing else. The default is deny, because on
data you are paying for by the megabyte, silence should be the safe state, not
the surprise.

## What We Refuse

We will not ship a "notify only" cap that watches you overspend and tells you
about it afterward. We will not default any app to allowed for the sake of a
smoother first run. We will not put this behind a subscription, an account,
telemetry, or a backend, and we will not lock you in: the source stays open and
the paid build never phones home or expires. We will not grow past the three
hotspot jobs into a general firewall or a network dashboard. We will not
contort the architecture to fit Mac App Store rules; a per-app network filter
is a system extension, App Store sandboxing forbids that, and we will not break
the thing to be listed in the store. The price is the one honest exchange we
keep: ten dollars once for the work, never rent. Every refusal here would be
easier or more impressive to drop, and every one would betray the person
rationing data who installed this to be protected by default, not managed and
not milked.

---

*Artichoke, 2026-05-17*

---

## Sessions

- 2026-05-17 — Non-commercial license + paid-binary model: manifesto reconciled, strategy.md created · `claude -r 5f0d9ee9-4359-4cbc-8d56-539a114c4fad`
- 2026-05-17 — Initial capture from build session · `claude -r 5f0d9ee9-4359-4cbc-8d56-539a114c4fad`
