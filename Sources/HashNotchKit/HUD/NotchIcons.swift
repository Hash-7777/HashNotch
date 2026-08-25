import SwiftUI

/// The panel's own drawn marks: one small picture per heading, so a row can be
/// found by shape before it is read.
///
/// **Why these are drawn rather than picked.** The panel is a dense list of
/// unrelated readings, and the eye needs somewhere to land before it starts
/// reading words. A mark beside each heading gives it that. The obvious way to
/// get one is `Image(systemName:)`, and it was not taken, for two reasons that
/// are about honesty rather than taste:
///
/// - **A missing symbol draws nothing, silently.** A system symbol name that
///   this version of macOS does not have is not an error; it is an empty space
///   where the mark should be. The oldest Mac this app supports is four
///   releases behind the one it is built on, and nothing in a build here would
///   notice a mark that is blank there.
/// - **A borrowed set cannot be held to one shape.** These are eleven marks
///   that have to look like eleven members of one family at nine points, on
///   black. Drawing them against one grid, at one stroke weight, is the only
///   way to be sure of that — and it is what was already done for the battery,
///   for the same reason.
///
/// Everything here is laid out on a 100 x 100 grid and scaled to whatever box
/// it is asked for, so a mark is the same drawing at every size and the family
/// cannot drift apart a mark at a time. The geometry is separate from the view
/// so the checks can measure it.
public enum NotchIcon: String, CaseIterable, Sendable {
    case cpu
    case memory
    case storage
    case internet
    case dataUsed
    case temperature
    case tokens
    case timer
    case microphone
    case airpods
    case activities
}

/// One piece of a mark: a path, and whether it is drawn as a line or as a
/// solid.
public struct NotchIconPart {
    public enum Style: Equatable {
        case stroke(CGFloat)
        case fill
    }

    public let path: Path
    public let style: Style

    public init(path: Path, style: Style) {
        self.path = path
        self.style = style
    }
}

/// Where every mark's lines actually are.
///
/// A plain function from a name and a box to a list of paths, with no view and
/// no environment anywhere near it, so the checks can ask the real drawing
/// whether it stays inside its box and whether any two marks came out the same.
public enum NotchIconGeometry {
    /// The grid every mark is drawn on. Nothing here is in points.
    public static let grid: CGFloat = 100

    /// One line weight for the whole family, on the grid. Every outline is
    /// drawn at this, so no mark can end up looking heavier than the one under
    /// it.
    public static let strokeWeight: CGFloat = 9

    /// The weight for lines drawn INSIDE an outline — the bars across a memory
    /// chip, the meridian on the globe.
    ///
    /// Lighter than the outline, and it has to be. At nine points a mark is
    /// about twenty pixels across, and an interior line at the full weight
    /// leaves a gap of well under a pixel between itself and the edge it sits
    /// beside; the two ink into each other and the mark becomes a blob with a
    /// shape that used to mean something. This was measured rather than
    /// guessed: the first draft of this family drew everything at one weight,
    /// and the processor, the memory chip and the globe were all unreadable at
    /// the size they are actually used at, while looking perfectly good at the
    /// size they were designed at.
    public static let detailWeight: CGFloat = 6.5

    /// The marks, scaled into `box`.
    public static func parts(for icon: NotchIcon, in box: CGRect) -> [NotchIconPart] {
        let scale = min(box.width, box.height) / grid
        let width = strokeWeight * scale
        return unscaled(icon).map { part in
            var transform = CGAffineTransform(translationX: box.minX, y: box.minY)
            transform = transform.scaledBy(x: scale, y: scale)
            let scaled = part.path.applying(transform)
            switch part.style {
            case .stroke: return NotchIconPart(path: scaled, style: .stroke(width))
            case .fill: return NotchIconPart(path: scaled, style: .fill)
            }
        }
    }

    // MARK: The marks

    /// Every mark on the 100 x 100 grid, in the order it is drawn.
    public static func unscaled(_ icon: NotchIcon) -> [NotchIconPart] {
        switch icon {
        case .cpu: return cpu
        case .memory: return memory
        case .storage: return storage
        case .internet: return internet
        case .dataUsed: return dataUsed
        case .temperature: return temperature
        case .tokens: return tokens
        case .timer: return timer
        case .microphone: return microphone
        case .airpods: return airpods
        case .activities: return activities
        }
    }

    /// A chip with legs on all four sides and a core in the middle. The core is
    /// what separates it from the memory chip beside it in the panel: one has a
    /// single square at its centre, the other has bars.
    private static var cpu: [NotchIconPart] {
        var parts: [NotchIconPart] = []
        parts.append(NotchIconPart(
            path: Path(roundedRect: CGRect(x: 28, y: 28, width: 44, height: 44),
                       cornerRadius: 8, style: .continuous),
            style: .stroke(strokeWeight)))
        parts.append(NotchIconPart(
            path: Path(roundedRect: CGRect(x: 42, y: 42, width: 16, height: 16),
                       cornerRadius: 3.5, style: .continuous),
            style: .fill))
        // Two legs a side rather than three. Three at nine points puts a gap of
        // less than a third of a point between them, which fills in and reads
        // as a smudge along the edge instead of as legs.
        var legs = Path()
        for offset in [41.0, 59.0] {
            legs.move(to: CGPoint(x: offset, y: 28)); legs.addLine(to: CGPoint(x: offset, y: 12))
            legs.move(to: CGPoint(x: offset, y: 72)); legs.addLine(to: CGPoint(x: offset, y: 88))
            legs.move(to: CGPoint(x: 28, y: offset)); legs.addLine(to: CGPoint(x: 12, y: offset))
            legs.move(to: CGPoint(x: 72, y: offset)); legs.addLine(to: CGPoint(x: 88, y: offset))
        }
        parts.append(NotchIconPart(path: legs, style: .stroke(detailWeight)))
        return parts
    }

    /// A memory chip: the same body as the processor, with bars across it and
    /// legs on two sides only. A pair that reads as a pair — they are both
    /// chips — while still being told apart at a glance.
    private static var memory: [NotchIconPart] {
        var parts: [NotchIconPart] = []
        parts.append(NotchIconPart(
            path: Path(roundedRect: CGRect(x: 18, y: 26, width: 64, height: 42),
                       cornerRadius: 8, style: .continuous),
            style: .stroke(strokeWeight)))
        var bars = Path()
        for x in [39.0, 61.0] {
            bars.move(to: CGPoint(x: x, y: 38))
            bars.addLine(to: CGPoint(x: x, y: 56))
        }
        parts.append(NotchIconPart(path: bars, style: .stroke(detailWeight)))
        // Along the bottom edge only, the way the pins on a memory module are.
        // It is also the one thing that has to differ from the processor beside
        // it at a size where the bars inside are barely resolvable: legs all
        // round is a processor, legs along one edge is memory.
        var legs = Path()
        for x in [35.0, 65.0] {
            legs.move(to: CGPoint(x: x, y: 68)); legs.addLine(to: CGPoint(x: x, y: 86))
        }
        parts.append(NotchIconPart(path: legs, style: .stroke(detailWeight)))
        return parts
    }

    /// Stacked platters. The oldest picture of a disk there is, and still the
    /// one nobody has to be taught.
    private static var storage: [NotchIconPart] {
        var parts: [NotchIconPart] = []
        let radiusX: CGFloat = 32, radiusY: CGFloat = 13
        let top: CGFloat = 22, bottom: CGFloat = 78
        parts.append(NotchIconPart(
            path: Path(ellipseIn: CGRect(x: 50 - radiusX, y: top - radiusY,
                                         width: radiusX * 2, height: radiusY * 2)),
            style: .stroke(strokeWeight)))
        var body = Path()
        body.move(to: CGPoint(x: 50 - radiusX, y: top))
        body.addLine(to: CGPoint(x: 50 - radiusX, y: bottom))
        body.addCurve(
            to: CGPoint(x: 50 + radiusX, y: bottom),
            control1: CGPoint(x: 50 - radiusX, y: bottom + radiusY * 1.35),
            control2: CGPoint(x: 50 + radiusX, y: bottom + radiusY * 1.35))
        body.addLine(to: CGPoint(x: 50 + radiusX, y: top))
        parts.append(NotchIconPart(path: body, style: .stroke(strokeWeight)))
        // The second platter, which is what makes it a stack rather than a cup.
        var middle = Path()
        middle.move(to: CGPoint(x: 50 - radiusX, y: 50))
        middle.addCurve(
            to: CGPoint(x: 50 + radiusX, y: 50),
            control1: CGPoint(x: 50 - radiusX, y: 50 + radiusY * 1.35),
            control2: CGPoint(x: 50 + radiusX, y: 50 + radiusY * 1.35))
        parts.append(NotchIconPart(path: middle, style: .stroke(strokeWeight)))
        return parts
    }

    /// A globe. Not an aerial or a set of arcs: what the row reports is the
    /// internet, and the arcs are a picture of Wi-Fi — which is one of several
    /// ways the traffic in that row might have travelled, and the row does not
    /// claim to know which.
    private static var internet: [NotchIconPart] {
        var parts: [NotchIconPart] = []
        let radius: CGFloat = 33
        parts.append(NotchIconPart(
            path: Path(ellipseIn: CGRect(x: 50 - radius, y: 50 - radius,
                                         width: radius * 2, height: radius * 2)),
            style: .stroke(strokeWeight)))
        parts.append(NotchIconPart(
            path: Path(ellipseIn: CGRect(x: 50 - 14, y: 50 - radius,
                                         width: 28, height: radius * 2)),
            style: .stroke(detailWeight)))
        var equator = Path()
        equator.move(to: CGPoint(x: 50 - radius, y: 50))
        equator.addLine(to: CGPoint(x: 50 + radius, y: 50))
        parts.append(NotchIconPart(path: equator, style: .stroke(detailWeight)))
        return parts
    }

    /// Three bars, rising. A quantity that has been piling up all day, which is
    /// exactly what the row under it reports — and deliberately not a picture
    /// of speed, since the row above it is the one about speed.
    private static var dataUsed: [NotchIconPart] {
        var parts: [NotchIconPart] = []
        let bottom: CGFloat = 82, width: CGFloat = 16
        for (x, height) in [(16.0, 26.0), (42.0, 44.0), (68.0, 62.0)] {
            parts.append(NotchIconPart(
                path: Path(roundedRect: CGRect(x: x, y: bottom - height,
                                               width: width, height: height),
                           cornerRadius: 5, style: .continuous),
                style: .fill))
        }
        return parts
    }

    /// A thermometer, drawn solid.
    ///
    /// The outlined version of this — a tube, a bulb, and two marks up the side
    /// — was the least readable mark in the family by a distance at the size a
    /// section heading uses. The marks closed up against the tube and the whole
    /// thing came out looking like a key. Solid holds its shape all the way
    /// down, and the marks are far enough off the tube to stay marks.
    private static var temperature: [NotchIconPart] {
        var parts: [NotchIconPart] = []
        var body = Path()
        body.addPath(Path(roundedRect: CGRect(x: 27, y: 10, width: 18, height: 62),
                          cornerRadius: 9, style: .circular))
        body.addEllipse(in: CGRect(x: 36 - 19, y: 52, width: 38, height: 38))
        parts.append(NotchIconPart(path: body, style: .fill))
        var ticks = Path()
        for y in [26.0, 42.0] {
            ticks.move(to: CGPoint(x: 58, y: y))
            ticks.addLine(to: CGPoint(x: 80, y: y))
        }
        parts.append(NotchIconPart(path: ticks, style: .stroke(detailWeight)))
        return parts
    }

    /// A robot's head. The one mark in the set that stands for something that
    /// is not a part of this Mac, and the only one whose job is to say "a
    /// machine did this" rather than to name a component.
    ///
    /// Two eyes and an aerial, and nothing else. A mouth, a grille and side
    /// ears all went in and all came back out: at nine points they close up
    /// against the eyes and the head becomes a filled square with a bump on
    /// top. What survives being small is a wide-set pair of solid eyes inside
    /// an outline.
    private static var tokens: [NotchIconPart] {
        var parts: [NotchIconPart] = []
        parts.append(NotchIconPart(
            path: Path(roundedRect: CGRect(x: 20, y: 32, width: 60, height: 50),
                       cornerRadius: 15, style: .continuous),
            style: .stroke(strokeWeight)))
        var eyes = Path()
        for x in [38.0, 62.0] {
            eyes.addEllipse(in: CGRect(x: x - 7, y: 50, width: 14, height: 14))
        }
        parts.append(NotchIconPart(path: eyes, style: .fill))
        var aerial = Path()
        aerial.move(to: CGPoint(x: 50, y: 32))
        aerial.addLine(to: CGPoint(x: 50, y: 20))
        parts.append(NotchIconPart(path: aerial, style: .stroke(detailWeight)))
        parts.append(NotchIconPart(
            path: Path(ellipseIn: CGRect(x: 42, y: 6, width: 16, height: 16)),
            style: .fill))
        return parts
    }

    /// A stopwatch rather than a clock face: a clock says what time it is, and
    /// this row is about a length of time running out.
    private static var timer: [NotchIconPart] {
        var parts: [NotchIconPart] = []
        let centre = CGPoint(x: 50, y: 58)
        let radius: CGFloat = 31
        parts.append(NotchIconPart(
            path: Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                         width: radius * 2, height: radius * 2)),
            style: .stroke(strokeWeight)))
        var crown = Path()
        crown.move(to: CGPoint(x: 38, y: 13))
        crown.addLine(to: CGPoint(x: 62, y: 13))
        parts.append(NotchIconPart(path: crown, style: .stroke(strokeWeight)))
        var stem = Path()
        stem.move(to: CGPoint(x: 50, y: 13))
        stem.addLine(to: CGPoint(x: 50, y: 27))
        parts.append(NotchIconPart(path: stem, style: .stroke(strokeWeight)))
        // The hand stops short of the rim, the way a real one does.
        var hand = Path()
        hand.move(to: centre)
        hand.addLine(to: CGPoint(x: 50, y: 40))
        parts.append(NotchIconPart(path: hand, style: .stroke(strokeWeight)))
        return parts
    }

    /// A microphone, outlined. It names the row that says an app has yours
    /// open; the app never opens one itself.
    private static var microphone: [NotchIconPart] {
        var parts: [NotchIconPart] = []
        parts.append(NotchIconPart(
            path: Path(roundedRect: CGRect(x: 37, y: 12, width: 26, height: 46),
                       cornerRadius: 13, style: .circular),
            style: .stroke(strokeWeight)))
        var cradle = Path()
        cradle.move(to: CGPoint(x: 24, y: 46))
        cradle.addCurve(
            to: CGPoint(x: 76, y: 46),
            control1: CGPoint(x: 24, y: 76),
            control2: CGPoint(x: 76, y: 76))
        parts.append(NotchIconPart(path: cradle, style: .stroke(strokeWeight)))
        var stand = Path()
        stand.move(to: CGPoint(x: 50, y: 70))
        stand.addLine(to: CGPoint(x: 50, y: 88))
        parts.append(NotchIconPart(path: stand, style: .stroke(strokeWeight)))
        return parts
    }

    /// Two buds, stems down.
    private static var airpods: [NotchIconPart] {
        var parts: [NotchIconPart] = []
        for x in [28.0, 72.0] {
            parts.append(NotchIconPart(
                path: Path(ellipseIn: CGRect(x: x - 16, y: 14, width: 32, height: 32)),
                style: .stroke(strokeWeight)))
            var stem = Path()
            stem.move(to: CGPoint(x: x, y: 46))
            stem.addLine(to: CGPoint(x: x, y: 84))
            parts.append(NotchIconPart(path: stem, style: .stroke(strokeWeight)))
        }
        return parts
    }

    /// A pulse. What this section carries is things happening, one after
    /// another, and a line with a beat in it is what that looks like.
    private static var activities: [NotchIconPart] {
        var path = Path()
        path.move(to: CGPoint(x: 10, y: 56))
        path.addLine(to: CGPoint(x: 30, y: 56))
        path.addLine(to: CGPoint(x: 42, y: 26))
        path.addLine(to: CGPoint(x: 58, y: 78))
        path.addLine(to: CGPoint(x: 70, y: 56))
        path.addLine(to: CGPoint(x: 90, y: 56))
        return [NotchIconPart(path: path, style: .stroke(strokeWeight))]
    }
}

/// A mark, drawn at a size and in a colour the caller chooses.
///
/// It takes its colour from whatever it sits beside rather than carrying one of
/// its own: a mark belongs to the words next to it, and a heading that is dimmer
/// than its readings should not have a bright picture in front of it.
public struct NotchIconView: View {
    let icon: NotchIcon
    let size: CGFloat
    let color: Color

    public init(_ icon: NotchIcon, size: CGFloat, color: Color) {
        self.icon = icon
        self.size = size
        self.color = color
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let box = CGRect(origin: .zero, size: canvasSize)
            for part in NotchIconGeometry.parts(for: icon, in: box) {
                switch part.style {
                case .stroke(let width):
                    context.stroke(
                        part.path,
                        with: .color(color),
                        style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                case .fill:
                    context.fill(part.path, with: .color(color))
                }
            }
        }
        .frame(width: size, height: size)
        // A picture that repeats the word beside it is noise to anything
        // reading the panel aloud.
        .accessibilityHidden(true)
    }
}
