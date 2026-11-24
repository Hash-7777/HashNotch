import AppKit
import Combine
import SwiftUI

/// Where the app's menu bar item is on screen, for the notch's live strip to
/// keep clear of. Nil while there is no item.
@MainActor
public final class MenuBarItemPlace: ObservableObject {
    @Published public internal(set) var frame: CGRect?
    public init() {}
}

/// The app's one item in the real menu bar: a small column per figure, its
/// word above its number, all drawn into one image.
///
/// Drawn rather than built from the button's title, because a title is one line
/// and these are two, and because one image is one redraw: the item changes at
/// most once per refresh, and only when a number in it has.
///
/// Clicking it opens a panel with the same figures at a size you can read
/// properly, and the menu bar's own preferences.
@MainActor
public final class StatusBarItem: NSObject, MenuBarItem {
    // The measurements, named so the checks can hold the item to them.
    package nonisolated static let labelSize: CGFloat = 7.5
    package nonisolated static let fontSize: CGFloat = 9.5
    /// Room between the word and the number under it.
    package nonisolated static let rowGap: CGFloat = 0
    /// Room between one figure's column and the next.
    package nonisolated static let columnGap: CGFloat = 5
    /// Room either side of the figures, inside the picture.
    package nonisolated static let sidePadding: CGFloat = 1
    /// Room either side of the picture, inside the item: the item's width is
    /// set outright rather than left to AppKit, so this is the margin the
    /// system would otherwise have added, a little tighter.
    package nonisolated static let itemInset: CGFloat = 6

    private let item: NSStatusItem
    /// What the item opens: built once with the item, so a click only shows
    /// something that already exists. Building it under the click held the
    /// main thread for several frames, measured on the running app.
    private let panel: MenuBarPanel
    /// The figures the panel shows. Its own copy, handed new figures only
    /// while it is open and once as it opens — so the view kept ready for the
    /// next click is not redrawn every refresh while nobody can see it.
    private let shown = MenuBarState()
    private var cancellables = Set<AnyCancellable>()
    private var figures: [MenuBarFigure] = []
    /// The bar's appearance the picture was last drawn for. Kept so a
    /// notification that the appearance may have changed redraws only when it
    /// actually has.
    private var drawnFor: NSAppearance.Name?
    /// The picture is drawn in the bar's colours as they were when it was
    /// drawn, so a switch between a light bar and a dark one redraws it.
    private var appearanceObservation: NSKeyValueObservation?
    /// Told where the item is, so the notch's strip can stop short of it.
    private let place: MenuBarItemPlace?
    private var moveObserver: NSObjectProtocol?

    /// - Parameter onSettings: opens the settings window on the menu-bar page.
    ///   The panel is put away first, so the two are never on screen at once.
    public init(
        settings: SettingsStore,
        meters: [MenuBarMeter],
        place: MenuBarItemPlace? = nil,
        onSettings: @escaping () -> Void
    ) {
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.place = place
        let shown = self.shown
        var close: () -> Void = {}
        self.panel = MenuBarPanel(content: MenuBarPanelView(
            settings: settings,
            state: shown,
            meters: meters,
            openSettings: {
                close()
                onSettings()
            }
        ))
        super.init()
        close = { [weak self] in self?.panel.hide() }

        // Named, so a place somebody drags it to with Command held is kept.
        // macOS keeps it with the app's own settings.
        item.autosaveName = "hashnotch.menubar"
        // Not removable by dragging it out. An item that could vanish that way
        // would leave its switches on in Settings with nothing to show for
        // them, and the switches would be lying. The panel takes it out.
        item.behavior = []
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePanel)
            // On the press, not the release, the way the system's own items
            // open — it is what makes opening one feel immediate.
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, let button = self.item.button,
                              Self.appearanceName(of: button) != self.drawnFor else { return }
                        self.display(self.figures)
                    }
                }
            }
        }

        // A figure switched on or off from inside the panel changes what it
        // holds; it is fitted again a turn later, once the view has the change.
        settings.$menuBarFigures.dropFirst()
            .merge(with: settings.$features.dropFirst().map { _ in settings.menuBarFigures })
            .sink { [weak self] _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.panel.refit() } }
            }
            .store(in: &cancellables)
    }

    public func display(_ figures: [MenuBarFigure]) {
        self.figures = figures
        if panel.isShown, shown.figures != figures { shown.figures = figures }
        guard let button = item.button else { return }
        let height = max(18, min(26, NSStatusBar.system.thickness))

        // Drawn once, here, into a bitmap at the screen's scale, in the bar's
        // colours as they are now — rather than handed over as a drawing for
        // AppKit to run again each time it decides to. And the item is given
        // its width outright, which is fixed by which figures are shown, so a
        // new number never asks the menu bar to lay itself out again. Those two
        // are most of what a refresh costs; reading the figures is a fraction
        // of a millisecond.
        let appearance = button.effectiveAppearance
        drawnFor = Self.appearanceName(of: button)
        var image = NSImage()
        appearance.performAsCurrentDrawingAppearance {
            image = Self.bitmap(
                of: Self.image(for: figures, height: height),
                scale: button.window?.backingScaleFactor ?? 2)
        }
        let width = image.size.width + Self.itemInset * 2
        if item.length != width { item.length = width }
        button.image = image
        reportPlace()
        // Spoken to VoiceOver, and deliberately not a hover tooltip. The item
        // already shows these figures, and on macOS 26 and later the system
        // draws the menu bar's items itself, so the button's own window is not
        // where the item is seen: a tooltip set on every refresh was raised by
        // AppKit wherever the pointer happened to be, anywhere on the screen.
        let spoken = figures.map { $0.reading?.spoken ?? "\($0.title), no reading yet" }
            .joined(separator: ", ")
        button.setAccessibilityLabel(spoken)
    }

    public func remove() {
        panel.hide()
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = nil
        NSStatusBar.system.removeStatusItem(item)
        place?.frame = nil
    }

    /// Say where the item is now, and keep saying it as it moves: the menu
    /// bar shifts it whenever an item beside it comes, goes or changes width.
    private func reportPlace() {
        guard let place, let window = item.button?.window else { return }
        if moveObserver == nil {
            moveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportPlace() }
            }
        }
        let frame = window.frame
        if place.frame != frame { place.frame = frame }
    }

    @objc private func togglePanel() {
        guard let button = item.button else { return }
        if !panel.isShown, shown.figures != figures { shown.figures = figures }
        panel.toggle(below: button)
    }

    // MARK: Drawing

    private static func appearanceName(of view: NSView) -> NSAppearance.Name? {
        view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
    }

    /// `image` drawn once into a bitmap of its own size at `scale`.
    package nonisolated static func bitmap(of image: NSImage, scale: CGFloat) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0,
              let rep = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: Int((size.width * scale).rounded(.up)),
                  pixelsHigh: Int((size.height * scale).rounded(.up)),
                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return image }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        let bitmap = NSImage(size: size)
        bitmap.addRepresentation(rep)
        return bitmap
    }

    /// Fixed-width digits, so a number changing never changes its width.
    package nonisolated static var font: NSFont {
        .monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
    }

    /// The word above each number: small, and spaced a little, the way a
    /// label on an instrument is.
    package nonisolated static var labelFont: NSFont {
        .systemFont(ofSize: labelSize, weight: .semibold)
    }

    package nonisolated static let labelKerning: CGFloat = 0.4

    package nonisolated static func labelWidth(_ label: String) -> CGFloat {
        (label as NSString).size(withAttributes: [.font: labelFont, .kern: labelKerning]).width
    }

    /// One figure's column width: its widest number, or its word if wider.
    package nonisolated static func columnWidth(widest: String, label: String) -> CGFloat {
        let text = (widest as NSString).size(withAttributes: [.font: font]).width
        return max(labelWidth(label), text).rounded(.up)
    }

    /// The whole item's width, which depends only on WHICH figures are shown —
    /// never on what they say — so nothing in the menu bar moves as they change.
    package nonisolated static func width(columns: [(widest: String, label: String)]) -> CGFloat {
        guard !columns.isEmpty else { return 0 }
        let total = columns.map { columnWidth(widest: $0.widest, label: $0.label) }.reduce(0, +)
        return total + columnGap * CGFloat(columns.count - 1) + sidePadding * 2
    }

    /// The height of the word and the number, one above the other.
    package nonisolated static var stackHeight: CGFloat {
        let label = labelFont.ascender - labelFont.descender
        let number = font.ascender - font.descender
        return (label + rowGap + number).rounded(.up)
    }

    /// The item's picture.
    ///
    /// Drawn in the menu bar's own text colours, resolved at the moment it is
    /// drawn, so it is right on a light bar and a dark one: the word in the
    /// bar's quieter colour, the number in its full one. A number at the point
    /// the panel turns it red is red here as well — colour that is always on is
    /// not a signal, so nothing else is coloured.
    package nonisolated static func image(for figures: [MenuBarFigure], height: CGFloat) -> NSImage {
        let widths = figures.map { columnWidth(widest: $0.widestText, label: $0.label) }
        let size = NSSize(
            width: width(columns: figures.map { ($0.widestText, $0.label) }),
            height: height)
        let image = NSImage(size: size, flipped: true) { _ in
            let font = Self.font
            let labelFont = Self.labelFont
            let labelHeight = labelFont.ascender - labelFont.descender
            let top = ((height - stackHeight) / 2).rounded()
            var x = sidePadding
            for (figure, column) in zip(figures, widths) {
                let high = figure.reading?.isHigh == true
                let label = NSAttributedString(
                    string: figure.label,
                    attributes: [
                        .font: labelFont,
                        .kern: labelKerning,
                        .foregroundColor: high ? NSColor.systemRed : NSColor.secondaryLabelColor,
                    ])
                label.draw(at: NSPoint(x: x + (column - label.size().width) / 2, y: top))
                let number = NSAttributedString(
                    string: figure.text,
                    attributes: [.font: font, .foregroundColor: high ? NSColor.systemRed : NSColor.labelColor])
                number.draw(at: NSPoint(
                    x: x + (column - number.size().width) / 2,
                    y: top + labelHeight + rowGap))
                x += column + columnGap
            }
            return true
        }
        // Not a template: a template image is drawn in one colour, and a red
        // number has to stay red. The colours above are the bar's own.
        image.isTemplate = false
        return image
    }
}

/// A glyph, drawn in SwiftUI at whatever size it is given.
public struct MenuBarGlyphView: View {
    let glyph: MenuBarGlyph
    let size: CGFloat
    let color: Color

    public init(_ glyph: MenuBarGlyph, size: CGFloat, color: Color) {
        self.glyph = glyph
        self.size = size
        self.color = color
    }

    public var body: some View {
        Canvas { context, canvasSize in
            for piece in glyph.pieces(in: CGRect(origin: .zero, size: canvasSize)) {
                context.fill(Path(piece.path), with: .color(color), style: FillStyle(eoFill: piece.evenOdd))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
