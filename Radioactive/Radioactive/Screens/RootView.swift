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
    @State private var tab: AppTab
    @State private var detectorPath: [Place] = []
    @State private var mapPath: [Place] = []
    @State private var nearbyPath: [Place]
    @State private var showAbout: Bool
    @State private var aboutIsFirstRun: Bool

    enum AppTab: Hashable { case detector, map, nearby }

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
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Detector", systemImage: "gauge.with.dots.needle.bottom.50percent", value: AppTab.detector) {
                NavigationStack(path: $detectorPath) {
                    DetectorScreen(engine: engine,
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
        }
        .tint(Theme.phosphor)
        // Honour Larger Text, but cap it so the pixel-instrument layouts hold.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .overlay(CRTOverlay())
        .onAppear {
            engine.onClick = { volume in
                audio.click(volume)
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
        .sheet(isPresented: $showAbout) {
            AboutSheet(isFirstRun: aboutIsFirstRun) {
                if aboutIsFirstRun { beginScanning(); aboutIsFirstRun = false }
                showAbout = false
            }
            // First run must be acknowledged — it's the disclaimer + permission primer.
            .interactiveDismissDisabled(aboutIsFirstRun)
        }
    }

    /// Start location + compass (priming the permission prompt) and run the first scan.
    private func beginScanning() {
        UserDefaults.standard.set(true, forKey: "didShowAbout")
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
