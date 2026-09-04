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
                detail: "A stretch of work, a short rest, and a longer one every few rounds. The day's tally counts only the time you were actually here."
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
                    "Rounds before the long rest",
                    detail: "How many stretches of work come first."
                ) {
                    Stepper(
                        value: Binding(
                            get: { engine.plan.worksBeforeLongBreak },
                            set: { var plan = engine.plan; plan.worksBeforeLongBreak = $0; engine.setPlan(plan) }
                        ),
                        in: FocusPlan.worksBeforeLongBreakRange
                    ) {
                        Text("\(engine.plan.worksBeforeLongBreak)")
                            .foregroundStyle(theme.textColor)
                            .monospacedDigit()
                    }
                    .labelsHidden()
                }
            }

            SettingCard {
                SettingRow(
                    "The days behind today",
                    detail: engine.history.isEmpty
                        ? "Nothing kept yet. Finished days are kept here so today has something to compare against."
                        : "\(engine.history.days.count) \(engine.history.days.count == 1 ? "day" : "days") kept, at most \(FocusHistory.keptDays). Four numbers and a date each \u{2014} never what you were working on. Nothing is sent anywhere."
                ) {
                    Button("Forget them") { engine.clearHistory() }
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
            Stepper(value: Binding(get: { value }, set: set), in: range) {
                Text("\(value)")
                    .foregroundStyle(theme.textColor)
                    .monospacedDigit()
            }
            .labelsHidden()
        }
    }
}
