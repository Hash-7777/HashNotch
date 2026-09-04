import SwiftUI

/// What a new install is shown before a single feature starts.
///
/// This exists because "you can switch it off" answered a different question
/// from the one people were asking. Every indicator honoured its switch, and
/// none of them sent anything anywhere — but they all shipped ON, and the app
/// began reading at launch, so the first chance to decline arrived after the
/// reading had happened. A reviewer put it exactly right: a first launch occurs
/// before the user can opt out.
///
/// So this is shown while nothing is running, and `FeatureRegistry.syncRunning`
/// refuses to start anything until it is accepted. It is deliberately not a
/// licence agreement: it names what is read in the plainest words available and
/// says what is never read, because the claim worth making here is one somebody
/// can check against the source rather than take on trust.
struct FirstRunView: View {
    let accent: Color
    let onAccept: () -> Void
    let onDecline: () -> Void

    /// The ones that touch a file, run a subprocess, can raise a macOS
    /// permission prompt, or learn something about YOU rather than about the
    /// machine. The rest — connection speed, battery, processor, memory,
    /// storage, temperatures — read counters the kernel keeps about the
    /// hardware, and listing them all here would bury the ones that matter.
    ///
    /// The test for being on this list is not "does it need permission". Naming
    /// the programs that used the network needs none and takes nothing off the
    /// Mac, and it still belongs here, because which programs somebody runs is
    /// a fact about them. A consent window that only lists what macOS happens
    /// to gate is a consent window written by macOS.
    private var readers: [ConsentReadings.Reader] { ConsentReadings.all }


    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            hairline

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(readers, content: row)
                    footnote
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 22)
            }

            hairline
            actions
        }
        .frame(width: 520, height: 580)
        .background(panelSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var panelSurface: some View {
        ZStack {
            VisualEffectView(material: .hudWindow)
            Color.black.opacity(0.55)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Before anything starts")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color.white)
            Text("HashNotch has not read anything yet. Here is everything it will read, and what it will never do.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
        .padding(.top, 26)
        .padding(.bottom, 20)
        // Drag the window by its heading — there is no title bar, and this
        // block is nothing but words.
        .overlay(WindowDragArea())
    }

    private func row(_ reader: ConsentReadings.Reader) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: reader.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(reader.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text(reader.reads)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
                Text(reader.never)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The rest")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            Text("AirPods charge runs the same Bluetooth report the System Information app shows you, and reads the battery percentages out of it. Connection speed, battery, processor, memory, storage and temperatures read counters the system keeps about the machine itself — how much went past, not what it was or whose it was.")
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
            Text("Nothing leaves your Mac. The only request this app can make is for the cover picture of what's playing.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            Text("Every indicator can be switched off at any time, and switching one off stops it reading — not just showing.")
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    /// Two answers, and they mean opposite things.
    ///
    /// This is not the pair that was here before. That one offered "Choose what
    /// runs" beside "Start", and both of them agreed — one was the same answer
    /// wearing a different word, which makes a statement look like a question.
    /// It was removed for exactly that reason.
    ///
    /// A window that asks permission and offers only one button is not asking
    /// anything either. It is telling somebody what is about to happen while
    /// standing in the doorway, and the only way past it is to agree. So the
    /// second button here is the one that was actually missing: **no**.
    ///
    /// Refusing quits, because there is no third state. The whole design of the
    /// consent gate is that nothing reads anything until it is answered, so an
    /// app left running on a refusal would be an app doing nothing at all,
    /// sitting in the notch, waiting to be asked again. Quitting says what
    /// happened.
    private var actions: some View {
        HStack(spacing: 12) {
            Button("Refuse and quit") { onDecline() }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.62))
                // Escape is what people press to get out of a window they did
                // not ask for, and it should not be the one key that does
                // nothing here.
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Start HashNotch") { onAccept() }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
    }
}

/// What the opening window promises the app reads.
///
/// Lifted out of the view so the checks can hold it to what the app actually
/// does. A consent window nothing is watching is a consent window that goes
/// stale the first time somebody adds a reading — which is exactly what
/// happened when naming the programs that used the network shipped without
/// appearing here.
package enum ConsentReadings {
    package struct Reader: Identifiable {
        package let id: String
        let icon: String
        let title: String
        package let reads: String
        package let never: String
    }

    /// Package-visible so the checks can hold this list to what the app
    /// actually does, rather than leaving it to be remembered.
    ///
    /// It has already been forgotten once: naming the programs that used the
    /// network was added, shipped, and left off this window for a day, while
    /// the paragraph below still said the network reading was "nothing about
    /// you". Nothing in the build could notice, because nothing was watching
    /// the list. Something is now.
    package static let all: [Reader] = [
        Reader(
            id: "media",
            icon: "play.circle",
            title: "What's playing",
            reads: "Asks macOS for the title, artist and position of whatever is playing, in any app.",
            never: "It cannot hear anything — these are the same track details your keyboard's play button works with."
        ),
        Reader(
            id: "call",
            icon: "mic",
            title: "Microphone and camera in use",
            reads: "Asks macOS one yes-or-no question per app — does this app have the microphone open? — and one per camera: is this camera running?",
            never: "Never listens, watches, records or transcribes. The app holds no microphone or camera permission and could not use one. It cannot tell which app a camera belongs to, and does not guess."
        ),
        Reader(
            id: "downloads",
            icon: "arrow.down.circle",
            title: "Downloads",
            reads: "Lists the file names in your Downloads folder, so it can tell you when one finishes.",
            never: "Never opens, moves or looks inside a file. macOS will ask your permission the first time."
        ),
        Reader(
            id: "focus",
            icon: "target",
            title: "Focus, and the day's tally",
            reads: "Nothing about your Mac. It records when you were focusing and for how long, and keeps the last 7 days.",
            never: "Never sent anywhere. It knows a block ran, never what you were working on. Nothing older than a week is kept, and you can delete it all in Settings."
        ),
        Reader(
            id: "away",
            icon: "clock.arrow.circlepath",
            title: "While you were away",
            reads: "Nothing of its own. It subtracts what the indicators above were already showing at two moments — when the screen went away, and when it came back.",
            never: "Nothing is read for this that is not already read for something else, and nothing is written down: the two moments live in memory and are gone when the app quits."
        ),
        Reader(
            id: "tokens",
            icon: "number",
            title: "AI tokens",
            reads: "Adds up the token counts your AI tools write into their own log files.",
            never: "Only the numbers are kept. None of the text of your conversations is read into the app."
        ),
        Reader(
            id: "networkApps",
            icon: "chart.bar",
            title: "Which programs used the network",
            reads: "Runs Apple's own nettop, the tool Activity Monitor's Network tab is built on, to ask how many bytes each of your programs has sent and received.",
            never: "No address, no site and no port is asked for or returned — this app cannot see where any of it went. It is a switch of its own under Settings, and turning it off stops the asking rather than hiding the answer."
        ),
        Reader(
            id: "activities",
            icon: "bell.badge",
            title: "Live activities",
            reads: "Reads one file, ~/.hashnotch/activities.json, which your own scripts and tools write when they want to put something on the notch.",
            never: "Never written to by this app, and nothing is read unless you or a tool you installed put it there."
        ),
    ]

}
