import SwiftUI
import Foundation

/// What this Mac's macOS can comfortably do, decided once at launch.
///
/// Not a feature switch — every version runs every feature. This is about how
/// hard the app is willing to work the compositor. The island animates a
/// blurred, shadowed, continuously resizing overlay window above everything
/// else on screen, and the cost of that is paid by the window server, which got
/// materially better at it over these releases. Asking Monterey for the same
/// work Tahoe absorbs is how an app ends up feeling heavy on exactly the
/// machines with the least headroom.
///
/// So the newest systems get the full treatment and older ones get the same
/// design with less to composite. Nothing is missing; it is lighter.
public enum SystemGeneration: Sendable {
    /// macOS 12 Monterey — the oldest supported.
    case monterey
    /// macOS 13 Ventura and 14 Sonoma.
    case modern
    /// macOS 15 Sequoia and 26 Tahoe.
    case latest

    public static let current: SystemGeneration = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        switch version.majorVersion {
        case ..<13: return .monterey
        case 13...14: return .modern
        default: return .latest
        }
    }()

    /// How far to scale animation durations. Slightly longer on older systems:
    /// a spring that cannot keep up looks like stutter, and the same spring
    /// given more time to travel looks deliberate.
    public var motionScale: Double {
        switch self {
        case .monterey: return 1.15
        case .modern: return 1.0
        case .latest: return 1.0
        }
    }

    // The panel's shadow used to be decided here — dropped on Monterey for
    // cost, softened elsewhere. It is now drawn on no system at all, so there
    // is nothing left to decide: a shadow says an object floats above a
    // surface, and this one is pretending to be part of the hardware.
    //
    // Which leaves timing as the only thing this type still scales, and that is
    // enough for it to keep earning its place.

    /// Every generation, so the checks can require the rules to hold for all of
    /// them rather than only for whichever Mac happens to be running them.
    package static let allCasesForChecks: [SystemGeneration] = [.monterey, .modern, .latest]

    /// Human-readable, for the Privacy page and for support.
    public var name: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion)"
    }
}

/// Modifiers that use a newer system's polish where it exists, and quietly do
/// without it where it does not.
///
/// The app supports several macOS versions and the newest ones have niceties
/// the older ones lack. Scattering `if #available` through the layouts would
/// bury the design under version checks — a view's body should read as what it
/// looks like. So each one is wrapped once, here, named for its intent, and the
/// call sites stay legible.
///
/// The rule for what belongs in this file: **only things whose absence costs
/// nothing but polish.** Digits that cross-fade instead of rolling, a scrollbar
/// that shows — an older Mac gets a slightly plainer version of the same app.
/// Anything an older system genuinely cannot do is handled where it lives and
/// says so out loud, the way "Open at Login" does.
public extension View {
    /// Rolls digits like an odometer when the number changes, on systems that
    /// can. Elsewhere the number simply changes, which is what it always did.
    ///
    /// Used on every live readout in the app — speeds, percentages, token
    /// counts, temperatures — which is why it is worth a name of its own
    /// rather than fifteen copies of the same availability check.
    @ViewBuilder
    func rollingDigits() -> some View {
        if #available(macOS 13, *) {
            self.contentTransition(.numericText())
        } else {
            self
        }
    }
}
