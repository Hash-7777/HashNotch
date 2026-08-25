import AppKit
import SwiftUI
import HashNotchKit

/// Setting up the agent side of the notch, without a terminal.
///
/// Everything on this page was previously done by hand: a shell script somebody
/// had to find and run, and a text file somebody had to create and fill in. Both
/// were documented, and being documented is not the same as being usable —
/// anybody who does not already live in a terminal was simply shut out of the
/// feature.
///
/// Two things are offered and nothing else: connect it, and choose what you
/// want to be stopped for.
struct ActivitiesSettingsView: View {
    @ObservedObject var monitor: ActivitiesMonitor
    let theme: Theme

    @State private var installing = false
    @State private var result: String?
    @State private var failed = false
    @State private var tools: [String] = AskTools.read()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(
                "Agents",
                detail: "Let an AI tool talk to the notch, and answer it from there."
            )

            SettingCard {
                SettingRow(connectionTitle, detail: connectionDetail) {
                    Button(installing ? "Working…" : connectionAction) { install() }
                        .disabled(installing || HookInstallation.installerURL == nil)
                }

                if let result {
                    Text(result)
                        .font(.system(size: 10))
                        .foregroundStyle(failed ? Color.orange : theme.subtitleColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if HookInstallation.installerURL == nil {
                    Text("Only a HashNotch that has been moved to Applications can do this — a copy run straight from a build folder has no installer inside it.")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.subtitleColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingCard {
                SettingGroupLabel("Ask me before")
                Text("A tool you tick here stops and asks on the notch instead of in its own window. Tick nothing and nothing is intercepted at all.")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.subtitleColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 2)

                ForEach(Array(AskTools.offered.enumerated()), id: \.element.name) { index, tool in
                    if index > 0 { SettingDivider() }
                    SettingRow(tool.name, detail: tool.detail) {
                        Toggle("", isOn: binding(for: tool.name)).labelsHidden()
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: Connecting

    private var connectionTitle: String {
        switch monitor.hookState {
        case .notInstalled, .unknown: return "Connect Claude Code"
        case .current: return "Claude Code is connected"
        case .outOfDate: return "Claude Code needs reconnecting"
        }
    }

    private var connectionDetail: String {
        switch monitor.hookState {
        case .notInstalled, .unknown:
            return "Adds a small script to your home folder and tells Claude Code to run it, so what it is doing can show on the notch. You can read the script first; it is plain text."
        case .current:
            return "It is running the version this copy of HashNotch ships."
        case .outOfDate(let installed, let available):
            return "The connected copy is version \(installed) and this app ships \(available). Reconnect to bring it up to date."
        }
    }

    private var connectionAction: String {
        if case .current = monitor.hookState { return "Reconnect" }
        return "Connect"
    }

    private func install() {
        installing = true
        result = nil
        HookInstallation.install { ok, output in
            installing = false
            failed = !ok
            result = ok
                ? "Done. Claude Code will use it from its next session."
                : (output.isEmpty ? "It did not finish. Nothing was changed." : output)
            monitor.refreshHookState()
        }
    }

    // MARK: Choosing

    /// Each switch edits only its own line, so a tool somebody added by hand
    /// that this page does not offer is left exactly where it is.
    private func binding(for name: String) -> Binding<Bool> {
        Binding(
            get: { tools.contains(name) },
            set: { on in
                let updated = AskTools.setting(name, on: on, in: tools)
                AskTools.write(updated)
                tools = updated
            }
        )
    }
}
