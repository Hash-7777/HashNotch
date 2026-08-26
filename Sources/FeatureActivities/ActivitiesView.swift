import SwiftUI
import AppKit
import HashNotchKit

/// Leading compact-live: the top activity's icon, to the left of the notch.
///
/// The mark sits in a soft tinted disc rather than floating bare against the
/// black, so a checkmark landing on the notch reads as a deliberate badge
/// instead of a stray glyph.
struct ActivitiesIconView: View {
    @ObservedObject var monitor: ActivitiesMonitor
    let theme: Theme

    var body: some View {
        if let activity = monitor.activities.first {
            ActivityMark(activity: activity, theme: theme, size: 21)
                .id(activity.id)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        }
    }
}

/// Logos already read from disk, so drawing one does not open and decode the
/// file again.
///
/// `ActivityMark` is drawn inside a view that re-renders at least once a second
/// while a countdown ticks, and far more often while the island animates.
/// Loading in `body` meant a disk read and a full image decode on the main
/// thread every one of those times, for a picture that had not changed since
/// the last one.
///
/// The entry is keyed by path *and* modification date, so replacing the file
/// still shows the new mark: a stat costs microseconds where the decode costs
/// milliseconds, which is the whole point of the cache. Only a handful of
/// posters ever have a logo, so a full clear when it fills is a fairer trade
/// than eviction machinery for a dictionary that rarely passes one entry.
@MainActor
private enum ActivityLogoCache {
    private struct Key: Hashable {
        let path: String
        let modified: Date?
    }

    private static var entries: [Key: NSImage] = [:]
    private static let maxEntries = 8

    static func image(atPath path: String) -> NSImage? {
        let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        let key = Key(path: path, modified: modified)
        if let cached = entries[key] { return cached }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        if entries.count >= maxEntries { entries.removeAll() }
        entries[key] = image
        return image
    }
}

/// The badge an activity shows: its own logo when it has one, otherwise a
/// symbol in a tinted disc.
///
/// A logo is drawn plain and round, without the tint behind it — a brand mark
/// sitting on a coloured disc that is not its own reads as a mistake. A symbol
/// keeps the disc, which is what stops it looking like a stray glyph on black.
struct ActivityMark: View {
    let activity: LiveActivity
    let theme: Theme
    let size: CGFloat

    /// The same colour the island's edge is wearing for this activity, asked of
    /// the same rule rather than chosen again here — a green ring around the
    /// notch with an accent-coloured badge inside it would read as two
    /// different things happening at once. Falls back to the accent for work
    /// that is merely in progress, which lights no edge at all.
    private var tint: Color { ActivitiesFeature.markTint(for: activity, accent: theme.accent) }

    var body: some View {
        if let path = activity.imagePath, let image = ActivityLogoCache.image(atPath: path) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: ActivitiesFeature.logoSide(for: size), height: ActivitiesFeature.logoSide(for: size))
                .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        } else {
            Image(systemName: activity.icon)
                .font(.system(size: size * 0.52, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(tint.opacity(0.16))
                        .overlay(Circle().strokeBorder(tint.opacity(0.22), lineWidth: 0.6))
                )
        }
    }
}

/// Trailing compact-live: the top activity's title, to the right of the notch.
///
/// A countdown shows its time left. A notice — something that already happened
/// — shows its subtitle instead, because a number ticking down beside the word
/// "finished" only ever asked you to watch something that was already over.
struct ActivitiesTitleView: View {
    @ObservedObject var monitor: ActivitiesMonitor
    let theme: Theme

    var body: some View {
        if let activity = monitor.activities.first {
            // One line, not two.
            //
            // The strip is exactly as tall as the notch — 28 points on this
            // hardware — and an 11pt title stacked on a 9pt subtitle fills
            // essentially all of it, leaving the pair looking jammed against
            // each other with no room to breathe. So where there is a subtitle
            // to draw it goes BESIDE the title, dimmed, where the eye reads it
            // as one phrase. The full two-line treatment still exists in the
            // panel, which has room.
            //
            // In practice only a standing request has one: a finished notice
            // is title-only by `displaySubtitle`, so "HashCortX finished" is
            // all the strip shows, without the model name that used to trail
            // it.
            HStack(spacing: 5) {
                Text(activity.title)
                    .foregroundStyle(theme.textColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if !activity.showsCountdown, let subtitle = activity.displaySubtitle {
                    Text(subtitle)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.subtitleColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let text = Formatters2.waitedText(activity, monitor: monitor, now: monitor.now) {
                    Text(text)
                        .foregroundStyle(theme.subtitleColor)
                        .monospacedDigit()
                        .rollingDigits()
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(maxWidth: 150, alignment: .leading)
            .id(activity.id)
            .transition(.opacity.combined(with: .offset(x: -6)))
        }
    }

}

/// Expanded detail: every active activity as a row with a progress bar.
struct ActivitiesDetailView: View {
    @ObservedObject var monitor: ActivitiesMonitor
    let theme: Theme

    /// The state of updating the hook from here: in progress, done, or what
    /// went wrong. Kept on the view because it is about this panel being open,
    /// not about the app.
    @State private var updatingHook = false
    @State private var updatedHook = false
    @State private var hookProblem: String?
    /// Everything the installer wrote, kept for the tooltip. The row shows one
    /// line of it; somebody chasing a failure can hover and read the rest.
    @State private var hookProblemDetail: String?

    var body: some View {
        if !monitor.activities.isEmpty || monitor.hookState.needsAttention {
            VStack(alignment: .leading, spacing: 8) {
                NotchSectionHeader("ACTIVITIES", icon: .activities, theme: theme)
                ForEach(monitor.activities) { activity in
                    row(activity)
                }
                if case .outOfDate(let installed, let available) = monitor.hookState {
                    staleHookRow(installed: installed, available: available)
                }
            }
        }
    }

    /// The one line that says the hook on disk is older than the app, and the
    /// button that fixes it.
    ///
    /// It sits under the activities rather than above them: something that just
    /// happened outranks a piece of housekeeping, and this can wait for as long
    /// as it takes to read what is above it.
    ///
    /// **It used to copy a command instead of running one**, on the argument
    /// that running it edits `~/.claude/settings.json` — another program's
    /// configuration, from a click on a panel that opens when a cursor passes
    /// the notch — and that quietly rewriting another tool's settings because a
    /// mouse went by is exactly the shape of the thing this app says it does
    /// not do.
    ///
    /// The argument was right about the danger and wrong about the remedy. What
    /// it produced was a notice that told somebody their agent was running old
    /// code and then handed them a shell command, which for most people is the
    /// same as telling them nothing. And the panel already carries buttons that
    /// grant an agent permission to run a command on this Mac; beside those,
    /// bringing a script up to date is not the consequential one.
    ///
    /// So it does the work, and the danger is answered where it actually lives:
    /// the target is a small labelled button rather than the whole row, so a
    /// passing cursor cannot press it, and it says what it did.
    private func staleHookRow(installed: Int, available: Int) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(theme.subtitleColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Notch hook is v\(installed), this app ships v\(available)")
                    .foregroundStyle(theme.textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(hookUpdateDetail)
                    .font(.system(size: 8))
                    .foregroundStyle(theme.subtitleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            if !updatedHook {
                Button(updatingHook ? "Updating…" : "Update") { updateHook() }
                    .buttonStyle(.plain)
                    .disabled(updatingHook)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(theme.accent.opacity(0.14))
                            .overlay(Capsule().strokeBorder(theme.accent.opacity(0.22), lineWidth: 0.6))
                    )
                    .contentShape(Capsule())
            }
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .frame(width: Panel.rowWidth)
        // The command it runs, for anybody who would rather see what is about
        // to happen than take a button's word for it — and, once it has
        // refused, everything it wrote, because one line of the row is not
        // enough to chase a failure with.
        .help(hookHelp)
    }

    private var hookHelp: String {
        guard let hookProblemDetail, !hookProblemDetail.isEmpty else {
            return "Runs \(HookInstallation.updateCommand)"
        }
        return "Runs \(HookInstallation.updateCommand)\n\n\(hookProblemDetail)"
    }

    private var hookUpdateDetail: String {
        if updatingHook { return "Bringing it up to date…" }
        if updatedHook { return "Updated — Claude uses it from its next session" }
        if let hookProblem { return hookProblem }
        return "Update it so the notch says what this app now says"
    }

    private func updateHook() {
        updatingHook = true
        hookProblem = nil
        hookProblemDetail = nil
        HookInstallation.install { ok, output in
            updatingHook = false
            if ok {
                updatedHook = true
                monitor.refreshHookState()
            } else {
                // What the installer actually said, not a shrug. See
                // `HookInstallation.failureReason`: this row once threw the
                // reason away and reported "Could not update it" for a script
                // that had never parsed on any Mac.
                hookProblem = HookInstallation.failureReason(from: output)
                hookProblemDetail = output
            }
        }
    }

    @ViewBuilder
    private func row(_ activity: LiveActivity) -> some View {
        // An activity that named the app it belongs to becomes a way back to
        // it. "Claude needs you" that you can only read is a notification; one
        // click from it to the window that is waiting is the whole difference
        // between being told and being able to do something about it.
        if activity.appPath != nil {
            Button { activate(activity) } label: {
                rowBody(activity, showsJump: true)
            }
            .buttonStyle(.plain)
        } else {
            rowBody(activity, showsJump: false)
        }
    }

    private func activate(_ activity: LiveActivity) {
        guard let path = activity.appPath else { return }
        // `activates` puts it in front when it is already open, which is what
        // this is for — a way back to the window that is waiting. It is not a
        // guarantee against starting it: `openApplication` launches a bundle
        // that is not running. That is why the path is confined to the standard
        // application folders before it ever reaches here (see
        // `ActivitiesReader.safeAppPath`) — a click must never be able to start
        // something a feed dropped somewhere out of the way.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: path), configuration: configuration
        )
    }

    private func rowBody(_ activity: LiveActivity, showsJump: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ActivityMark(activity: activity, theme: theme, size: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(activity.title)
                        .foregroundStyle(theme.textColor)
                        .lineLimit(1)
                    if let subtitle = activity.displaySubtitle {
                        Text(subtitle)
                            .font(.system(size: 9))
                            .foregroundStyle(theme.subtitleColor)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let text = Formatters2.waitedText(activity, monitor: monitor, now: monitor.now) {
                    Text(text)
                        .foregroundStyle(theme.textColor)
                        .monospacedDigit()
                }
                if showsJump {
                    Image(systemName: "arrow.up.forward.app.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.accent)
                }
            }
            if let progress = activity.progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(theme.accent)
                    .scaleEffect(x: 1, y: 0.7)
            }
        }
        .frame(width: Panel.rowWidth, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Small local formatter (kept here to avoid growing the core for one feature).
package enum Formatters2 {
    /// How long this has been waiting, for anything that stands rather than
    /// passes. A notice on its way out says nothing — it is already leaving.
    @MainActor
    static func waitedText(
        _ activity: LiveActivity,
        monitor: ActivitiesMonitor,
        now: Date
    ) -> String? {
        guard activity.showsCountdown, let arrived = monitor.arrived(activity) else { return nil }
        return waited(Int(now.timeIntervalSince(arrived)))
    }

    /// How long something has been waiting on you.
    ///
    /// A standing request used to show the time LEFT before it gave up and
    /// left the screen — a countdown on a question, which measures the wrong
    /// thing entirely: it says how long until the app stops asking, when what
    /// matters is how long the answer has been owed. Now that a request is
    /// taken down the moment it is dealt with, it does not need to expire, and
    /// the number can be the honest one.
    ///
    /// Nothing at all for the first minute. A request that has just arrived is
    /// news, and "0 min" beside it is furniture. After that it counts up, which
    /// is its own quiet pressure.
    package static func waited(_ seconds: Int) -> String? {
        guard seconds >= 60 else { return nil }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
