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
                    Image(systemName: "mic.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CallPalette.live)
                        .frame(width: 20, height: 20)
                }
                // The dot. Small, bright, and on the icon rather than beside it,
                // so it reads as "this app has your microphone" rather than as a
                // decoration that happens to be nearby.
                Circle()
                    .fill(CallPalette.live)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                    .offset(x: 2, y: 2)
            }
            .transition(.scale(scale: 0.5).combined(with: .opacity))
        }
    }
}

/// Trailing compact: how long, and that the microphone is the reason.
struct CallTitleView: View {
    @ObservedObject var monitor: CallMonitor
    let theme: Theme

    var body: some View {
        if let use = monitor.use {
            HStack(spacing: 6) {
                Text(CallReader.elapsedText(use.elapsed(now: monitor.now)))
                    .foregroundStyle(theme.textColor)
                    .monospacedDigit()
                    .rollingDigits()
                Image(systemName: "mic.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(CallPalette.live)
            }
            .fixedSize(horizontal: true, vertical: false)
            .transition(.opacity.combined(with: .offset(x: -6)))
        }
    }
}

/// Expanded: which app, how long, and — the part that matters — what the app
/// does and does not know about it.
struct CallDetailView: View {
    @ObservedObject var monitor: CallMonitor
    let theme: Theme

    var body: some View {
        if let use = monitor.use {
            VStack(alignment: .leading, spacing: 7) {
                NotchSectionHeader("MICROPHONE", theme: theme)

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
                                .fill(CallPalette.live)
                                .frame(width: 6, height: 6)
                            Text(use.appName)
                                .foregroundStyle(theme.textColor)
                                .lineLimit(1)
                        }
                        // Only claim an owner when there is one. When the
                        // microphone is held by a background service nothing
                        // could attribute, the name above already says
                        // "Microphone in use" and a second line insisting it
                        // belongs to something would be inventing a fact.
                        if use.isNamedApp {
                            Text("has your microphone open")
                                .font(.system(size: 9))
                                .foregroundStyle(theme.subtitleColor)
                        } else {
                            Text("by a background service")
                                .font(.system(size: 9))
                                .foregroundStyle(theme.subtitleColor)
                        }
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
                Text("HashNotch only sees that an app opened the microphone. It never listens, records or transcribes, and has no microphone permission of its own.")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.subtitleColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: Panel.rowWidth, alignment: .leading)
        }
    }
}

enum CallPalette {
    /// The same orange macOS itself uses for its microphone indicator, so it
    /// reads as the system's own warning rather than as this app's decoration.
    static let live = Color(red: 1.00, green: 0.58, blue: 0.00)
}
