import SwiftUI
import AppKit

/// The black interactive notch.
///
/// Three states:
///   • idle    — a black shape the size of the notch (looks like the notch).
///   • live    — content flanks the notch (art left, title right), black.
///   • expanded — on hover, a glassy panel drops down with the details.
///
/// The notch shape and live strip are solid black so they read as one piece
/// with the hardware; the drop-down panel is Control-Center glass, falls
/// straight down out of the notch like a water drop, and sizes to its
/// content (never clipped).
struct NotchIslandView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var settings: SettingsStore
    @ObservedObject var presence: LivePresence
    let registry: FeatureRegistry
    let context: FeatureContext
    /// Reports the island's rendered size so the controller can keep the
    /// overlay WINDOW hugging the island (a window-sized screenshot then
    /// captures just the notch, not a huge transparent strip).
    var onIslandSize: ((CGSize) -> Void)? = nil

    private var showExpanded: Bool { state.isExpanded }

    /// Whether the strip *should* be on screen — which is not the same as
    /// whether it is drawn yet. See `liveShown`.
    private var wantsLive: Bool { !state.isExpanded && presence.hasLive }

    /// The user's choice of motion, then adjusted for what this macOS keeps up
    /// with. A spring that cannot be drawn in time reads as stutter, and the
    /// same spring given slightly longer reads as deliberate — so an older
    /// system gets the identical animation, a little more slowly, rather than a
    /// faster one it drops frames through.
    private var motionScale: Double {
        settings.appearance.motion.responseScale * SystemGeneration.current.motionScale
    }
    private var panelRadius: CGFloat { CGFloat(settings.appearance.panelCornerRadius) }

    /// The panel drops as a SOLID BLACK box first, then — once this flips true
    /// ~0.2s later — the glass and its contents fade in. That black beat makes
    /// the panel read as the physical notch stretching open before it reveals.
    @State private var panelRevealed = false
    /// How many pixels the display gives a point, so the outline can be exactly
    /// one of them.
    @Environment(\.displayScale) private var displayScale

    // ── The settle, and why it is a spring rather than an effect ────────────
    //
    // The water-drop wobble was first built as a second animated transform:
    // an impulse kicked on open, released on an under-damped spring, applied
    // as a scaleEffect over the whole island. It was wrong, and the way it was
    // wrong is worth keeping.
    //
    // That scaleEffect sat on the container that HOLDS the transitioning
    // views. While the panel arrives and the strip leaves, both exist, and both
    // are already being scaled by their own transitions — so an outer scale
    // animating on a DIFFERENT curve multiplied against them frame by frame.
    // Captured in slow motion: the strip's artwork and title smeared across
    // three positions at once during the open, like a bad ghost.
    //
    // The wobble now comes from the opening spring itself — lower damping
    // overshoots and rings down, which is the same physical behaviour with
    // nothing layered on top. One transform per view, and nothing to compound.
    //
    // RULE, since it was learned the expensive way: never animate a transform
    // on a container whose children are mid-transition. Put it on a child that
    // is staying put, or express it in the spring that is already running.

    /// Whether the live strip is actually drawn.
    ///
    /// The panel and the strip are different shapes holding different layouts.
    /// Letting both animate at once cross-fades two layouts through each other
    /// — the same artwork and title visible twice, in two places, sliding past
    /// the desktop — which is what made closing the panel look cheap. Only one
    /// of them is ever on screen now: the panel retracts fully into the notch,
    /// and only then does the strip emerge from it.
    @State private var liveShown = false
    @State private var liveHandoff: DispatchWorkItem?

    /// Whether the strip is actually put on screen.
    ///
    /// `liveShown` alone was the condition, and it is a SECOND source of truth
    /// for something `wantsLive` already decides — so keeping the two in step
    /// was left to every path that touches either: the exit animation, the
    /// delayed hand-off, `onAppear`, and two separate `onChange` handlers. One
    /// path not keeping up drew the strip beside the open panel, which is the
    /// one arrangement the app promises never to show ("three states, and it is
    /// only ever in one of them").
    ///
    /// It was reported against the panel held open by the settings window, and
    /// reproduced by posting an activity while the panel opened: the strip was
    /// still shown at the moment the panel arrived, and stayed for as long as
    /// the panel was held open. The strip is wider than the panel, so it does
    /// not even hide behind it — the artwork juts out one side and the title
    /// the other.
    ///
    /// So the rule is enforced where it is DRAWN rather than maintained at
    /// every site that could break it. `liveShown` keeps its job of sequencing
    /// the hand-off; it just no longer gets the last word on visibility.
    private var liveVisible: Bool {
        IslandLayers.stripIsVisible(liveShown: liveShown, panelExpanded: showExpanded)
    }

    /// How long the strip waits after the panel starts closing. Slightly longer
    /// than the closing spring, so the hand-off happens on an empty notch.
    private var handoffDelay: TimeInterval { 0.30 * motionScale }

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { liveShown = wantsLive }
        .onChange(of: showExpanded) { expanded in
            if expanded {
                panelClosedAt = nil
                panelRevealed = false
                // Begins while the panel is still on its way down, not after it
                // has landed. At 0.2s the box arrived, paused, and then filled
                // — two events where there is one movement, which is what reads
                // as a stutter even when every frame was drawn on time. Starting
                // at 0.1s and fading over 0.24s has the contents arriving with
                // the panel rather than after it.
                //
                // Scaled by the motion setting like everything else, so calm
                // does not end up with the contents appearing before a panel
                // that is still moving.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.10 * motionScale) {
                    guard state.isExpanded else { return }
                    withAnimation(.easeOut(duration: 0.24 * motionScale)) { panelRevealed = true }
                }
            } else {
                panelClosedAt = Date()
                panelRevealed = false
            }
            updateLive(animated: true)
        }
        .onChange(of: wantsLive) { _ in updateLive(animated: true) }
    }

    /// Bring the strip in or out, never at the same moment as the panel.
    ///
    /// Going away is immediate: the strip must be gone before the panel starts
    /// opening. Coming back waits for the panel to finish retracting — but only
    /// when a panel was actually open, so a track starting on an idle notch
    /// still appears at once.
    /// Development aid, inert unless `HASHNOTCH_DEBUG=island`. The strip
    /// appearing beside an open panel is invisible to reading — both flags are
    /// spread across a view struct, an observable, and a delayed work item —
    /// and obvious in one line of trace.
    private static var tracesIsland: Bool {
        (ProcessInfo.processInfo.environment["HASHNOTCH_DEBUG"] ?? "").contains("island")
    }

    private func trace(_ label: String) {
        guard Self.tracesIsland else { return }
        let since = panelClosedAt.map { String(format: "%.2fs ago", Date().timeIntervalSince($0)) } ?? "nil"
        let line = "[island] \(label) liveShown=\(liveShown) wantsLive=\(wantsLive) "
            + "expanded=\(state.isExpanded) hasLive=\(presence.hasLive) panelClosedAt=\(since)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    private func updateLive(animated: Bool) {
        trace("updateLive enter")
        liveHandoff?.cancel()
        liveHandoff = nil

        guard wantsLive else {
            if liveShown { withAnimation(.easeOut(duration: 0.16)) { liveShown = false } }
            return
        }
        guard !liveShown else { return }

        let panelStillClearing = panelClosedAt.map { Date().timeIntervalSince($0) < handoffDelay } ?? false
        guard panelStillClearing else {
            withAnimation(.spring(response: 0.45 * motionScale, dampingFraction: 0.82)) {
                liveShown = true
            }
            return
        }

        let work = DispatchWorkItem {
            trace("handoff fires")
            guard wantsLive else { return }
            withAnimation(.spring(response: 0.45 * motionScale, dampingFraction: 0.82)) {
                liveShown = true
            }
        }
        liveHandoff = work
        DispatchQueue.main.asyncAfter(deadline: .now() + handoffDelay, execute: work)
    }

    /// Drives the outline's slow breath. See `outline(radius:)`.
    @State private var outlinePulse = false

    /// When the panel last began closing, so the strip knows whether the notch
    /// is still busy. Nil while the panel is open or has long since gone.
    @State private var panelClosedAt: Date?

    /// Layered pills instead of one morphing pill: the black notch shape is
    /// ALWAYS present as the base, the live strip and the glass panel each
    /// appear and vanish as their own layer, every one anchored to the top
    /// center. Nothing ever slides sideways — the strip fades out where it is
    /// (at its notch-aligned offset) while the panel drops STRAIGHT DOWN from
    /// the physical notch like a water drop, and returns into it on close.
    private var island: some View {
        ZStack(alignment: .top) {
            if liveShown && showExpanded {
                // The state the bug report describes, kept as a trace rather
                // than deleted: `liveVisible` now makes it unreachable on
                // screen, and this says so out loud if that ever stops being
                // true. Gated behind HASHNOTCH_DEBUG=island, so it costs a
                // string comparison and nothing else.
                let _ = trace("strip suppressed while the panel is open")
            }
            collapsedIsland

            if liveVisible {
                liveIsland
                    // Aligns the strip's internal gap with the PHYSICAL notch
                    // (the sides are unequal, so a centered strip would sit
                    // 64pt off).
                    .offset(x: state.liveCenterOffset)
                    // Grows sideways OUT of the notch: it starts exactly as wide
                    // as the notch, at full height, and stretches outward. The
                    // anchor is the notch's place inside the strip, not the
                    // strip's own centre — the sides are unequal, so anchoring
                    // to the centre would have it converge to a point that is
                    // not the notch.
                    .transition(.drop(
                        widthRatio: state.notchWidth / max(state.liveWidth, 1),
                        heightRatio: 1,
                        anchor: UnitPoint(x: state.notchAnchorInLiveStrip, y: 0)
                    ))
            }

            if showExpanded {
                expandedIsland
                    // The water drop. It forms at exactly the notch's width and
                    // almost no height — so it reads as the notch itself
                    // swelling — then stretches DOWN and OUT, and settles with a
                    // soft wobble (the opening spring undershoots its damping
                    // for precisely that). Uniform scaling was the old mistake:
                    // it made the panel balloon from a point in the middle of
                    // nowhere, which at speed is indistinguishable from a pop.
                    .transition(.drop(
                        widthRatio: state.notchWidth / max(state.expandedWidth, 1),
                        heightRatio: 0.04,
                        anchor: .top,
                        // Full black from the first frame. See the note on
                        // `drop` — fading a black panel in over a white desktop
                        // reads as a grey ghost, and the panel is supposed to be
                        // the notch stretching rather than a window appearing.
                        arrivesOpaque: true
                    ))
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { onIslandSize?(geo.size) }
                    .onChange(of: geo.size) { size in onIslandSize?(size) }
            }
        )
        // Opening springs overshoot slightly for the water-drop wobble; closing
        // springs are fully damped, because a bouncing close reads as a crash.
        // The motion setting scales all four responses together, so calm and
        // lively stay recognisably the same animation.
        // Opening keeps a trace of overshoot — the drop landing — but only a
        // trace. At 0.62 the panel visibly bounced past its height and rang
        // back, which reads as the panel wobbling rather than as it arriving,
        // and any bounce is a stretch of motion during which the whole panel is
        // being scaled and redrawn for no reason anybody asked for. At 0.82 it
        // overshoots by a hair and settles, which is the difference between a
        // drop landing and a drop splashing. Closing stays fully damped,
        // because a bouncing close reads as a crash.
        .animation(
            showExpanded
                ? .spring(response: 0.52 * motionScale, dampingFraction: 0.82)
                : .spring(response: 0.42 * motionScale, dampingFraction: 0.98),
            value: showExpanded
        )
        // Tracks what is DRAWN, not the intent behind it. Animating on
        // `liveShown` while the layer keyed off `liveVisible` meant the two
        // could disagree, and a spring driven by the wrong value is how a
        // removal ends up with no animation attached to it at all.
        .animation(
            liveVisible
                ? .spring(response: 0.45 * motionScale, dampingFraction: 0.82)
                : .spring(response: 0.30 * motionScale, dampingFraction: 1.0),
            value: liveVisible
        )
        // Handing the strip from one feature to another.
        //
        // The strip hugs its content, so swapping owners changes its width — a
        // track title and artwork give way to four words, or the other way
        // about. Nothing animated that, so the pill jumped to its new size in a
        // single frame while the content cross-faded, which read as the strip
        // slamming shut and reopening in the middle of a hand-off. Plugging in
        // a charger while music played did it every time, because that is
        // exactly when one feature takes the strip and gives it straight back.
        //
        // Fully damped: this is a hand-off between two things that are both
        // already there, not an arrival, and a bounce would draw the eye to the
        // furniture rather than to what it now says.
        .animation(
            .spring(response: 0.38 * motionScale, dampingFraction: 1.0),
            value: liveFeature?.id
        )
    }

    // MARK: The three pills

    /// The permanent base: a black shape the size of the notch, so the island
    /// reads as one piece with the hardware in every state.
    /// The black notch shape, always present as the base layer.
    ///
    /// It carries NO outline, and that is not an omission. This layer is
    /// exactly the size of the physical notch and sits directly behind it, so
    /// the hardware covers all of it but the last point or two along the
    /// bottom. An outline drawn here is therefore invisible except for that
    /// bottom sliver — which appears as a stray line running along the underside
    /// of the physical notch, in the middle of the strip, joined to nothing.
    ///
    /// Nothing is lost by leaving it off. The tint is only ever set while the
    /// live strip is showing, and the strip is drawn on top of this layer and
    /// carries the outline itself — so every state that has a colour to show
    /// already shows it, on the shape that is actually visible.
    private var collapsedIsland: some View {
        pillShape(radius: 10)
            .fill(Color.black)
            .frame(width: state.collapsedWidth, height: state.collapsedHeight)
    }

    /// The colour the island is wearing, or nil when nothing is asking for one.
    ///
    /// Taken from whichever feature currently owns the strip, so the rule that
    /// decides whose words are shown also decides whose colour is worn and two
    /// features can never argue over it.
    private var outlineTint: Color? {
        liveVisible ? liveFeature?.outlineTint : nil
    }

    /// A line of colour traced around the island's own edge.
    ///
    /// Drawn as a stroke on the island's own outline rather than as a shadow
    /// behind it, because the island sits against the physical notch: anything
    /// that spreads outward lands on the bezel, where there is no screen to
    /// light up, and looks like a smudge on the black plastic.
    ///
    /// Three sides, never four — see `IslandOutlineShape`. Stroking the closed
    /// silhouette ran the colour straight across the top and turned it through
    /// two hard right angles, in the one place that is not an edge at all: up
    /// there is bezel, or menu bar. The ends are faded out as they approach it,
    /// so the colour runs off underneath rather than stopping dead against it.
    ///
    /// Two passes — a crisp inner line and a softer wider one — because a
    /// single hairline against black reads as a drawing error at a glance,
    /// while the blurred pass alone has no edge to it. Together they read as
    /// the glass itself being lit.
    ///
    /// **Always present, never inserted.** The colour changes; the view stays.
    /// Adding and removing it meant that handing the strip from one feature to
    /// another — a charging notice ending and the music coming back — tore one
    /// outline down and built another in the very moment the pill was resizing
    /// underneath, so the colour jumped and flickered through a resize instead
    /// of following it. Keeping the view and animating the tint to and from
    /// clear makes every handover a cross-fade, including the handover to
    /// nothing at all.
    private func outline(radius: CGFloat) -> some View {
        let tint = outlineTint
        return ZStack {
            IslandOutlineShape(radius: radius)
                .stroke(tint ?? .clear, style: outlineStroke(displayScale))
            IslandOutlineShape(radius: radius)
                .stroke((tint ?? .clear).opacity(0.28), style: outlineGlow(displayScale))
                .blur(radius: 1.0)
        }
        // Flush with the island's own edge, all the way round.
        //
        // It used to be drawn a few points BELOW the pill, because the strip
        // was exactly as tall as the physical notch: its bottom edge was level
        // with the notch's underside, so a flush line was behind the hardware
        // for the notch's whole width and survived only on the two shoulders.
        // Dropping it fixed the middle and spoiled the shoulders — there the
        // line left the black and floated over the desktop, a hairline with a
        // visible gap between it and the pill it belongs to.
        //
        // The strip now hangs `NotchState.liveLip` points below the notch, so
        // there is black under the hardware for the line to sit on, and the
        // line can go back to tracing the edge exactly. See `liveLip`.
        // The slow breath, which is what makes it catch the eye from across a
        // desk. A steady ring is easy to stop seeing.
        .opacity(outlinePulse ? 1.0 : 0.55)
        .animation(
            .easeInOut(duration: 1.4 * motionScale).repeatForever(autoreverses: true),
            value: outlinePulse
        )
        // And the colour itself cross-fades, so a handover between features is
        // one continuous change rather than a swap.
        .animation(.easeInOut(duration: 0.42 * motionScale), value: tint)
        .onAppear { outlinePulse = true }
        .allowsHitTesting(false)
    }

    /// The line is CENTRED on the island's edge, not tucked inside it.
    ///
    /// `strokeBorder` was tried, on the reasoning `NotchShape` already gives for
    /// the island's own hairline: half a line hanging outside softens the join
    /// with the bezel. That reasoning does not carry to the bottom edge here,
    /// and the geometry says why. The live strip is exactly as tall as the
    /// physical notch — `liveHeight` is the notch's own height, deliberately,
    /// so the idle shape has no lip poking out below the hardware. So the pill's
    /// bottom edge is level with the notch's underside, and insetting the stroke
    /// lifted the bottom line INTO the band the hardware covers: it disappeared
    /// behind the notch across the middle and survived only on the two
    /// shoulders, leaving a line broken in half with the notch sitting in the
    /// gap.
    ///
    /// Centred, half the line falls just below that edge, onto screen that is
    /// actually visible, and the bottom runs unbroken from one side to the
    /// other. The half point that hangs outside along the sides sits in the
    /// menu-bar band, where there is nothing for it to halo against.
    ///
    /// Round ends, because the line has two.
    ///
    /// It runs up both sides and stops where the island meets the screen. On
    /// this hardware that is the bezel, so the ends are never seen — but on a
    /// display with no notch the island hangs below the menu bar and they are,
    /// and a flat end there reads as the line having been cut off. Round reads
    /// as finished.
    ///
    /// A gradient mask was tried first, fading the top of the line away. It
    /// looked worse than what it replaced: the line thinned out and vanished a
    /// third of the way up each side, so instead of an outline the island wore
    /// two short green marks near its bottom corners with nothing joining them.
    /// A hairline, not a band.
    ///
    /// This began at 2 points with a 4.5-point glow behind it, which on a strip
    /// only 28 points tall is a stripe rather than an edge — the colour stopped
    /// reading as the island being lit and started reading as a border drawn
    /// around it, and the wide blurred pass left a halo on the black.
    ///
    /// Chosen by rendering the weights offscreen at the strip's real
    /// proportions, with the hardware notch masked in front, and looking at
    /// them side by side rather than reasoning about numbers. A point was too
    /// heavy and its glow left a visible bloom on the black; what reads as
    /// modern is a bright hairline with barely any halo behind it.
    ///
    /// So the line is **one device pixel**, whatever the display: half a point
    /// on Retina, a whole point where there is no Retina to halve. Asked of the
    /// environment rather than hard-coded, because 0.5 on a display that cannot
    /// draw it is not a finer line, it is a smeared one.
    private func outlineStroke(_ scale: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: 1 / max(scale, 1), lineCap: .round)
    }

    /// A whisper of glow, so the line has depth without a halo. Kept in
    /// proportion to the line rather than fixed, for the same reason.
    private func outlineGlow(_ scale: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: 2.4 / max(scale, 1), lineCap: .round)
    }

    private var liveIsland: some View {
        // The black pill HUGS its content (no trailing dead space after the
        // name), but sits left-anchored inside a fixed-width positioning box.
        // Keeping the box fixed means the notch gap stays pinned and the strip
        // never shifts as the title changes; only the visible pill shrinks to
        // fit.
        liveContent
            .background(
                // No shadow. The strip is pretending to BE the notch — the same
                // piece of black glass, just wider — and a shadow underneath
                // says the opposite: that this is a panel floating above the
                // screen. On a light background it drew a visible grey band
                // under the menu bar that appeared and vanished every time
                // something became live, which is both wrong and distracting.
                //
                // The physical notch casts no shadow, so neither does this. The
                // dropped panel keeps its own, because that one genuinely IS a
                // surface hanging below the bar and reads as depth rather than
                // as a mistake.
                Color.black.clipShape(pillShape(radius: 14))
            )
            // The outline goes HERE, on the same view the black pill is drawn
            // behind — before the positioning frame below, never after.
            //
            // That frame is a fixed-width box the pill sits left-anchored
            // inside, so the notch gap stays pinned while the title changes
            // length. Tracing the box instead of the pill drew the colour
            // around a rectangle far wider than the black, ending in mid-air
            // past the end of the words with nothing underneath it.
            .overlay(outline(radius: 14))
            .frame(width: state.liveWidth, height: state.liveHeight, alignment: .leading)
    }

    /// The drop-down panel. It first appears as a solid-black box (matching the
    /// notch) and, once `panelRevealed` flips shortly after, crossfades to
    /// Control-Center glass while its contents fade in. The content is always
    /// laid out (just invisible at first) so the black box is full panel size
    /// from the start and nothing resizes on the reveal.
    private var expandedIsland: some View {
        VStack(spacing: 0) {
            notchShoulders
            expandedContent
                .padding(.top, 16)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
        }
            .opacity(panelRevealed ? 1 : 0)
            .frame(width: state.expandedWidth, alignment: .top)
            .background(
                ZStack {
                    Color.black
                    // Solid black is not "no glass" — it is the black beat held
                    // permanently, which is why the reveal still crossfades.
                    if settings.appearance.panelFill == .glass {
                        ZStack {
                            VisualEffectView(material: .hudWindow)
                            // A heavy scrim, not a hint of one.
                            //
                            // Frosted glass takes its brightness from whatever
                            // is behind the window, and every label in this
                            // panel is white. Over a dark desktop 0.15 was
                            // plenty; over a white document the glass came up
                            // pale and the text sat on it almost invisibly. The
                            // panel has to be readable over ANY background, and
                            // the only thing that guarantees that is darkening
                            // it enough that what shows through is texture
                            // rather than brightness. It still reads as glass —
                            // shapes and motion behind it are still there.
                            Color.black.opacity(0.45)
                        }
                        .opacity(panelRevealed ? 1 : 0)
                    }
                }
                .clipShape(pillShape(radius: panelRadius))
                .overlay(
                    pillShape(radius: panelRadius)
                        .strokeBorder(Color.white.opacity(panelRevealed ? 0.12 : 0), lineWidth: 0.7)
                )
                // No shadow, on any system.
                //
                // It was already softened once and already dropped on the
                // oldest system for cost. Filmed in slow motion against a white
                // desktop it was still the most obvious thing on screen: a wide
                // grey halo that grew and shrank around the panel through every
                // open and close, and lingered as a smear while the panel was
                // small. That is the "shadow that keeps showing and
                // disappearing" — the strip's was the other one.
                //
                // Nothing is lost. A shadow says an object floats above a
                // surface, and this object is supposed to be part of the
                // hardware at the top of the screen: the physical notch casts
                // none, so neither should what pretends to be it. The panel is
                // still plainly a surface — it has its own fill and a hairline
                // along its edge.
            )
    }

    private func pillShape(radius: CGFloat) -> NotchShape {
        NotchShape(radius: radius)
    }

    // MARK: Live (flanks the notch)

    private var liveContent: some View {
        HStack(spacing: 0) {
            // Leading stays a FIXED width so the artwork hugs the notch (6pt,
            // iPhone-style) and the notch gap lands in the same place every
            // time. The trailing side HUGS its content — the title's own cap
            // (it marquees past it) plus a little breathing room — so the pill
            // ends right after the name instead of reserving dead black space.
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                if let feature = liveFeature,
                   let view = feature.makeCompactLeadingView(context: context) { view }
            }
            .padding(.trailing, 6)
            .frame(width: state.liveLeadingWidth, alignment: .trailing)

            Color.clear.frame(width: state.notchWidth, height: state.notchHeight)

            HStack(spacing: 6) {
                if let feature = liveFeature,
                   let view = feature.makeCompactTrailingView(context: context) { view }
            }
            // 10, not 18. The artwork on the other side hugs the notch at 6, so
            // an 18pt gap here made the two sides visibly unequal — the title
            // floated away from the hardware while the picture sat against it,
            // and the strip read as two separate things rather than one piece
            // wrapped around the notch. Still clear of the notch's rounded
            // corner, which is what the extra points were buying.
            .padding(.leading, 10)
            .padding(.trailing, 12)
            // The trailing side is what actually overran: two features' titles
            // came to roughly twice the strip's whole budget, so the pill grew
            // past the width its own centring is computed from and slid across
            // the notch. One feature fits; the cap makes that structural rather
            // than a thing each feature has to remember.
            .frame(maxWidth: state.liveTrailingWidth, alignment: .leading)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: state.notchHeight)
        .font(.system(size: 11, weight: .semibold, design: .rounded))
    }

    // MARK: Expanded (clean vertical list, below the notch)

    /// The panel's rows, with a hairline between each feature.
    ///
    /// Every feature was drawing its own heading and its own rows into one
    /// evenly spaced column, so a dozen unrelated readouts arrived as a single
    /// undifferentiated list — the eye had nothing to tell it where the
    /// temperatures stopped and the timer began. Equal spacing between things
    /// says they are equally related, and these are not: a section is a group,
    /// and between groups there should be a boundary.
    ///
    /// A one-pixel line and a little more room around it is the whole fix. The
    /// separator only ever goes BETWEEN features, never above the first or
    /// below the last, so the panel keeps clean edges.
    private var expandedContent: some View {
        let sections = enabledFeatures.compactMap { feature -> (id: String, view: AnyView)? in
            guard let detail = feature.makeExpandedView(context: context) else { return nil }
            return (feature.id, detail)
        }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                if index > 0, settings.appearance.separatorThickness > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(settings.appearance.separatorOpacity))
                        .frame(height: settings.appearance.separatorThickness)
                        .frame(width: Panel.rowWidth)
                        .padding(.vertical, 9)
                }
                section.view
            }
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
    }

    /// The app's controls, in the band of panel that shows either side of the
    /// physical notch: quit on the left, settings on the right.
    ///
    /// These used to hang off the row stack as an `.overlay(alignment:
    /// .topTrailing)` with a hand-tuned offset — which meant they were not in
    /// the layout at all, and simply floated above whichever feature happened to
    /// be first. That worked only while Now Playing led the panel, because its
    /// artwork block left a convenient hole in the top-right corner. Reordering
    /// the panel put a full-width row there instead and the buttons landed on
    /// top of its value. Placing them by layout, in a band nothing else can
    /// occupy, means no ordering of features can collide with them again.
    ///
    /// The middle cell is the hardware. Nothing is ever drawn in it — the notch
    /// is physically in front of the panel — so it is reserved rather than
    /// filled, and the two buttons are pushed out to the panel's own edges.
    /// Each control sits in the middle of its shoulder — centred between the
    /// panel's edge and the hardware, and centred in the band's height. Pushed
    /// out to the panel's edge they read as having been squeezed into a corner;
    /// centred, the two areas look like the places they were meant for.
    private var notchShoulders: some View {
        HStack(spacing: 0) {
            IslandControlButton(
                symbol: "power",
                tint: Color(red: 1.0, green: 0.35, blue: 0.35),
                help: "Quit HashNotch"
            ) {
                // Put the panel away before asking. The question is about the
                // whole app, not about the panel, and leaving it hanging over
                // the screen behind the question makes the two look related.
                //
                // `dismissAll`, not `state.setExpanded(false)`. Setting the
                // state alone is what made this button look broken: the pointer
                // is still on the panel, so the next mouse-moved event found it
                // inside the keep-open zone and reopened the panel before the
                // question was even up. Only the controller can tell hover to
                // stand down for long enough to get out of the way.
                //
                // Asked immediately afterwards rather than after the closing
                // spring. The wait existed because the old system alert blocked
                // the run loop and would have frozen the panel mid-close; the
                // question is now an ordinary window, so the panel finishes
                // closing underneath it.
                context.dismissAll()
                context.confirmQuit()
            }
            .frame(width: state.shoulderWidth)

            Color.clear
                .frame(width: state.notchWidth, height: state.notchHeight)

            IslandControlButton(
                symbol: "gearshape.fill",
                tint: .white,
                turnsOnHover: true,
                help: "Settings"
            ) {
                context.openSettings()
            }
            .frame(width: state.shoulderWidth)
        }
        .frame(width: state.expandedWidth, height: state.notchHeight, alignment: .center)
    }

    /// The one feature that owns the strip right now.
    ///
    /// Highest `livePriority` among those that are actually live, ties going to
    /// whichever was registered first so the choice never wobbles between
    /// redraws. When the winner's moment passes — a notice dismissing itself,
    /// a warning timing out — it drops out of `activeIDs` and the strip hands
    /// straight back to whatever was underneath, usually the music.
    private var liveFeature: NotchFeature? {
        var best: (feature: NotchFeature, priority: Int, index: Int)?
        for (index, feature) in enabledFeatures.enumerated()
        where presence.activeIDs.contains(feature.id) {
            let priority = feature.livePriority
            if let current = best,
               priority < current.priority || (priority == current.priority && index > current.index) {
                continue
            }
            best = (feature, priority, index)
        }
        return best?.feature
    }

    /// The enabled features in draw order. Derived once per settings change by
    /// the registry rather than re-sorted here on every body evaluation — this
    /// is read twice per body (once to pick the strip's owner, once to build the
    /// panel) and the body runs at animation frequency.
    private var enabledFeatures: [NotchFeature] {
        registry.orderedEnabled(using: settings)
    }
}

/// One of the island's own controls: a soft disc that lifts under the pointer
/// and presses in when clicked.
///
/// At rest it is a faint disc rather than a bare glyph. A symbol floating on
/// black reads as decoration; the disc says it is a control before anyone has
/// to hover it to find out. Everything then moves together on one spring — the
/// fill, the ring, the glyph's brightness, the lift and the glow — because a
/// control whose parts arrive on different curves feels loose rather than
/// responsive.
private struct IslandControlButton: View {
    let symbol: String
    var tint: Color = .white
    /// Whether the glyph turns under the pointer. True for the gear, where it
    /// reads as the thing it depicts; wrong for the power symbol, which is not
    /// a thing that turns.
    var turnsOnHover: Bool = false
    let help: String
    let action: () -> Void

    @State private var hovering = false

    private var size: CGFloat { 26 }

    var body: some View {
        Button(action: action) {
            // The symbol alone, with no disc behind it.
            //
            // These sit in the band of panel either side of the notch — black,
            // a few points from the hardware — and a filled ring around each
            // one drew two more shapes up there competing with the one shape
            // the island is trying to be. The glyph carries the meaning on its
            // own; brightening it on hover is all the feedback a target this
            // size needs.
            //
            // The hit area stays the full 26pt square regardless, so nothing
            // got harder to click by getting quieter to look at.
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovering ? tint : Color.white.opacity(0.5))
                .rotationEffect(.degrees(turnsOnHover && hovering ? 60 : 0))
                .frame(width: size, height: size)
                // The lift is small on purpose. These sit a few points from the
                // physical notch, and anything that grows noticeably up here
                // reads as the hardware moving.
                .scaleEffect(hovering ? 1.10 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.30, dampingFraction: 0.68), value: hovering)
        .help(help)
    }
}

/// Presses in under the click and springs back.
///
/// A separate style rather than more state on the button, because whether a
/// button is being pressed is the one thing a SwiftUI view cannot see about
/// itself — it belongs to the button's own configuration.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: configuration.isPressed)
    }
}
