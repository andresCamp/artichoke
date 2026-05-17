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
any normal person can reach. So the gap got filled by paid, closed-source
utilities. The control you need is reachable, just not free and not yours.

## What Changed

The Network Extension framework is now stable and the system-extension
distribution path works for an independent developer with a Developer ID and
notarization. One person can now build the per-flow control that used to
require a commercial security stack, sign it, and give it away. The only thing
standing between a metered Mac user and per-app network control is somebody
deciding to write the honest minimal version and not charge for it.

## The Declaration

Artichoke gives you a per-app switch for the network and defaults every switch
to off. On a constrained connection nothing reaches the internet until you tick
the box for the app you actually need. You set a hard ceiling and when it is
hit, everything stops. It is free, open source, and notarized, and it does
exactly the three jobs that matter on a hotspot and nothing else. The default
is deny, because on data you are paying for by the megabyte, silence should be
the safe state, not the surprise.

## What We Refuse

We will not ship a "notify only" cap that watches you overspend and tells you
about it afterward. We will not default any app to allowed for the sake of a
smoother first run. We will not add accounts, telemetry, a backend, or a paid
tier. We will not grow past the three hotspot jobs into a general firewall or a
network dashboard. Every one of those would be easier or more impressive, and
every one would betray the person rationing data who installed this to be
protected by default, not managed.

---

*Artichoke, 2026-05-17*

---

## Sessions

- 2026-05-17 — Initial capture from build session · `claude -r 5f0d9ee9-4359-4cbc-8d56-539a114c4fad`
