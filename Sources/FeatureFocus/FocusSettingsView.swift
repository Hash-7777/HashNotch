import SwiftUI
import HashNotchKit

/// How long each part of the cycle runs.
///
/// Steppers rather than free text: every one of these is a small whole number of
/// minutes, and a field somebody can type "0" into is a field that has to be
/// argued with afterwards. The ranges are the same ones `FocusPlan` clamps to,
/// so the window and the rule cannot disagree.
struct FocusSettingsView: View {
    @ObservedObject var engine: FocusEngine
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(
                "Focus",
                detail: "Work, then a short rest. A longer rest every few rounds. Only time you were at the Mac is counted."
            )

            SettingCard {
                minutesRow("Focus", value: engine.plan.workMinutes, range: FocusPlan.workRange) {
                    var plan = engine.plan; plan.workMinutes = $0; engine.setPlan(plan)
                }
                SettingDivider()
                minutesRow("Short rest", value: engine.plan.shortBreakMinutes, range: FocusPlan.shortBreakRange) {
                    var plan = engine.plan; plan.shortBreakMinutes = $0; engine.setPlan(plan)
                }
                SettingDivider()
                minutesRow("Long rest", value: engine.plan.longBreakMinutes, range: FocusPlan.longBreakRange) {
                    var plan = engine.plan; plan.longBreakMinutes = $0; engine.setPlan(plan)
                }
                SettingDivider()
                SettingRow(
                    "Rounds before a long rest",
                    detail: FocusPlan.roundsDetail(engine.plan.worksBeforeLongBreak)
                ) {
                    countStepper(
                        value: engine.plan.worksBeforeLongBreak,
                        range: FocusPlan.worksBeforeLongBreakRange
                    ) { var plan = engine.plan; plan.worksBeforeLongBreak = $0; engine.setPlan(plan) }
                }
            }

            SettingCard {
                SettingRow(
                    "Past days",
                    detail: engine.history.isEmpty
                        ? "Nothing kept yet."
                        : "\(engine.history.days.count) day\(engine.history.days.count == 1 ? "" : "s") kept, up to \(FocusHistory.keptDays). On this Mac only, never sent anywhere."
                ) {
                    Button("Delete") { engine.clearHistory() }
                        .disabled(engine.history.isEmpty)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func minutesRow(
        _ title: String,
        value: Int,
        range: ClosedRange<Int>,
        set: @escaping (Int) -> Void
    ) -> some View {
        SettingRow(title, detail: "\(value) minutes.") {
            countStepper(value: value, range: range, set: set)
        }
    }

    /// The number, then the buttons that change it.
    ///
    /// The number is drawn beside the stepper rather than as its label. A
    /// stepper's label is exactly what `.labelsHidden()` removes, so written as
    /// a label the figure never appeared at all — the rounds row showed two
    /// arrows and no number, and the minute rows only got away with it because
    /// their descriptions repeat the value.
    private func countStepper(
        value: Int,
        range: ClosedRange<Int>,
        set: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text("\(value)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textColor)
                .monospacedDigit()
                .frame(minWidth: 22, alignment: .trailing)
                .rollingDigits()
                .animation(.snappy, value: value)
            Stepper("", value: Binding(get: { value }, set: set), in: range)
                .labelsHidden()
        }
    }
}
