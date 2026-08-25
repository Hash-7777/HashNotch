import Foundation
import HashNotchKit

/// One temperature sensor reading.
public struct TempSensor: Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let celsius: Double
}

/// Reports temperatures for the notch HUD.
///
/// Primary source is the real on-die sensors via `AppleSiliconThermal`; the
/// public `ProcessInfo.thermalState` is always tracked too, both as a colour
/// signal and as a fallback label when sensor reads aren't available. Swapping
/// the sensor source later touches only this file — the feature, view, and core
/// stay put.
@MainActor
public final class ThermalMonitor: ObservableObject {
    @Published public private(set) var state: ProcessInfo.ThermalState = .nominal
    @Published public private(set) var sensors: [TempSensor] = []
    @Published public private(set) var hottestCelsius: Double?

    /// Where the readings come from: the HID event system if this Mac has it,
    /// and the SMC otherwise.
    ///
    /// Two readers rather than one because no single interface covers every
    /// Mac. The HID one gives sensors with names — `PMU tdie1`, `NAND CH0 temp`
    /// — which is why it is asked first, but it exists only on Apple Silicon,
    /// so on an Intel Mac it resolves nothing and this feature used to have
    /// nothing to show at all. The SMC has been on every Mac for twenty years
    /// and is still on this one; its names are four-character keys rather than
    /// words, which is the only reason it is second.
    ///
    /// Chosen once, at init, because which interface a Mac has does not change
    /// while it is running.
    private let sensorReader: ThermalSensorReader? =
        AppleSiliconThermal() ?? SMCThermal()
    private var sampler: VisibleSampler?
    private var observer: NSObjectProtocol?
    /// Reading the sensors means one IOKit round trip per sensor, and Apple
    /// Silicon reports dozens of them. That is far too much to do on the thread
    /// that is drawing the panel — which is exactly where it used to happen,
    /// every three seconds, while the panel was open and animating.
    private let queue = DispatchQueue(label: "com.hashnotch.thermal", qos: .utility)
    private var inFlight = false

    public init() {}

    public func start(visibility: PanelVisibility, scale: Double = 1) {
        state = ProcessInfo.processInfo.thermalState
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.state = ProcessInfo.processInfo.thermalState
            }
        }

        // Sensor reads only matter while their numbers are on screen. The
        // system's own thermal-state notification above still arrives either way.
        sampler = VisibleSampler(interval: 3.0 * scale, visibility: visibility) { [weak self] in
            self?.refresh()
        }
        sampler?.start()
    }

    public func stop() {
        sampler?.stop()
        sampler = nil
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    /// Read off-main, publish on main. Skips if a previous read is still
    /// running, so a slow one never stacks up behind itself.
    private func refresh() {
        guard !inFlight, let reader = sensorReader else { return }
        inFlight = true
        queue.async { [weak self] in
            let grouped = Self.grouped(reader.read())
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inFlight = false
                self.apply(grouped)
            }
        }
    }

    /// Group cryptic sensor names (e.g. "PMU tdie7") into friendly categories,
    /// keeping the hottest reading in each, in a FIXED order.
    ///
    /// The order used to be by temperature, hottest first, and that is a list
    /// that rearranges itself while somebody is reading it. This Mac reports
    /// thirty-five raw sensors that fold into three rows, and the moment the
    /// drive passed the processor the two swapped places — so a glance at "the
    /// second row" meant something different from one minute to the next. A
    /// panel's rows should be where they were last time.
    ///
    /// Which rows exist still depends on the machine, and that part is not a
    /// bug: sensor names are model-specific, so a Mac with no separate graphics
    /// or drive sensor simply has no such row, and one whose sensors match
    /// nothing here reports them all as System. On a Mac with no on-die sensors
    /// at all — every Intel one, since this reads an Apple Silicon interface —
    /// there are no rows and the panel shows the coarse pressure word instead,
    /// which is the honest answer rather than an empty section.
    ///
    /// Pure and static so it runs on the reading queue rather than the main
    /// thread, and so the checks can pin the grouping without any hardware.
    ///
    /// `nonisolated` is the part that makes that true rather than merely
    /// intended. Being `static` inside a `@MainActor` class does not exempt it:
    /// it inherited the class's isolation, so `refresh()` calling it from the
    /// sampling queue was reaching main-actor code off the main thread — the
    /// exact thing moving this work off the main thread was meant to avoid, and
    /// an error rather than a warning under Swift 6. It is pure, so the fix is
    /// to say so.
    package nonisolated static func grouped(
        _ readings: [(name: String, celsius: Double)]
    ) -> [TempSensor] {
        var byCategory: [String: Double] = [:]
        for reading in readings {
            let category = friendlyCategory(for: reading.name)
            byCategory[category] = max(byCategory[category] ?? 0, reading.celsius)
        }
        return byCategory
            .map { TempSensor(name: $0.key, celsius: $0.value) }
            .sorted { left, right in
                let l = categoryOrder.firstIndex(of: left.name) ?? categoryOrder.count
                let r = categoryOrder.firstIndex(of: right.name) ?? categoryOrder.count
                return l == r ? left.name < right.name : l < r
            }
    }

    /// What an SMC key is about, from the letter after the T.
    ///
    /// Only applied to something shaped like an SMC key — four characters
    /// beginning with T — so a descriptive name from the other reader is never
    /// mistaken for one. Anything unrecognised is left to the word rules and
    /// then to System, which is the honest answer for a sensor nobody can name.
    package nonisolated static func smcCategory(for rawName: String) -> String? {
        let characters = Array(rawName)
        guard characters.count == 4, characters[0] == "T" else { return nil }
        switch characters[1] {
        case "B": return "Battery"
        case "C", "P": return "Processor"
        case "G": return "Graphics"
        case "H": return "Drive"
        default: return nil
        }
    }

    /// The order the categories are shown in, biggest thing first.
    ///
    /// Not alphabetical and not by temperature: it reads down the machine, from
    /// the chip doing the work to the parts around it. Anything unrecognised
    /// sorts to the end by name, so an unfamiliar Mac still produces the same
    /// order twice running.
    package nonisolated static let categoryOrder = [
        "Processor", "Graphics", "Drive", "Battery", "System",
    ]

    private func apply(_ newSensors: [TempSensor]) {
        // Publish only on change so steady temperatures cause no redraws.
        if newSensors != sensors { sensors = newSensors }
        let newHottest = newSensors.first?.celsius
        if newHottest != hottestCelsius { hottestCelsius = newHottest }
    }

    /// Maps a raw sensor name to a friendly, human category.
    ///
    /// `nonisolated` for the same reason as `grouped`, which is its only
    /// caller: it is string matching with no state behind it, and it runs on
    /// the sampling queue.
    package nonisolated static func friendlyCategory(for rawName: String) -> String {
        // A key off the SMC is four characters and says what it is in the
        // second one, by a convention that has held across every Mac that has
        // had one. Matched before the word rules below, because "TB0T" contains
        // none of those words and would otherwise land in System along with
        // every other sensor on an Intel Mac — one row called System, which is
        // barely better than nothing.
        if let category = smcCategory(for: rawName) { return category }
        let name = rawName.lowercased()
        if name.contains("gas gauge") || name.contains("batt") { return "Battery" }
        if name.contains("gpu") { return "Graphics" }
        if name.contains("cpu") || name.contains("acc") { return "Processor" }
        // "Drive", not "Storage": the panel has a Storage section of its own for
        // how full the disk is, and two unrelated numbers under one word is a
        // readout that has to be worked out rather than glanced at.
        if name.contains("ssd") || name.contains("nand") || name.contains("flash") { return "Drive" }
        // PMU / SOC / die / calibration sensors are the main chip — call it the processor.
        if name.contains("soc") || name.contains("pmu") || name.contains("tdie")
            || name.contains("tcal") || name.contains("tdev") || name.contains("die") {
            return "Processor"
        }
        if name.contains("air") || name.contains("ambient") || name.contains("prox") { return "System" }
        return "System"
    }

    /// Coarse thermal-pressure word (also drives the tint colour).
    public var pressureLabel: String {
        switch state {
        case .nominal: return "Cool"
        case .fair: return "Fair"
        case .serious: return "Warm"
        case .critical: return "Hot"
        @unknown default: return "—"
        }
    }
}

/// What the monitor needs of a source of temperatures, so it can hold whichever
/// one this Mac has without knowing which that is.
protocol ThermalSensorReader: Sendable {
    func read() -> [(name: String, celsius: Double)]
}

extension AppleSiliconThermal: ThermalSensorReader {}
extension SMCThermal: ThermalSensorReader {}
