import Foundation
import Combine

/// The app's one item in the menu bar, as far as the controller is concerned.
///
/// A protocol so the checks can watch what the controller does without putting
/// anything in the real menu bar; the app uses `StatusBarItem`.
@MainActor
public protocol MenuBarItem: AnyObject {
    /// Draw these figures, one column each, in this order.
    func display(_ figures: [MenuBarFigure])
    /// Take it out of the menu bar for good.
    func remove()
}

/// The figures the menu bar is showing now, for the popover to show larger.
@MainActor
public final class MenuBarState: ObservableObject {
    @Published public package(set) var figures: [MenuBarFigure] = []
    public init() {}
}

/// Puts the figures somebody chose into one item in the menu bar, reads them on
/// one clock while it is there, and takes it out again.
///
/// ONE item, not one per figure. Each item in the menu bar is a place macOS
/// arranges on its own terms, and on a Mac with a notch the ones that do not
/// fit beside it are hidden behind it without a word. Several small figures
/// stacked in one item take a fraction of the room four items would, and they
/// arrive and leave together.
///
/// Which figures run is one pure rule, `MenuBarPlan.wanted`, applied whenever
/// anything it reads changes. Reading happens on one utility queue, never on
/// the main thread — the temperature reader asks the hardware about dozens of
/// sensors — and the item is redrawn only when what it says has changed.
@MainActor
public final class MenuBarController {
    public let state = MenuBarState()

    private let settings: SettingsStore
    private let meters: [MenuBarMeter]
    private let makeItem: (MenuBarState) -> MenuBarItem
    private let queue = DispatchQueue(label: "com.hashnotch.menubar", qos: .utility)
    private var item: MenuBarItem?
    private var timer: DispatchSourceTimer?
    /// The figures the running clock reads, in order.
    private var running: [String] = []
    private var isPaused = false
    private var cancellables = Set<AnyCancellable>()
    /// Bumped every time the clock starts, so an answer still on its way from
    /// a clock that has since been stopped is recognised and dropped.
    private var generation = 0

    public init(
        settings: SettingsStore,
        meters: [MenuBarMeter],
        makeItem: @escaping (MenuBarState) -> MenuBarItem
    ) {
        self.settings = settings
        self.meters = meters
        self.makeItem = makeItem
    }

    /// Watch the settings this depends on, and apply them once now.
    ///
    /// Each change is applied a hop later, because `@Published` announces a
    /// change before the store holds the new value.
    public func begin() {
        let later: (@escaping @MainActor () -> Void) -> Void = { work in
            DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
        }
        settings.$features.dropFirst()
            .sink { [weak self] _ in later { self?.sync() } }
            .store(in: &cancellables)
        settings.$menuBarFigures.dropFirst()
            .sink { [weak self] _ in later { self?.sync() } }
            .store(in: &cancellables)
        settings.$hasAcceptedReading.dropFirst()
            .sink { [weak self] _ in later { self?.sync() } }
            .store(in: &cancellables)
        // How often the clock runs is fixed when it starts, so a new rate, or
        // battery saver, means starting it over. The item stays where it is.
        settings.$menuBarRefresh.dropFirst().removeDuplicates()
            .sink { [weak self] _ in later { self?.restartClock() } }
            .store(in: &cancellables)
        settings.$batterySaver.dropFirst().removeDuplicates()
            .sink { [weak self] _ in later { self?.restartClock() } }
            .store(in: &cancellables)
        sync()
    }

    /// The screen went away, or came back. Nothing is read while nobody can
    /// see it, and the item leaves the menu bar with the island.
    public func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        sync()
    }

    /// Bring the menu bar in line with what should be there.
    public func sync() {
        let wanted = MenuBarPlan.wanted(
            meters: meters.map(\.id),
            shown: Set(settings.menuBarFigures),
            isEnabled: settings.isEnabled,
            hasConsent: settings.hasAcceptedReading,
            isPaused: isPaused
        )
        guard !wanted.isEmpty else {
            if item != nil { stopAll() }
            return
        }
        if item != nil, wanted == running { return }
        if item == nil { item = makeItem(state) }
        running = wanted
        startClock()
    }

    /// Take the item out and stop reading.
    public func stopAll() {
        stopClock()
        running = []
        state.figures = []
        item?.remove()
        item = nil
    }

    /// The figures currently being read. Package-visible so the checks can
    /// prove that switching one off really stops it.
    package var runningIDs: [String] { item == nil ? [] : running }

    /// Whether the item is in the menu bar at all.
    package var isShown: Bool { item != nil }

    private func startClock() {
        stopClock()
        generation &+= 1
        let token = generation
        let chosen = running.compactMap { id in meters.first { $0.id == id } }
        // Fresh readers each time, so nothing compares against a reading
        // taken before the clock last stopped.
        let readers = chosen.map { $0.makeReader() }

        // Shown straight away so the item does not appear empty and then grow
        // when the first reading lands: what a figure already said is kept,
        // and a new one is a dash until it has read something.
        let previous = state.figures
        let placeholder = chosen.map { meter in
            MenuBarFigure(meter: meter, reading: previous.first { $0.id == meter.id }?.reading)
        }
        show(placeholder)

        let interval = MenuBarPlan.interval(
            refresh: settings.menuBarRefresh, samplingScale: settings.samplingScale)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // A tenth of the interval of slack lets macOS fold these wakeups in
        // with others it already has.
        //
        // The first reading comes half a second in rather than at once, so a
        // reader that measures a change — the processor's — has something to
        // measure it over, and the first figure it gives is a real one.
        timer.schedule(
            deadline: .now() + 0.5,
            repeating: interval,
            leeway: .milliseconds(Int(interval * 100))
        )
        timer.setEventHandler { [weak self] in
            let readings = readers.map { $0() }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == token else { return }
                    self.show(zip(chosen, readings).map { MenuBarFigure(meter: $0, reading: $1) })
                }
            }
        }
        self.timer = timer
        timer.resume()
    }

    private func stopClock() {
        timer?.cancel()
        timer = nil
        generation &+= 1
    }

    private func restartClock() {
        guard item != nil, !running.isEmpty else { return }
        startClock()
    }

    private func show(_ figures: [MenuBarFigure]) {
        guard figures != state.figures else { return }
        state.figures = figures
        item?.display(figures)
    }
}
