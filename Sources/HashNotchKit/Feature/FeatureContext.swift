import Foundation

/// Shared services handed to every feature when it builds its view.
///
/// This is how the core passes common things (theme, user settings, live
/// presence) to features without any feature depending on another. Extend this
/// type to share more — features opt in by reading what they need.
@MainActor
public final class FeatureContext {
    /// Visual tokens, re-derived from settings each time they are asked for, so
    /// a change of accent reaches every feature without any of them subscribing
    /// to anything.
    public var theme: Theme { baseTheme.tinted(settings.accent.color) }

    private let baseTheme: Theme
    public let settings: SettingsStore
    public let presence: LivePresence
    /// Whether the panel is open. Features that only draw inside it sample
    /// against this instead of running around the clock.
    public let visibility: PanelVisibility

    /// What happened while nobody was looking, once there is anything to say.
    ///
    /// The core fills this in; one feature draws it. Neither the features that
    /// supplied the numbers nor the one that shows them has to know the other
    /// exists — see `AwayDigest`.
    public let away: AwayReport

    /// Opens the customization window. The app wires this at launch; the
    /// island's gear button calls it (there is no menu-bar item).
    public var openSettings: () -> Void = {}

    /// Opens the customization window ON a particular page.
    ///
    /// For the case where the island has just told somebody that a switch is
    /// off. Sending them to a window and leaving them to find it themselves is
    /// most of the way to not having told them.
    public var openSettingsPage: (String) -> Void = { _ in }

    /// Shuts the panel. For the case where a feature is about to hand the user
    /// over to something else — a system permission dialog, say — and the panel
    /// would otherwise sit on top of the thing it just asked them to look at.
    ///
    /// A closure, like `openSettings`, rather than a method on
    /// `PanelVisibility`: that type reports whether anyone is looking, and a
    /// feature reaching in to change it would make an observation into a
    /// control that the island does not know was used.
    public var closePanel: () -> Void = {}

    /// Puts the panel AND the settings window away, and tells hover to stand
    /// down while it happens.
    ///
    /// `closePanel` is the polite version: it refuses while settings is holding
    /// the panel open, because a feature clearing the screen for a permission
    /// prompt has no business closing a window somebody is working in. The quit
    /// button is the case that needs the other one — it is about the whole app,
    /// so everything the app has on screen goes, whatever is holding it open.
    ///
    /// The standing-down is the part that actually matters, and doing it by
    /// hand is what made the button look broken: the pointer is still on the
    /// panel — it has to be, that is what was just clicked — so simply setting
    /// the panel closed let the very next mouse-moved event find the cursor
    /// inside the keep-open zone and put it straight back up.
    public var dismissAll: () -> Void = {}

    /// Asks whether to quit, and quits if the answer is yes. Wired by the app,
    /// which owns the window the question is asked in.
    public var confirmQuit: () -> Void = {}

    public init(
        theme: Theme = .default,
        settings: SettingsStore,
        presence: LivePresence? = nil,
        visibility: PanelVisibility? = nil
    ) {
        self.baseTheme = theme
        self.settings = settings
        self.presence = presence ?? LivePresence()
        self.visibility = visibility ?? PanelVisibility()
        self.away = AwayReport()
    }
}
