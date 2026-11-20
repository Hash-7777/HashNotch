import SwiftUI

/// The figures the popover shows, larger. The item keeps one of these for its
/// popover and hands it figures only while the popover is open.
@MainActor
public final class MenuBarState: ObservableObject {
    @Published public package(set) var figures: [MenuBarFigure] = []
    public init() {}
}

/// What opens from the menu bar item: the figures at a size you can read, and
/// the menu bar's own preferences — which figures, and how often.
///
/// The popover's surface is the system's own, which is glass on a macOS that
/// draws glass and frosted on one that does not, so this draws no background
/// of its own and nothing here can disagree with it.
public struct MenuBarPopoverView: View {
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
                Picker("", selection: $settings.menuBarRefresh) {
                    ForEach(MenuBarRefresh.allCases, id: \.self) { refresh in
                        Text(refresh.shortLabel).tag(refresh)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(refreshDetail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 280)
        .tint(settings.accent.color)
    }

    private func caption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(.secondary)
    }

    /// One figure, larger: its glyph, its number, its name.
    private func tile(_ figure: MenuBarFigure) -> some View {
        let high = figure.reading?.isHigh == true
        return VStack(spacing: 5) {
            MenuBarGlyphView(figure.glyph, size: 15, color: high ? .red : .primary.opacity(0.85))
            Text(figure.text)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(high ? Color.red : Color.primary)
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
            MenuBarGlyphView(meter.glyph, size: 12, color: .primary.opacity(indicatorOn ? 0.8 : 0.35))
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
            Toggle("", isOn: Binding(
                get: { indicatorOn && settings.isInMenuBar(meter.id) },
                set: { settings.setInMenuBar(meter.id, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(!indicatorOn)
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
