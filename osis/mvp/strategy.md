# Artichoke MVP Strategy

This is a solo, open-source, paid macOS utility. Not a company, not a funded
product. The strategy is deliberately small: find the people already searching
for this exact thing, meet them with an honest answer, and let the work carry
itself.

## Target

One person on one Mac who is rationing internet by the megabyte and resents it:
travelers and digital nomads living off phone tethering, people in roaming or
on capped plans, rural users on satellite or fixed-wireless, students and
others on prepaid data. They already know macOS is leaking their hotspot. Many
have already found TripMode, balked at the subscription or the ~$39, and gone
looking for something else. That last group, the dissatisfied searcher, is the
sharpest target: the job is known, the alternative is named, the objection is
priced.

## Wedge

The narrowest place Artichoke wins unambiguously: the person who has typed
"TripMode alternative", "free TripMode", "open source TripMode", or "stop mac
hotspot data" into a search box. This is existing, high-intent demand with a
named competitor and a clear objection (subscription, closed source, price).
Artichoke is the open, auditable, ten-dollars-once, build-it-yourself-free
answer to that exact query. We do not need to create the need or change a
workflow; the need is searched for and the workflow (a menu-bar per-app
toggle) is already the one TripMode taught the market. We enter on the
comparison, not on a new behavior.

## Why Us

Three things only this project credibly offers right now, together:

- **Open source under PolyForm Noncommercial.** The verdict path is readable
  and auditable. A network filter that sees every connection asking you to
  trust a closed binary is a real objection; we remove it. TripMode cannot
  match this without changing what they are.
- **One-time $10, perpetual, no telemetry, no account, no expiry.** A direct
  answer to subscription fatigue. The price is positioned as an honesty
  signal, not a revenue model: you pay once for the work, you own it, it never
  phones home, build-from-source stays free for non-commercial use.
- **Founder-market fit.** Built by someone who rations tethered data and wrote
  the minimal honest version for their own use. The scope is disciplined
  (three hotspot jobs, nothing else) because it is built from the actual pain,
  not a feature matrix.

The window is the period before another open alternative occupies the
"TripMode alternative" position. Strategy spends that window on durable,
long-tail discoverability (below), not on a launch spike.

## GTM / Distribution

**Distribution reality (a constraint, not a choice):** Artichoke is a
NetworkExtension content-filter system extension. The Mac App Store forbids
that class of extension; it requires Developer ID distribution, notarization,
and a one-time System Settings approval. This is the same reason TripMode,
Little Snitch, and Lulu are not on the App Store. So Artichoke ships as a
Developer-ID-signed, notarized binary sold from the developer's own site
(Gumroad / Lemon Squeezy / Paddle), $10 one-time. There is no App Store lever
to pull; the GitHub repo and direct download are the entire funnel.

**The product is the page.** The GitHub README is the de facto product page,
because the wedge audience arrives via search and via "alternative" listicles
that link straight to repos. The README must be pain-first (the leaking-Mac
scene, not the architecture), carry a screenshot and a short GIF of the menu
toggling apps, use the exact language people search for ("open source / free
TripMode alternative"), and make the dual model unmistakable: build it free,
or pay $10 once for the signed build.

Channels, matched to where this audience already is, in priority order:

1. **GitHub README + repo metadata.** Topics, description, and listing all
   tuned to "TripMode alternative" / "macOS per-app firewall hotspot". This is
   the durable asset everything else points back to.
2. **Show HN.** One honest post: the problem, the open source, the price
   stance. The HN crowd overlaps heavily with metered/dev Mac users and
   rewards exactly this honesty.
3. **r/macapps and r/macOS.** Where Mac utility discovery actually happens for
   this audience. Post as the maker, lead with the pain and the open source.
4. **awesome-macos lists and "TripMode alternative" listicles.** Submit PRs /
   reach out. These rank for the wedge query for years and feed the README the
   long-tail intent traffic that matters more than any launch day.
5. **A one-page site, later, not first.** Only if the README ceiling is hit.
   Not a prerequisite for launch.

Activation is the user seeing apps blocked and their hotspot quiet, not the
purchase. The free build-from-source path is part of distribution, not a
leak: it lowers trust friction for the exact skeptics most likely to evangelize
the repo.

## Success Criteria

Modest and honest. This is a solo utility; success is reach and a fair return
for the work, not growth-curve economics.

| Metric | Target | Timeframe |
|---|---|---|
| Repo ranks on page 1 for "open source TripMode alternative" | listed in 1+ durable listicle/awesome list | 90 days post-launch |
| GitHub stars (proxy for wedge discoverability) | 300 | 90 days post-launch |
| Paid binary conversions | 100 | 90 days post-launch |
| Show HN reaches front page | front page once | launch week |

These are beliefs under test, not commitments. If the comparison query does
not convert, the positioning is wrong, not the channel mix.

## Non-Goals

- **No Mac App Store effort.** Architecturally impossible for a system
  extension; pursuing it would mean breaking the product.
- **No paid marketing or ads.** The audience is reachable for free via search
  and community; paid acquisition does not fit a $10 one-time utility.
- **No subscription, no tiers, no "pro" edition.** The price is one honest
  number; segmenting it would betray the stance and the manifesto.
- **No feature-parity race with TripMode.** Three hotspot jobs is the scope.
  Competing on feature count abandons the wedge (honest, minimal, open).
- **No company, no roadmap-for-investors, no GTM org.** Solo project; any
  motion that assumes a team or funding is out of scope.
- **No telemetry-driven growth loops.** We cannot and will not instrument the
  app; success is read from public proxies (stars, sales, listings), not user
  data.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| End-to-end filtering path still unverified (iteration 1) | A shipped product that does not actually block; reputational damage on the exact audience that audits | Do not launch the paid binary until the full path is verified; gate GTM on iteration 1 |
| System-extension approval friction (one-time Settings approval) | Users bounce at first run, blame the app | README sets expectation up front with a screenshot of the approval step; treat the prompt as a known, explained step, not a surprise |
| Someone ships an open MIT alternative into the wedge first | Loses the "open source TripMode alternative" position | Spend the window on durable listicle/awesome placement now; openness + disciplined scope is the defensible difference, not just being free |
| Non-commercial license read as "not really open" by purists | Loud objections in HN/Reddit threads dominate the narrative | Be explicit and unapologetic in README and manifesto: source-available, free to build for personal use, $10 funds the work; do not argue the OSI definition, state the deal plainly |
| Price objection ("why pay when I can build it") | Low conversion despite high traffic | This is intended: free build is the trust funnel; the $10 buys signed/notarized/auto-update convenience and supports the work. Frame it that way, do not fight it |
| Apple changes NetworkExtension/Developer ID distribution rules | Distribution path closes | Low-probability, watched not mitigated; the same risk applies to every competitor, so it is a category risk, not a relative one |

---

*Artichoke MVP, 2026-05-17*

---

## Sessions

- 2026-05-17 — Non-commercial license + paid-binary model: manifesto reconciled, strategy.md created · `claude -r 5f0d9ee9-4359-4cbc-8d56-539a114c4fad`
