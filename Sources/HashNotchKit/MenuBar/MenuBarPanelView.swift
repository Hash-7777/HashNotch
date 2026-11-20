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
            HStack {
                Text("HashNotch")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("All settings")
                .accessibilityLabel("All settings")
            }

            if !state.figures.isEmpty {
                HStack(spacing: 8) {
                    ForEach(state.figures, id: \.id) { figure in
                        tile(figure)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                caption("In the menu bar")
                ForEach(meters, id: \.id) { meter in
                    row(meter)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                caption("Refresh")
                refreshPicker
                Text(refreshDetail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 280)
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
                        .foregroundStyle(chosen ? theme.onAccent : Color.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .background(
                            Capsule(style: .continuous)
                                .fill(chosen ? theme.accent : Color.clear)
                        )
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(refresh.label)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.08)))
        .animation(.easeOut(duration: 0.15), value: settings.menuBarRefresh)
    }

    private func caption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(.secondary)
    }

    /// One figure, larger: its glyph, its number, its name.
    private func tile(_ figure: MenuBarFigure) -> some View {
        let level: ReadingLevel = figure.reading?.isHigh == true ? .danger : .normal
        return VStack(spacing: 5) {
            MenuBarGlyphView(figure.glyph, size: 15, color: theme.color(for: level))
            Text(figure.text)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(level == .danger ? Theme.danger : Color.white)
            Text(figure.title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(figure.reading?.spoken ?? "\(figure.title), no reading yet")
    }

    /// A figure's switch. A figure whose indicator is off shows its switch off
    /// and greyed, and says why, rather than a switch that does nothing.
    private func row(_ meter: MenuBarMeter) -> some View {
        let indicatorOn = settings.isEnabled(meter.id)
        return HStack(spacing: 9) {
            MenuBarGlyphView(meter.glyph, size: 12, color: indicatorOn ? theme.accent : .white.opacity(0.3))
            VStack(alignment: .leading, spacing: 1) {
                Text(meter.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(indicatorOn ? Color.primary : Color.secondary)
                if !indicatorOn {
                    Text("Its indicator is off")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
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
                .fill(configuration.isOn ? accent : Color.white.opacity(0.16))
                .frame(width: 30, height: 18)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
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
