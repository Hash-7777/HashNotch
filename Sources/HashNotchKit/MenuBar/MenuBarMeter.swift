import Foundation

/// What one figure in the menu bar says at a moment.
public struct MenuBarReading: Equatable, Sendable {
    /// What is drawn: "23%", "52°".
    public let text: String
    /// What is read aloud and shown on hover: "CPU 23%".
    public let spoken: String
    /// At or past the point the panel turns the same figure red.
    public let isHigh: Bool

    public init(text: String, spoken: String, isHigh: Bool) {
        self.text = text
        self.spoken = spoken
        self.isHigh = isHigh
    }
}

/// A figure a feature offers for the menu bar.
///
/// The panel's readouts sample only while the panel is open, which is what
/// keeps the app quiet the rest of the time. A figure in the menu bar is on
/// screen all day, so it cannot work that way: it has its own reader, on the
/// menu bar's own clock, and it runs only while it is actually shown. That is
/// why this is a separate thing from the feature's monitor rather than a second
/// view of it — the two have different reasons to be awake.
///
/// The core never learns what any figure means. It is handed a name, a glyph,
/// and a way to build a reader, which is the same arrangement every feature
/// already has with the panel.
public struct MenuBarMeter: Sendable {
    /// The feature's own id. A figure belongs to its indicator: switching the
    /// indicator off takes the figure out of the menu bar as well.
    public let id: String
    /// The short name, as the popover and the settings page show it.
    public let title: String
    /// One plain sentence: what the figure is.
    public let summary: String
    /// The word above its number in the menu bar: "CPU", "TEMP". A word, not a
    /// picture — at the size the menu bar allows, a drawing of a graphics card
    /// or a memory stick has to be guessed at, and a word does not.
    public let label: String
    /// Its picture, where there is room for one: the popover.
    public let glyph: MenuBarGlyph
    /// The widest thing it can ever say, so its column in the menu bar is
    /// sized once and nothing beside it moves as the figure changes.
    public let widestText: String
    /// Builds a fresh reader. Called every time the menu bar starts reading,
    /// so a reader that compares one reading with the last starts with no
    /// baseline rather than one from before it was stopped.
    ///
    /// A reader is only ever called on one serial queue, never on the main
    /// thread, and never twice at once.
    public let makeReader: @Sendable () -> @Sendable () -> MenuBarReading?

    public init(
        id: String,
        title: String,
        summary: String,
        label: String,
        glyph: MenuBarGlyph,
        widestText: String,
        makeReader: @escaping @Sendable () -> @Sendable () -> MenuBarReading?
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.label = label
        self.glyph = glyph
        self.widestText = widestText
        self.makeReader = makeReader
    }
}

/// One column of the menu bar item: which figure, and what it says now.
public struct MenuBarFigure: Equatable, Sendable {
    public let id: String
    public let title: String
    public let label: String
    public let glyph: MenuBarGlyph
    public let widestText: String
    /// Nil until it has read something, drawn as a dash.
    public let reading: MenuBarReading?

    public init(meter: MenuBarMeter, reading: MenuBarReading?) {
        self.id = meter.id
        self.title = meter.title
        self.label = meter.label
        self.glyph = meter.glyph
        self.widestText = meter.widestText
        self.reading = reading
    }

    /// What the column shows.
    public var text: String { reading?.text ?? "—" }
}

/// How often the figures in the menu bar are read.
///
/// Two seconds by default: often enough that the figure is about now, and a
/// figure that ticks every second all day draws the eye to the corner of the
/// screen without having anything new to say.
public enum MenuBarRefresh: String, Codable, CaseIterable, Sendable {
    case oneSecond
    case twoSeconds
    case threeSeconds
    case fiveSeconds
    case tenSeconds

    public nonisolated static let `default`: MenuBarRefresh = .twoSeconds

    public var seconds: TimeInterval {
        switch self {
        case .oneSecond: return 1
        case .twoSeconds: return 2
        case .threeSeconds: return 3
        case .fiveSeconds: return 5
        case .tenSeconds: return 10
        }
    }

    /// The short form, for a control with five of these side by side.
    public var shortLabel: String { "\(Int(seconds))s" }

    public var label: String {
        self == .oneSecond ? "Every second" : "Every \(Int(seconds)) seconds"
    }
}

/// How figures are worded, in one place so every figure reads the same way and
/// the checks can hold it.
public enum MenuBarText {
    /// A share of the whole as a whole percentage: "23%".
    public static func percent(_ share: Double) -> String {
        let clamped = min(1, max(0, share.isFinite ? share : 0))
        return "\(Int((clamped * 100).rounded()))%"
    }

    /// A temperature in whole degrees: "52°".
    public static func degrees(_ celsius: Double) -> String {
        "\(Int(celsius.rounded()))°"
    }
}

/// Which figures should be read right now. Pure, so the rule can be held by the
/// checks rather than trusted to the controller that acts on it.
public enum MenuBarPlan {
    /// The ids to show, in the order the meters were offered.
    ///
    /// A figure runs only if every one of these holds: somebody has agreed to
    /// the app reading anything at all, the screen is on, its indicator is
    /// switched on, and it has been put in the menu bar. Switching an indicator
    /// off means off, here as everywhere — it would be a strange switch that
    /// stopped a reading in the panel and left the same reading running in the
    /// menu bar.
    public static func wanted(
        meters: [String],
        shown: Set<String>,
        isEnabled: (String) -> Bool,
        hasConsent: Bool,
        isPaused: Bool
    ) -> [String] {
        guard hasConsent, !isPaused else { return [] }
        return meters.filter { shown.contains($0) && isEnabled($0) }
    }

    /// The order the figures stand in, left to right: the two processors,
    /// then memory, then temperature. Fixed rather than following the panel,
    /// because the panel's order is about what is read rather than glanced at,
    /// and in a row of four small numbers the pair you compare should sit
    /// together. Anything not named goes after these, in the order offered.
    public static let order = ["cpu", "gpu", "memory", "thermal"]

    /// `meters` arranged into `order`.
    public static func arranged(_ meters: [MenuBarMeter]) -> [MenuBarMeter] {
        meters.enumerated().sorted { lhs, rhs in
            let l = order.firstIndex(of: lhs.element.id) ?? order.count + lhs.offset
            let r = order.firstIndex(of: rhs.element.id) ?? order.count + rhs.offset
            return l < r
        }.map(\.element)
    }

    /// The interval the clock actually runs at: the chosen refresh, doubled by
    /// battery saver like every other reading in the app.
    public static func interval(refresh: MenuBarRefresh, samplingScale: Double) -> TimeInterval {
        refresh.seconds * samplingScale
    }
}
