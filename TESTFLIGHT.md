# Getting RADIOACTIVE onto TestFlight

The app is **TestFlight-ready in code**: it builds (Debug + Release), passes its unit
tests, ships a privacy manifest, clears export compliance automatically, and carries the
novelty/disclaimer framing App Review needs. The steps below are the ones **only you can
do** (they need your Apple account) plus the on-device check that the Simulator can't.

## ✅ Already done (in the repo)
- `PrivacyInfo.xcprivacy` — declares precise location (App Functionality, not linked, not
  tracking) + UserDefaults reason `CA92.1`. Verified bundled into the `.app`.
- `ITSAppUsesNonExemptEncryption = NO` — export compliance auto-clears on upload.
- Location permission string reworded (no "contaminated businesses" claim).
- `MARKETING_VERSION = 1.0.0`, build `1`, category Entertainment.
- First-run **About/disclaimer** sheet + **Report/request-removal** on every place.
- Code signing scoped so the **Simulator** still builds unsigned, while a **device
  archive** will sign through your team.

## 1. You: Apple Developer + signing  (~15 min)
1. Enrol in the **Apple Developer Program** (£79/yr) if you haven't.
2. Open `Radioactive/Radioactive.xcodeproj` in Xcode → select the **Radioactive** target →
   **Signing & Capabilities** → tick **Automatically manage signing** → pick your **Team**.
   (This writes your `DEVELOPMENT_TEAM` into the project for both Debug and Release.)
3. The bundle id `com.xofvr.radioactive` will be registered on your account automatically
   the first time you archive.

## 2. You: a real support email  (2 min)
App Review needs a reachable contact. Replace the placeholder `reports@radioactive.app`
with your real email in two places:
- `Radioactive/Radioactive/Screens/AboutSheet.swift` → `contactEmail`
- `Radioactive/Radioactive/Screens/DetailScreen.swift` → the `mailto:` in `reportButton`

## 3. You: archive + upload  (~10 min)
1. In Xcode set the run destination to **Any iOS Device (arm64)**.
2. **Product → Archive**.
3. In the Organizer: **Distribute App → TestFlight (Internal Testing)** → Upload.
4. In **App Store Connect → your app → App Privacy**: declare **Precise Location →
   App Functionality**, *not linked to identity*, *not used for tracking* (matches the
   manifest). Export compliance auto-clears.
5. Add yourself as an **Internal Tester**; install via the TestFlight app on your phone.

## 4. You + me: the on-device compass check (the Simulator is blind to this)
On your phone in Bristol, on the Detector tab you should see **◎ POINT TO SCAN**; rotating
the phone should swing the needle and snap the aimed place. If it feels off, tell me and
I'll tune. Known follow-ups I'd do **before a public release** (fine for internal TestFlight):
- a visible **heading cone/reticle** on the radar + a **CALIBRATE** chip when the
  magnetometer is uncertain,
- decouple the **lock haptic** from the audio toggle + a distinct "acquired" cue,
- **radar pin de-clutter** (labels overlap on dense streets),
- pause GPS/compass on background (`scenePhase`) for battery.

## Not yet wired (your call)
**Real red-star ratings** need a **Google Places (New)** key — until then every reading is a
clearly-flagged **SIMULATED** stand-in (the app never presents a fake rating as real). See
the Obsidian note `RadioActive — MapKit Reviews Investigation` for the plan.
