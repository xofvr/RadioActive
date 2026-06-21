# ☢️ RADIOACTIVE — Review Geiger Counter

> Point your phone at a place. The needle climbs on **bad** reviews.

A novelty field instrument for iOS. RADIOACTIVE is a handheld "review geiger counter":
the worse a place's reviews, the more **radioactive** it reads. Aim the detector, watch the
analog needle swing into the red, listen to the live Geiger crackle, and hunt down the most
gloriously terrible kebab houses, pubs and cafés around you.

Bad reviews aren't ⭐ stars here — they're **red stars** ☢️. Five red = maximum contamination.

This is a fully native **SwiftUI** app for **iOS 26**, built on Apple's Human Interface
Guidelines and the **Liquid Glass** design system — a retro phosphor-CRT instrument rendered
with modern Apple materials.

---

## Screens

| | |
|---|---|
| **Detector** | The hero instrument — a semicircular analog dose meter with a jittering needle, a live oscilloscope trace, CPM readout, contamination status, and a Geiger-audio toggle. Cycle targets and tap through to a full report. |
| **Map** | A tactical **radar scope** — rotating sweep, range rings, a pulsing "you", and a pin for every contaminant placed by real bearing + distance. |
| **Nearby** | The leaderboard of the worst, sorted toxic-first, filterable by Pubs / Cafés / Eats, each with a red-star badge and a "badness" meter. |
| **Detail** | The dossier — peak CPM, rating breakdown, and genuine field reports ("The *fish* filed a missing persons report."). |

## The instrument, modelled honestly

The needle isn't random. A place's **badness** `(5 − rating) / 5` sets the ceiling; your aim
(heading vs. the target's bearing) and proximity only swing the needle *within* that band — so
a good place can never be made to read bad. Geiger clicks fire from a Poisson process whose
rate tracks the live reading, driving both **CoreHaptics** taps and **AVAudioEngine**
band-passed noise bursts. It all runs off a `CADisplayLink` at display rate and publishes via
the Observation framework, so the `Canvas` instruments redraw every frame.

## Design provenance

The UI was designed in **[Claude Design](https://claude.ai/design)** (`Radioactive.dc.html`)
and ported 1:1 to native SwiftUI — same palette, same physics model, same copy — then
re-grounded in HIG + Liquid Glass: floating chrome (tab bar, audio control, filter chips,
range chip) rides on real Liquid Glass, while the dark instrument bodies keep the CRT soul.
Typography pairs the **VT323** pixel font (instrument readouts) with SF Pro + Dynamic Type
(human content).

> **App icon is a placeholder.** The current radiation-trefoil icon is a stand-in pending the
> real logo. To swap it, replace `Radioactive/Radioactive/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
> (a single 1024×1024 PNG) — or drop the new icon into the asset catalog in Xcode.

## Build & run

Requires **Xcode 26** (iOS 26 SDK).

```bash
cd Radioactive
xcodebuild -scheme Radioactive -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# or just open it
open Radioactive.xcodeproj
```

Then run on any iOS 26 simulator or device. Enable **Geiger audio** on the Detector screen
and aim — the crackle (and, on device, the haptics) get hotter as the reviews get worse.

## Architecture

```
Radioactive/Radioactive/
├── Theme/         Palette, danger-gradient, VT323 registration, Liquid Glass helpers
├── Model/         Place data + DetectorEngine (the physics, CADisplayLink clock)
├── Instruments/   Canvas: GaugeView, ScopeView, RadarView
├── Components/    RedStars, StatusPill, CRTOverlay
├── Screens/       RootView (glass TabView) + Detector / Map / Nearby / Detail
└── Audio/         GeigerAudio (AVAudioEngine), Haptics (CoreHaptics)
```

The project uses Xcode's file-system-synchronized groups — drop a Swift file in a folder and
it's in the target.

---

*All establishments are fictional. Any resemblance to your local chippy is, regrettably, plausible.*

VT323 © The VT323 Project Authors, [SIL Open Font License](https://openfontlicense.org).
