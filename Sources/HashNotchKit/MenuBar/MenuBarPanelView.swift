import SwiftUI

/// The figures the panel shows, larger. The item keeps one of these for its
/// panel and hands it figures only while the panel is open.
@MainActor
public final class MenuBarState: ObservableObject {
    @Published public package(set) var figures: [MenuBarFigure] = []
    public init() {}
}

/// What opens from the menu bar item: the figures at a size you can read, and
/// the menu bar's own preferences — which figures, and how often.
///
/// It draws no surface of its own: `MenuBarPanel` puts it on the app's glass,
/// the same surface every other window here is made of.
public struct MenuBarPanelView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var state: MenuBarState
    let meters: [MenuBarMeter]
    let openSettings: () -> Void
    /// The chosen rate's pill slides between rates rather than jumping.
    @Namespace private var rateSelection

    public init(
        settings: SettingsStore,
        state: MenuBarState,
        meters: [MenuBarMeter],
        openSettings: @escaping () -> Void
    ) {
        self.settings = settings
        self.state = state
        self.meters = meters
        self.openSettings = openSettings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("HashNotch")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                Spacer(minLength: 8)
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white.opacity(0.7))
                .help("All settings")
                .accessibilityLabel("All settings")
            }

            if !state.figures.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(state.figures.enumerated()), id: \.element.id) { index, figure in
                        tile(figure).modifier(ArrivesInTurn(order: 1 + index))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                caption("In the menu bar")
                VStack(spacing: 0) {
                    ForEach(Array(meters.enumerated()), id: \.element.id) { index, meter in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.white.opacity(0.07))
                                .frame(height: 0.5)
                                .padding(.leading, 33)
                        }
                        row(meter)
                    }
                }
                .background(card)
            }
            .modifier(ArrivesInTurn(order: 4))

            VStack(alignment: .leading, spacing: 7) {
                caption("Refresh")
                refreshPicker
                Text(refreshDetail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
            .modifier(ArrivesInTurn(order: 5))
        }
        .padding(14)
        .frame(width: 280)
    }

    /// The faint pane the tiles and the switches sit on: a little lighter than
    /// the glass, with an edge just visible, so they read as set into it.
    ///
    /// Raised a little: lit along its top edge and resting on a soft shadow,
    /// so the tiles and the switches read as standing on the glass rather
    /// than printed on it.
    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return shape
            .fill(Color.white.opacity(0.065))
            .overlay(shape.strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.16), Color.white.opacity(0.03)],
                    startPoint: .top, endPoint: .bottom),
                lineWidth: 0.5))
            .background(OuterShadow(shape: shape, color: .black.opacity(0.32), radius: 3, y: 2))
    }

    /// The app's own colours: its accent for anything on or chosen, its red
    /// for a reading running high — the same two the notch panel uses, so the
    /// two read as one app and a new accent reaches both at once.
    ///
    /// The controls here are drawn rather than taken from the system, and that
    /// is because of where they live. This panel never becomes the key window —
    /// that is what keeps it from taking focus from the app in use — and the
    /// system draws its own switches and segmented controls in a window that is
    /// not key in grey, whatever accent they are given. Drawn, they wear the
    /// accent whatever the panel's state.
    private var theme: Theme { Theme.default.tinted(settings.accent.color) }

    private var refreshPicker: some View {
        HStack(spacing: 2) {
            ForEach(MenuBarRefresh.allCases, id: \.self) { refresh in
                let chosen = settings.menuBarRefresh == refresh
                Button {
                    settings.menuBarRefresh = refresh
                } label: {
                    Text(refresh.shortLabel)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(chosen ? theme.onAccent : Color.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background {
                            if chosen {
                                Capsule(style: .continuous)
                                    .fill(theme.accent)
                                    .overlay(Capsule(style: .continuous).strokeBorder(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.35), Color.white.opacity(0)],
                                            startPoint: .top, endPoint: .bottom),
                                        lineWidth: 0.5))
                                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "chosen", in: rateSelection)
                            }
                        }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(refresh.label)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5))
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: settings.menuBarRefresh)
    }

    private func caption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .kerning(0.9)
            .foregroundStyle(Color.white.opacity(0.4))
            .padding(.leading, 2)
    }

    /// One figure, larger: its glyph, its number, its name.
    private func tile(_ figure: MenuBarFigure) -> some View {
        let level: ReadingLevel = figure.reading?.isHigh == true ? .danger : .normal
        return VStack(spacing: 4) {
            MenuBarGlyphView(figure.glyph, size: 14, color: theme.color(for: level))
                .padding(.bottom, 2)
            Text(figure.text)
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(level == .danger ? Theme.danger : Color.white)
                .rollingDigits()
                .figureAnimation(.spring(response: 0.35, dampingFraction: 0.9), value: figure.text)
            Text(figure.title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(figure.reading?.spoken ?? "\(figure.title), no reading yet")
    }

    /// A figure's switch. A figure whose indicator is off shows its switch off
    /// and greyed, and says why, rather than a switch that does nothing.
    private func row(_ meter: MenuBarMeter) -> some View {
        let indicatorOn = settings.isEnabled(meter.id)
        return HStack(spacing: 10) {
            MenuBarGlyphView(meter.glyph, size: 13, color: indicatorOn ? theme.accent : .white.opacity(0.3))
            VStack(alignment: .leading, spacing: 1) {
                Text(meter.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(indicatorOn ? Color.white.opacity(0.9) : Color.white.opacity(0.45))
                if !indicatorOn {
                    Text("Its indicator is off")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            Spacer(minLength: 8)
            Toggle(meter.title, isOn: Binding(
                get: { indicatorOn && settings.isInMenuBar(meter.id) },
                set: { settings.setInMenuBar(meter.id, $0) }
            ))
            .toggleStyle(PanelSwitchStyle(accent: theme.accent))
            .disabled(!indicatorOn)
            .accessibilityLabel(meter.title)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var refreshDetail: String {
        MenuBarWording.refreshDetail(
            refresh: settings.menuBarRefresh, batterySaver: settings.batterySaver)
    }
}

/// What the preferences say about the refresh. Pure, so the checks can hold it
/// to the rate the clock actually runs at.
package enum MenuBarWording {
    package static func refreshDetail(refresh: MenuBarRefresh, batterySaver: Bool) -> String {
        let seconds = Int(MenuBarPlan.interval(refresh: refresh, samplingScale: batterySaver ? 2 : 1))
        let rate = seconds == 1 ? "every second" : "every \(seconds) seconds"
        let saver = batterySaver ? " Battery saver doubles the time you chose." : ""
        return "Read \(rate), only while something is in the menu bar.\(saver)"
    }
}

/// A switch drawn in the app's accent. See `MenuBarPanelView.theme` for why it
/// is drawn rather than the system's.
struct PanelSwitchStyle: ToggleStyle {
    let accent: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule(style: .continuous)
                .fill(configuration.isOn ? accent : Color.white.opacity(0.14))
                .frame(width: 30, height: 18)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                        .frame(width: 14, height: 14)
                        .padding(2)
                }
                .opacity(isEnabled ? 1 : 0.4)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

/// The panel's contents arriving one after another as it opens, each rising a
/// few points into place, a beat behind the one before. Closing, they all go
/// at once with the panel, since nothing about leaving needs an order.
private struct ArrivesInTurn: ViewModifier {
    let order: Int
    @Environment(\.menuBarPanelOpen) private var open
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(open ? 1 : 0)
            .offset(y: open || reduceMotion ? 0 : 6)
            .animation(
                open
                    ? .spring(response: 0.38, dampingFraction: 0.86).delay(0.03 * Double(order))
                    : .easeIn(duration: 0.1),
                value: open)
    }
}
