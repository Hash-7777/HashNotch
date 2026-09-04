import AppKit
import SwiftUI
import HashNotchKit

/// Leading compact: the app's own icon, with the live dot on it.
struct CallIconView: View {
    @ObservedObject var monitor: CallMonitor
    let theme: Theme

    var body: some View {
        if monitor.use != nil {
            ZStack(alignment: .bottomTrailing) {
                if let icon = monitor.appIcon() {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 20, height: 20)
                } else {
                    // No app to show, so the symbol has to carry which thing is
                    // live. A camera on its own can never be attributed, so this
                    // is the ordinary case for it rather than a rare fallback.
                    Image(systemName: monitor.use?.microphone == true ? "mic.fill" : "video.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CallPalette.dot(
                            microphone: monitor.use?.microphone ?? false,
                            camera: monitor.use?.camera ?? false))
                        .frame(width: 20, height: 20)
                }
                // The dot. Small, bright, and on the icon rather than beside it,
                // so it reads as "this app has your microphone" rather than as a
                // decoration that happens to be nearby.
                Circle()
                    .fill(CallPalette.dot(
                        microphone: monitor.use?.microphone ?? false,
                        camera: monitor.use?.camera ?? false))
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                    .offset(x: 2, y: 2)
            }
            .transition(.scale(scale: 0.5).combined(with: .opacity))
        }
    }
}

/// Trailing compact: how long, and which of the two is the reason.
struct CallTitleView: View {
    @ObservedObject var monitor: CallMonitor
    let theme: Theme

    var body: some View {
        if let use = monitor.use {
            HStack(spacing: 5) {
                Text(CallReader.elapsedText(use.elapsed(now: monitor.now)))
                    .foregroundStyle(theme.textColor)
                    .monospacedDigit()
                    .rollingDigits()
                // One symbol per thing that is live, so a glance at the strip
                // says whether you are heard, seen, or both — which is the
                // thing people get wrong in a meeting.
                if use.microphone {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(CallPalette.microphone)
                }
                if use.camera {
                    Image(systemName: "video.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(CallPalette.camera)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .transition(.opacity.combined(with: .offset(x: -6)))
        }
    }
}

/// Expanded: what is live, which app when that can be answered, how long, and —
/// the part that matters — what this app does and does not know about it.
struct CallDetailView: View {
    @ObservedObject var monitor: CallMonitor
    let theme: Theme

    var body: some View {
        if let use = monitor.use {
            VStack(alignment: .leading, spacing: 7) {
                NotchSectionHeader(
                    CallReader.headline(microphone: use.microphone, camera: use.camera),
                    // The microphone's mark stands for both when both are live:
                    // one heading gets one mark, and the words beside it already
                    // name the pair.
                    icon: use.microphone ? .microphone : .camera,
                    theme: theme
                )

                HStack(spacing: 9) {
                    if let icon = monitor.appIcon() {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 26, height: 26)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(CallPalette.dot(
                                    microphone: use.microphone, camera: use.camera))
                                .frame(width: 6, height: 6)
                            Text(use.appName)
                                .foregroundStyle(theme.textColor)
                                .lineLimit(1)
                        }
                        // Only claim an owner when there is one. When nothing
                        // could be attributed, the name above is already a
                        // statement rather than an app, and a second line
                        // insisting it belongs to something would invent a fact.
                        // A camera on its own is always in that case: nothing
                        // macOS publishes can say whose it is.
                        Text(CallReader.subtitle(
                            microphone: use.microphone,
                            camera: use.camera,
                            isNamedApp: use.isNamedApp
                        ))
                        .font(.system(size: 9))
                        .foregroundStyle(theme.subtitleColor)
                    }
                    Spacer(minLength: 8)
                    Text(CallReader.elapsedText(use.elapsed(now: monitor.now)))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.textColor)
                        .monospacedDigit()
                        .rollingDigits()
                }

                // Said here rather than only in a document, because this is the
                // one readout where somebody is entitled to wonder. An app that
                // notices your microphone should say what it noticed with, and
                // it should say it where the noticing is on screen.
                Text("HashNotch only sees that a microphone or camera was opened. It never listens, watches, records or transcribes, and holds no microphone or camera permission of its own.")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.subtitleColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: Panel.rowWidth, alignment: .leading)
        }
    }
}

package enum CallPalette {
    /// The same orange macOS itself uses for its microphone indicator, so it
    /// reads as the system's own warning rather than as this app's decoration.
    package static let microphone = Color(red: 1.00, green: 0.58, blue: 0.00)

    /// And the green it uses for the camera, for exactly the same reason.
    ///
    /// The two halves of this readout were both drawn in the microphone's
    /// orange to begin with, which broke the promise the line above makes:
    /// macOS says orange for a microphone and GREEN for a camera, so a camera
    /// drawn in orange is speaking the system's language for one symbol and not
    /// the other. Somebody glancing at the strip during a call already has the
    /// system's colours in the menu bar above it.
    ///
    /// `NSColor.systemGreen` in the dark appearance, measured — rgb(0.188,
    /// 0.820, 0.345) — and written out rather than taken live, because the
    /// island is black whatever appearance the Mac is set to, and a dynamic
    /// colour would shift with a setting that changes nothing underneath it.
    package static let camera = Color(red: 0.188, green: 0.820, blue: 0.345)

    /// The colour of the live dot on the app's icon, and of the stand-in symbol
    /// when there is no icon to put it on.
    ///
    /// One dot, two things it could mean, so the camera wins — which is what
    /// macOS does too: with both live it shows the green one. Being seen is the
    /// larger fact, and it is the one somebody wants to know from across the
    /// room.
    package static func dot(microphone: Bool, camera: Bool) -> Color {
        camera ? Self.camera : Self.microphone
    }
}
