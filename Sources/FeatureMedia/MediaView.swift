import SwiftUI
import AppKit
import HashNotchKit

/// Leading compact-live: album artwork to the left of the notch.
/// Shows while a track is present — playing or paused — so the artwork stays
/// on the notch after you pause, until the player quits or the tab closes.
struct MediaArtworkView: View {
    @ObservedObject var monitor: MediaMonitor
    let theme: Theme

    var body: some View {
        if let media = monitor.nowPlaying {
            artwork(media)
                .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func artwork(_ media: NowPlaying) -> some View {
        let size: CGFloat = 26
        Group {
            if let data = media.artwork, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(theme.subtitleColor)
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
    }
}

/// Trailing compact-live: the track title to the right of the notch — long
/// titles scroll like on the iPhone — with the audio bars at the far end,
/// away from the notch so the text never disappears under it.
struct MediaTitleView: View {
    @ObservedObject var monitor: MediaMonitor
    let theme: Theme

    var body: some View {
        if let media = monitor.nowPlaying {
            HStack(spacing: 7) {
                // The title scrolls only while playing, for the same reason the
                // bars only dance then: a paused track sits at the notch for as
                // long as you leave it, and neither should be animating there.
                MarqueeText(media.title, scrolls: media.isPlaying)
                    .foregroundStyle(theme.textColor)
                // Bars dance only while playing; they rest as dots when paused.
                AudioBarsView(isActive: media.isPlaying, tint: theme.accent)
            }
            .frame(maxWidth: 140, alignment: .leading)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

/// Expanded detail: the iPhone-island media card — artwork, scrolling title,
/// artist, audio bars, a live progress bar, and play/skip controls for the
/// players we can script (Spotify, Music).
struct MediaDetailView: View {
    @ObservedObject var monitor: MediaMonitor
    let theme: Theme
    /// Shuts the panel, for the one case that needs it: raising a system
    /// permission dialog the panel would otherwise cover.
    var onClose: () -> Void = {}
    /// Opens settings at a named page, for the notice that names a switch.
    var onOpenSettingsPage: (String) -> Void = { _ in }
    /// Where the finger is during a drag of the progress bar, in seconds. Nil
    /// when nobody is dragging, which is when the clock owns the bar again.
    @State private var scrubbing: Double?
    /// Whether the pointer is over the bar, so it can thicken to be grabbed
    /// without being thick the rest of the time.
    @State private var hoveringBar = false

    /// A hairline at rest. The bar's job is to be read at a glance from across
    /// a desk, and a thin line with a bright played portion reads better than a
    /// thick one — thickness adds weight without adding information.
    private static let barThickness: CGFloat = 3
    /// Thicker only while it is being aimed at or dragged, so there is
    /// something to hold on to at the moment it is wanted.
    private static let barThicknessActive: CGFloat = 5
    private static let handleSize: CGFloat = 9

    var body: some View {
        if let media = monitor.nowPlaying {
            // Tight on purpose, and tightened again since. The media card sits
            // at the top of a panel that has to fit eleven other indicators
            // below it before the screen runs out, so every point it does not
            // need is a point another readout gets — and this card was the one
            // spending the most on air.
            //
            // Every point taken back here comes out of a GAP or out of the
            // artwork, never out of a target: the three transport buttons keep
            // their 28-point circles and the progress bar keeps a row tall
            // enough to catch, because a control nobody can hit is not a saving.
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    artwork(media)
                    VStack(alignment: .leading, spacing: 1) {
                        // Unlike the strip, this title keeps scrolling while
                        // paused. The panel only exists while you are hovering
                        // it, so the animation is bounded by your attention —
                        // and being able to read the whole of a long title is
                        // worth more here than the second or two of motion.
                        MarqueeText(media.title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.textColor)
                        if let artist = media.artist {
                            Text(artist)
                                .font(.system(size: 10))
                                .foregroundStyle(theme.subtitleColor)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    AudioBarsView(isActive: media.isPlaying, tint: theme.accent)
                }

                if let progress = monitor.progress {
                    progressBar(progress)
                }

                // Controls work for every source: Spotify/Music via their own
                // scripting, everything else through the system media channel.
                HStack(spacing: 28) {
                    MediaControlButton(symbol: "backward.fill", size: 12, theme: theme) {
                        monitor.previous()
                    }
                    MediaControlButton(
                        symbol: media.isPlaying ? "pause.fill" : "play.fill",
                        size: 16,
                        theme: theme
                    ) {
                        monitor.togglePlayPause()
                    }
                    MediaControlButton(symbol: "forward.fill", size: 12, theme: theme) {
                        monitor.next()
                    }
                }
                .frame(maxWidth: .infinity)

                if let problem = monitor.controlProblem {
                    controlNotice(problem)
                }

                if let volume = monitor.systemVolume {
                    HStack(spacing: 9) {
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.subtitleColor)
                        PremiumVolumeSlider(value: volume) { monitor.setVolume($0) }
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.subtitleColor)
                    }
                }
            }
            .frame(width: Panel.rowWidth, alignment: .leading)
        }
    }

    /// Shown only after a command has actually failed, never as a warning in
    /// advance.
    ///
    /// A button that quietly does nothing is the worst version of this: the
    /// system's media channel reports success for a browser and ignores the
    /// command, so without this the panel had every reason to believe it had
    /// worked and the user had every reason to believe the app was broken. It
    /// says what stopped it and offers the one action that fixes it.
    @ViewBuilder
    private func controlNotice(_ problem: MediaMonitor.ControlProblem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.subtitleColor)
            Text(noticeText(problem))
                .font(.system(size: 9))
                .foregroundStyle(theme.subtitleColor)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if problem == .browserControlOff {
                // The notice names a switch, so it had better be able to reach
                // it. Telling somebody where to go and making them find it is
                // most of the way to not telling them.
                Button("Open…") {
                    onClose()
                    onOpenSettingsPage(SettingsRoute.browserControl)
                }
                .buttonStyle(.plain)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.accent)
            }
            if problem == .accessibilityMissing {
                Button("Allow…") {
                    // Get out of the way first. The panel hangs from the top of
                    // the screen and macOS puts its permission dialog in the
                    // middle, but the panel is the frontmost thing the user was
                    // just touching — leaving it up over the answer to the
                    // question it asked is a poor way to ask for permission.
                    onClose()
                    MediaKeys.requestTrust()
                }
                .buttonStyle(.plain)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.accent)
            }
        }
        .frame(width: Panel.rowWidth, alignment: .leading)
        .transition(.opacity)
        // Granting the permission happens outside this app and reports nothing
        // back, so the notice asks again whenever it is shown rather than
        // waiting for the next poll to notice it is obsolete.
        .onAppear { monitor.recheckControl() }
    }

    private func noticeText(_ problem: MediaMonitor.ControlProblem) -> String {
        switch problem {
        case .browserControlOff:
            // Named for what the user would look for, not for the mechanism:
            // the setting is called "Control video in your browser".
            return "A browser only listens to the media keys. Turn on \"Control video in your browser\"."
        case .accessibilityMissing:
            // The switch reading "on" while the permission is not in force is
            // the normal case after an update, not an edge case, so the remedy
            // is the message rather than a footnote to it. Telling someone to
            // grant a permission they can see is already granted reads as the
            // app being broken.
            //
            // And the remedy is the one that WORKS. This first said to switch
            // it off and on again, which is the obvious advice and was tried
            // and did not help: macOS keeps the stale entry either way. What
            // fixed it was removing the entry outright with the minus button so
            // there is nothing left to be stale, and letting the app add itself
            // back. Advice that does not work is worse than none — it costs the
            // reader the time AND their belief in the next thing the app says.
            return "macOS is not allowing the media keys. In Accessibility, select HashNotch, remove it with the − button, then press Allow here to add it back."
        }
    }

    /// How tall the draggable row is. Still comfortably catchable — a hairline
    /// is not something anyone can reliably hit, which is why the row is taller
    /// than the bar drawn inside it — and three points shorter than it was.
    private static let progressRowHeight: CGFloat = 13

    /// The progress bar, ticking once a second only while the track is moving.
    ///
    /// A paused track's position does not change, so a clock driving it redraws
    /// the bar and both labels every second to arrive at the same frame — inside
    /// a panel that is already animating. `TimelineView(.periodic:)` has no
    /// `paused` parameter the way `.animation` does, so the schedule itself is
    /// switched rather than the value: playing gets the clock, paused gets one
    /// static frame at the position it stopped on.
    @ViewBuilder
    private func progressBar(_ progress: MediaProgress) -> some View {
        if progress.isPlaying {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                progressBody(progress, now: context.date)
            }
            .frame(height: Self.progressRowHeight)
        } else {
            // `current(now:)` ignores the clock while paused, so any date gives
            // the stopped position; its own is the honest one to pass.
            progressBody(progress, now: progress.at)
                .frame(height: Self.progressRowHeight)
        }
    }

    private func progressBody(_ progress: MediaProgress, now: Date) -> some View {
        // While a drag is in progress the finger is the truth, not the clock:
        // otherwise the poll behind it fights the drag and the bar stutters.
        let current = scrubbing ?? progress.current(now: now)
        let fraction = progress.duration > 0 ? current / progress.duration : 0
        let seekable = monitor.canSeek && progress.duration > 0
        // "In use" — being dragged, or about to be.
        let active = seekable && (scrubbing != nil || hoveringBar)
        return VStack(spacing: 2) {
            GeometryReader { geo in
                // The bar is drawn at its own slim height, centred inside a
                // taller invisible row. The first version made the whole row
                // the bar, so adding the ability to drag made the line four
                // times thicker and stuck a dot on the end of it — the control
                // grew to advertise itself, which is the opposite of premium.
                // The touch target is what needs the height; the bar does not.
                let track = active ? Self.barThicknessActive : Self.barThickness
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .frame(height: track)
                    Capsule()
                        .fill(theme.textColor)
                        .frame(width: max(track, geo.size.width * CGFloat(fraction)), height: track)
                    // The handle exists only while the bar is being used. At
                    // rest the played edge IS the position, which is how every
                    // player worth copying draws it.
                    if seekable, active {
                        Circle()
                            .fill(theme.textColor)
                            .frame(width: Self.handleSize, height: Self.handleSize)
                            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                            .offset(x: min(
                                max(0, geo.size.width * CGFloat(fraction) - Self.handleSize / 2),
                                geo.size.width - Self.handleSize
                            ))
                    }
                }
                .frame(height: geo.size.height, alignment: .center)
                .animation(.easeOut(duration: 0.14), value: active)
                // The hit area is the full row rather than the hairline: a line
                // this thin is not something anyone can reliably catch.
                .contentShape(Rectangle())
                .gesture(
                    seekable
                        ? DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let ratio = min(max(0, value.location.x / max(1, geo.size.width)), 1)
                                scrubbing = ratio * progress.duration
                            }
                            .onEnded { value in
                                let ratio = min(max(0, value.location.x / max(1, geo.size.width)), 1)
                                monitor.seek(to: ratio * progress.duration)
                                scrubbing = nil
                            }
                        : nil
                )
                .onHover { hoveringBar = $0 }
            }
            .frame(height: seekable ? 10 : Self.barThickness)
            HStack {
                Text(timeText(current))
                Spacer()
                Text("-" + timeText(max(0, progress.duration - current)))
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(theme.subtitleColor)
        }
    }

    private func timeText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @ViewBuilder
    private func artwork(_ media: NowPlaying) -> some View {
        // Four points off, which comes straight off the height of the whole
        // card: this is the tallest thing in its row, so the row is as tall as
        // it is.
        let size: CGFloat = 42
        Group {
            if let data = media.artwork, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 16))
                            .foregroundStyle(theme.subtitleColor)
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
    }
}

/// An iPhone-style volume slider: thin capsule track, white fill, and a knob
/// that grows under the pointer. Values apply on every drag tick — the
/// backing call is direct CoreAudio, so movement is instant.
private struct PremiumVolumeSlider: View {
    let value: Int
    let onChange: (Int) -> Void

    @State private var dragging = false
    @State private var hovering = false

    private var knobSize: CGFloat { dragging ? 17 : (hovering ? 14 : 11) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = CGFloat(min(max(value, 0), 100)) / 100
            let knob = knobSize
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 4)
                Capsule(style: .continuous)
                    .fill(Color.white)
                    .frame(width: max(4, width * fraction), height: 4)
                Circle()
                    .fill(Color.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
                    .offset(x: min(max(width * fraction - knob / 2, 0), width - knob))
            }
            .frame(width: width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        dragging = true
                        let fraction = min(max(gesture.location.x / width, 0), 1)
                        onChange(Int((fraction * 100).rounded()))
                    }
                    .onEnded { _ in dragging = false }
            )
        }
        // Only as tall as the knob at its largest, so the slider carries no
        // dead space above or below it.
        .frame(height: 17)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: knobSize)
    }
}

/// One round media control: a plain white symbol with a soft circular
/// highlight on hover, sized for an easy click target.
private struct MediaControlButton: View {
    let symbol: String
    let size: CGFloat
    let theme: Theme
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(theme.textColor)
                // 28 rather than 32: still a comfortable target, and three of
                // them plus the row's own gaps are the tallest thing in the
                // media card.
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.16 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
