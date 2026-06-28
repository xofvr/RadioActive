import SwiftUI

/// App shell: a Liquid Glass tab bar (iOS 26) over three NavigationStacks, with
/// the CRT overlay on top. Owns the single `DetectorEngine` plus the audio and
/// haptics sinks, and routes cross-screen navigation (pin/row → detail,
/// "detect from here" → detector tab).
struct RootView: View {
    @State private var engine = DetectorEngine()
    @State private var audio = GeigerAudio()
    @State private var haptics = Haptics()
    @State private var location = LocationService()
    @State private var heading = HeadingService()
    @State private var placesProvider = PlacesProvider()
    @State private var settings = AppSettings()
    @State private var tab: AppTab
    @State private var detectorPath: [Place] = []
    @State private var mapPath: [Place] = []
    @State private var nearbyPath: [Place]
    @State private var logPath: [Place] = []
    @State private var showAbout: Bool
    @State private var aboutIsFirstRun: Bool
    @State private var showBoot: Bool
    @State private var bootIsFirstRun: Bool
    /// True once `beginScanning()` has run (location started, with a real fix or the
    /// default-area fallback). Gates the live-ratings toggle so it never fetches at the
    /// default coordinate while the first-run About sheet is still up, before BEGIN SCAN.
    @State private var scanning = false

    enum AppTab: Hashable { case detector, map, nearby, log }

    init() {
        // Screenshot / UI-test affordance (never ships): launch with
        //   -RAD_SCREEN detector|map|nearby|detail
        // to open straight onto a given screen.
        var initialTab: AppTab = .detector
        var nearby: [Place] = []
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "RAD_SCREEN") {
        case "map": initialTab = .map
        case "nearby": initialTab = .nearby
        case "detail": initialTab = .nearby; nearby = [Places.all[0]]
        default: break
        }
        #endif
        _tab = State(initialValue: initialTab)
        _nearbyPath = State(initialValue: nearby)

        var seenAbout = UserDefaults.standard.bool(forKey: "didShowAbout")
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "RAD_SKIP_ABOUT") { seenAbout = true }
        #endif
        _showAbout = State(initialValue: !seenAbout)
        _aboutIsFirstRun = State(initialValue: !seenAbout)

        // Boot overlay: long RobCo sequence on first run, short on return. Sits
        // ABOVE the About sheet (see body's ZStack), so it always lands first.
        var skipBoot = false
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "RAD_SKIP_BOOT") { skipBoot = true }
        #endif
        _showBoot = State(initialValue: !skipBoot)
        _bootIsFirstRun = State(initialValue: !seenAbout)
    }

    var body: some View {
        ZStack {
        TabView(selection: $tab) {
            Tab("Detector", systemImage: "gauge.with.dots.needle.bottom.50percent", value: AppTab.detector) {
                NavigationStack(path: $detectorPath) {
                    DetectorScreen(engine: engine,
                                   placesProvider: placesProvider,
                                   onAbout: { aboutIsFirstRun = false; showAbout = true })
                        .detailRoute(engine: engine, onDetect: detect)
                }
            }
            Tab("Map", systemImage: "scope", value: AppTab.map) {
                NavigationStack(path: $mapPath) {
                    MapScreen(engine: engine,
                              onScan: { tab = .detector },
                              onRescan: { refresh(force: true) },
                              locationService: location,
                              placesProvider: placesProvider)
                        .detailRoute(engine: engine, onDetect: detect)
                }
            }
            Tab("Nearby", systemImage: "list.bullet", value: AppTab.nearby) {
                NavigationStack(path: $nearbyPath) {
                    NearbyScreen(engine: engine)
                        .detailRoute(engine: engine, onDetect: detect)
                }
            }
            Tab("Log", systemImage: "books.vertical", value: AppTab.log) {
                NavigationStack(path: $logPath) {
                    LogbookScreen(engine: engine)
                        .detailRoute(engine: engine, onDetect: detect)
                }
            }
        }
        .environment(settings)
        .tint(Theme.phosphor)
        // Honour Larger Text, but cap it so the pixel-instrument layouts hold.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .overlay(CRTOverlay())
        .onAppear {
            // Mirror the live-ratings preference before the first scan, so the
            // opening load already honours it (Google only when ON + configured).
            placesProvider.liveRatingsEnabled = settings.liveRatings
            engine.onClick = { [weak engine] volume in
                // Hotter signal = brighter click. `engine.rads` is readable here
                // (same module, MainActor) and biases the audio pitch upward.
                // Weak capture mirrors the display-link path — engine stores this
                // closure, so a strong capture would retain-cycle.
                guard let engine else { return }
                audio.click(volume, pitchBias: engine.rads)
                haptics.click(volume)
            }
            engine.onAudioToggle = { on in
                audio.setEnabled(on)
                haptics.setEnabled(on)
            }
            engine.onLock = { haptics.click(1.0) }
            engine.start()
            // Returning users start scanning straight away; first-run waits for the
            // About sheet's BEGIN SCAN so the location prompt arrives with context.
            if !showAbout { beginScanning() }
        }
        // Compass: point the phone and the detector aims itself.
        .onChange(of: heading.heading) { engine.deviceHeading = heading.heading }
        // Live-ratings kill switch. Keep the provider flag in sync always; only fetch
        // once scanning has begun — on first run the toggle lives in the About sheet
        // shown BEFORE BEGIN SCAN, and beginScanning()'s own load will honour the flag
        // at the real location. A deliberate flip must take effect immediately, so it
        // bypasses the 45s refetch floor (which refresh(force:) still honours) by
        // loading directly — ON fetches real Google data at once, OFF returns to sim.
        .onChange(of: settings.liveRatings) {
            placesProvider.liveRatingsEnabled = settings.liveRatings
            guard scanning else { return }
            location.markFetched()
            Task { await placesProvider.load(into: engine, near: location.coordinate, force: true) }
        }
        // Clock 1: drift the radar/needle as you move. Clock 2: gated rediscovery.
        .onChange(of: location.updates) {
            engine.updateUser(location.coordinate)
            refresh()
        }
        .onDisappear {
            engine.stop()
            location.stop()
            heading.stop()
        }
        // Gate the About sheet behind the boot sequence. A UIKit-backed .sheet
        // renders ABOVE any ZStack sibling regardless of zIndex, so presenting it
        // while `showBoot` is true would cover the RobCo cold-start. Holding the
        // sheet until boot finishes guarantees the boot always lands first.
        .sheet(isPresented: Binding(get: { showAbout && !showBoot },
                                    set: { showAbout = $0 })) {
            AboutSheet(isFirstRun: aboutIsFirstRun) {
                if aboutIsFirstRun { beginScanning(); aboutIsFirstRun = false }
                showAbout = false
            }
            // First run must be acknowledged — it's the disclaimer + permission primer.
            .interactiveDismissDisabled(aboutIsFirstRun)
        }

        // Boot overlay sits on top of everything (including the About sheet), so
        // the RobCo cold-start always plays first. Reveals the screen beneath on finish.
        if showBoot {
            BootSequenceView(isFirstRun: bootIsFirstRun) {
                withAnimation(.easeOut(duration: 0.3)) { showBoot = false }
            }
            .transition(.opacity)
            .zIndex(10)
        }
        }
    }

    /// Start location + compass (priming the permission prompt) and run the first scan.
    private func beginScanning() {
        UserDefaults.standard.set(true, forKey: "didShowAbout")
        scanning = true
        location.start()
        heading.start()
        refresh(force: true)
    }

    /// Run a rediscovery if the movement gate allows (or `force` for a manual RESCAN /
    /// the first load). Arms the gate before awaiting so one crossing never double-fires.
    private func refresh(force: Bool = false) {
        guard location.shouldRefetch(force: force) else { return }
        location.markFetched()
        Task { await placesProvider.load(into: engine, near: location.coordinate, force: force) }
    }

    /// "Detect from here": aim the engine at a place and jump to the detector.
    private func detect(_ place: Place) {
        engine.aim(at: place)
        tab = .detector
    }
}

extension View {
    /// Shared push destination: any `Place` value pushes the detail report.
    func detailRoute(engine: DetectorEngine, onDetect: @escaping (Place) -> Void) -> some View {
        navigationDestination(for: Place.self) { place in
            DetailScreen(place: place, engine: engine, onDetect: { onDetect(place) })
        }
    }
}

#Preview {
    RootView()
}
