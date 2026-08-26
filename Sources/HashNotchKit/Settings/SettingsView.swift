import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Lightweight description of a feature for the settings list, so the view never
/// holds the live feature objects.
public struct FeatureDescriptor: Identifiable {
    public let id: String
    public let title: String
    public let options: [FeatureOption]
    /// A page of this feature's own settings, if it has one.
    public let page: FeatureSettingsPage?

    public init(
        id: String,
        title: String,
        options: [FeatureOption],
        page: FeatureSettingsPage? = nil
    ) {
        self.id = id
        self.title = title
        self.options = options
        self.page = page
    }
}

/// Which page the settings window should show.
///
/// Its own object rather than a value on `SettingsStore`, because where somebody
/// is looking is not a preference and has no business being saved to disk with
/// the ones that are. The island sets this when it sends somebody here to fix
/// something specific, so they arrive at the switch rather than at a window.
@MainActor
public final class SettingsRoute: ObservableObject {
    @Published public var requested: String?

    public init() {}

    /// Where the browser-control switch lives. Named here so a caller does not
    /// have to know the page it happens to sit on today — and it has moved
    /// once already, from Alerts to General, which is exactly why the island
    /// asks by name rather than naming a page itself.
    public static let browserControl = "general"
}

/// The customization window.
///
/// Deliberately not a stock grouped Form: this window is the only face the app
/// has apart from the island itself, so it is dark and tinted to match it. Each
/// concern gets its own page rather than a dozen controls stacked into one
/// scroll, which is what made the previous single list feel thin.
public struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var route: SettingsRoute
    let features: [FeatureDescriptor]

    @State private var section: Section = .general
    @State private var dragging: String?
    /// The row the pointer is over, so a row can say it is grabbable before
    /// anybody tries to grab it. Cleared while a drag is running: during one,
    /// what matters is where the row is going, not where the pointer is.
    @State private var hoveredRow: String?

    enum Section: String, CaseIterable, Identifiable {
        case general, indicators, appearance, alerts, position, privacy
        /// A page a FEATURE supplies. Deliberately unnamed here: the tab's
        /// words and its symbol come from the feature, because the core does
        /// not know what any feature does and should not start now.
        case supplied
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .indicators: return "Indicators"
            case .appearance: return "Appearance"
            case .alerts: return "Alerts"
            case .position: return "Position"
            case .privacy: return "Privacy"
            case .supplied: return ""
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape.fill"
            case .indicators: return "square.stack.3d.up.fill"
            case .appearance: return "paintbrush.fill"
            case .alerts: return "bell.fill"
            case .position: return "arrow.up.and.down.and.arrow.left.and.right"
            case .privacy: return "lock.shield.fill"
            case .supplied: return "puzzlepiece.extension.fill"
            }
        }
    }

    /// The page a feature has supplied, if any has. Only one is shown: no
    /// feature but the activity feed has ever needed one, and a window that
    /// grows a tab per feature stops being a window anybody can find anything
    /// in.
    private var suppliedPage: FeatureSettingsPage? {
        features.compactMap(\.page).first
    }

    /// The tabs actually shown. The supplied one appears only when a feature
    /// has supplied it, so a build without that feature has no empty tab.
    private var sections: [Section] {
        Section.allCases.filter { $0 != .supplied || suppliedPage != nil }
    }

    /// Closes the panel. Supplied by the window that owns it, because a
    /// borderless panel has no title bar to close and needs to offer the button
    /// itself.
    private let onClose: () -> Void

    /// Puts this window and the panel away together, for the moment a switch is
    /// about to make macOS ask for something.
    private let onDismissAll: () -> Void

    public init(
        settings: SettingsStore,
        features: [FeatureDescriptor],
        route: SettingsRoute,
        onDismissAll: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {}
    ) {
        self.settings = settings
        self.features = features
        self.route = route
        self.onDismissAll = onDismissAll
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            tabStrip
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            ScrollView {
                page
                    .padding(.horizontal, 22)
                    // Room between the row of tabs and the heading of the page
                    // they opened. There were 11 points — the strip's own
                    // padding and the hairline — so the heading sat against the
                    // tab above it and the two read as one block, which made
                    // the page title look like a caption belonging to the tabs
                    // rather than the title of everything below it.
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                    // Belt and braces after the picker fix: the page takes
                    // the width it is given rather than asking for more,
                    // so one over-eager control can never push the rest of
                    // the column off the edge again.
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Hiding the scrollbar is cosmetic; on macOS 12 it simply shows
            // in the system's usual way, which is not worth a workaround.
            .hideScrollIndicatorsIfPossible()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panelSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            // The hairline that catches the light along the top edge, the same
            // one dark glass surfaces have all over macOS. It is most of what
            // separates a dark rectangle from a piece of the interface.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.16), .white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .preferredColorScheme(.dark)
        .tint(settings.accent.color)
        .onAppear { jumpIfRequested() }
        .onChange(of: route.requested) { _ in jumpIfRequested() }
    }

    /// The one spring the reordering moves on. Built here rather than written
    /// out at each call so a row that dims, a row that moves and a row that
    /// settles are all the same movement — three curves doing one job is what
    /// makes a list look busy.
    private var reorderSpring: Animation {
        .spring(
            response: ReorderMotion.response(for: settings.appearance.motion),
            dampingFraction: ReorderMotion.damping
        )
    }

    /// Move to a page the island asked for, once.
    private func jumpIfRequested() {
        guard let wanted = route.requested,
              let target = Section(rawValue: wanted) else { return }
        withAnimation(reorderSpring) { dragging = nil }
        section = target
        route.requested = nil
    }

    /// Frosted where the system allows it, with a dark wash over the top so the
    /// text stays readable against a bright wallpaper.
    private var panelSurface: some View {
        ZStack {
            VisualEffectView(material: .hudWindow)
            Color.black.opacity(0.55)
        }
    }

    /// The app's name, and the way out.
    ///
    /// The name sits here now rather than above a column of links, because the
    /// column is gone. No page title here though: every page already opens with
    /// its own heading and a line explaining it, and the two stacked read as a
    /// stutter.
    private var header: some View {
        HStack(spacing: 8) {
            // Drag the window by this strip, the way a title bar works — the
            // name and the empty room after it, the full width of the window
            // up to the close button. It has to be the strip rather than the
            // name alone: this is now the only place the window moves from, so
            // a handle the width of one word would be a window that is hard to
            // move. The button stays outside it, because a view the window can
            // be dragged by never receives a click.
            HStack(spacing: 8) {
                Text("HashNotch")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer(minLength: 8)
            }
            .frame(height: 22)
            .overlay(WindowDragArea())
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.07)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 0)
    }

    // MARK: Tabs

    /// The six pages, across the top.
    ///
    /// This was a 146pt column down the left, which cost the content a third of
    /// the window's width on every page to show six words. Across the top the
    /// same six pages cost about 54pt of height once, and the pages below get
    /// the full width — which is what stops a row of controls from having to
    /// choose between wrapping and running off the edge.
    ///
    /// The icon sits ABOVE its label rather than beside it, and that is what
    /// makes six fit. Side by side, "Appearance" plus its icon is roughly 77pt,
    /// so the row would want over 460pt before padding and the last tab would
    /// be pushed out. Stacked, each tab needs only as much width as its widest
    /// word.
    private var tabStrip: some View {
        HStack(spacing: 4) {
            ForEach(sections) { item in
                tab(item)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    /// What a tab is called. Every tab but one answers for itself; the supplied
    /// one is named by whichever feature supplied it.
    private func title(for item: Section) -> String {
        item == .supplied ? (suppliedPage?.title ?? "") : item.title
    }

    private func symbol(for item: Section) -> String {
        item == .supplied ? (suppliedPage?.symbol ?? item.symbol) : item.symbol
    }

    private func tab(_ item: Section) -> some View {
        let selected = section == item
        return Button {
            // Leaving the page abandons any drag that was in progress. Without
            // this a half-finished reorder carried its held id across to
            // another page, where nothing could ever clear it.
            dragging = nil
            section = item
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol(for: item))
                    .font(.system(size: 12, weight: .semibold))
                    .frame(height: 14)
                    .foregroundStyle(selected ? settings.accent.color : Color.white.opacity(0.55))
                Text(title(for: item))
                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.7))
                    // One line, always. A tab that wraps is taller than its
                    // neighbours and the whole strip grows to match it.
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            // Equal shares of whatever width there is, so the strip stays even
            // on a display that has squeezed the window narrower.
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.09 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title(for: item))
    }

    // MARK: Pages

    @ViewBuilder
    private var page: some View {
        switch section {
        case .general: general
        case .indicators: indicators
        case .appearance: appearance
        case .alerts: alerts
        case .position: position
        case .privacy: privacy
        case .supplied:
            if let page = suppliedPage { page.view } else { EmptyView() }
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader("General", detail: "How the app starts, and how hard it works.")

            SettingCard {
                SettingRow(
                    "Open at login",
                    detail: loginDetail
                ) {
                    Toggle("", isOn: launchAtLoginBinding)
                        .labelsHidden()
                        .disabled(!LoginItem.isSupported)
                }

                if LoginItem.needsApproval {
                    Button("Approve in System Settings") {
                        LoginItem.openLoginItemsSettings()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
                }

                SettingDivider()

                SettingRow(
                    "Battery saver",
                    detail: "Check everything half as often. Nothing disappears."
                ) {
                    Toggle("", isOn: $settings.batterySaver).labelsHidden()
                }

                SettingDivider()

                SettingRow(
                    "Count AI tokens",
                    detail: "Counts on this rhythm whether or not the panel is open, so the figure on the notch is this fresh. Only what your tools have written since the last count is read, which is what makes even the short settings cheap.",
                    stacked: true
                ) {
                    Picker("", selection: $settings.tokenScanInterval) {
                        ForEach(TokenScanInterval.allCases, id: \.self) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }

                SettingDivider()

                // Which span, not whether to count: the counting is the same
                // work whatever is shown, and all three spans are read from the
                // same day-by-day record, so this changes what the panel adds
                // up rather than what it collects.
                SettingRow(
                    "Data used counts",
                    detail: "How much has gone through your network, over the stretch you pick. \"Since I reset it\" is started again from the panel.",
                    stacked: true
                ) {
                    Picker("", selection: $settings.networkUsagePeriod) {
                        ForEach(NetworkUsagePeriod.allCases, id: \.self) { period in
                            Text(period.label).tag(period)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }

                SettingDivider()

                // Its own switch, rather than part of the network indicator,
                // because it is a different KIND of reading. Everything else in
                // that indicator comes from per-interface byte counters, which
                // know how much went past and nothing whatever about who sent
                // it. This asks macOS a question that names your programs. It
                // needs no permission and nothing leaves the Mac either way,
                // but "this app knows which of your programs use the network"
                // is a sentence somebody is entitled to say no to.
                SettingRow(
                    "Name the programs that used the most",
                    detail: "Shows the two biggest under the total, with what each of them used. It asks macOS for its own per-program figures — the same ones Activity Monitor shows. Off means it is never asked.",
                    stacked: true
                ) {
                    Toggle("", isOn: $settings.networkShowsApps).labelsHidden()
                }
            }

            // The two switches that hand the app a power it does not otherwise
            // have. They sit here, together, rather than among the alert
            // settings where they used to be — an alert setting is about how
            // something looks, and these are about what the app is allowed to
            // do, which is the first thing somebody looks for and the last
            // place they would think to find it.
            // Each service is its own switch, because each is a request to a
            // different company. Rolling them into one would mean somebody who
            // wants covers for the service they use has to accept requests to
            // the others as well.
            SettingGroupLabel("Cover art")
            SettingCard {
                ForEach(Array(ArtworkService.all.enumerated()), id: \.element.id) { index, service in
                    if index > 0 { SettingDivider() }
                    SettingRow(service.name, detail: service.detail, stacked: true) {
                        Toggle("", isOn: artworkBinding(service)).labelsHidden()
                    }
                }
            }

            SettingGroupLabel("Permissions")
            SettingCard {
                SettingRow(
                    "Control video in your browser",
                    detail: "Needs Accessibility, so the buttons can press the media keys. Without it they still work for Spotify and Music.",
                    stacked: true
                ) {
                    Toggle("", isOn: mediaKeysBinding).labelsHidden()
                }

                SettingDivider()

                SettingRow(
                    "Switch Low Power Mode from the panel",
                    detail: "Switch it here instead of in System Settings. macOS asks for your password each time you use it.",
                    stacked: true
                ) {
                    Toggle("", isOn: $settings.canSwitchLowPowerMode).labelsHidden()
                }
            }

            SettingCard {
                ResetRow(
                    title: "Reset all settings",
                    detail: "Puts every page back the way the app arrived — indicators, look, alerts, position. Your consent to read is kept, so nothing stops working.",
                    confirmLabel: "Reset everything",
                    action: resetEverything
                )
            }

            SettingCard {
                SettingRow(
                    "Quit HashNotch",
                    detail: "Closes the island and stops everything."
                ) {
                    Button("Quit") { NSApp.terminate(nil) }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                }
            }

            Spacer(minLength: 0)
        }
    }

    /// Everything back to shipped, including the login item.
    ///
    /// The login item is switched through `LoginItem` rather than by writing
    /// the stored value, because that value is only ever a copy of what macOS
    /// is doing — the user can change it in System Settings without this app
    /// knowing. Setting the copy alone would leave the app still opening at
    /// login while the settings said it did not.
    private func resetEverything() {
        dragging = nil
        if LoginItem.isSupported, LoginItem.isEnabled {
            _ = LoginItem.setEnabled(false)
        }
        settings.launchAtLogin = LoginItem.isSupported ? LoginItem.isEnabled : false
        settings.resetAll(features: features)
    }

    private var indicators: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(
                "Indicators",
                detail: "What shows, how it looks, and in what order. Drag a row to move it."
            )

            SettingCard {
                ForEach(Array(orderedDescriptors.enumerated()), id: \.element.id) { index, feature in
                    if index > 0 { SettingDivider() }
                    indicatorRow(feature)
                }
            }
            // Behind the rows, catching any drag let go between them or beside
            // them. Without it a drag that missed a row left its held id set
            // for the rest of the session — see `ReorderCancel`.
            .onDrop(
                of: [UTType.text],
                delegate: ReorderCancel(dragging: $dragging, settle: reorderSpring)
            )

            Spacer(minLength: 0)
        }
        // And a drag abandoned by closing the page cannot outlive the page.
        .onDisappear { dragging = nil }
    }

    /// Descriptors in the user's chosen order. Ties break on id so two features
    /// never swap places between launches.
    private var orderedDescriptors: [FeatureDescriptor] {
        features.sorted { left, right in
            let l = settings.features[left.id]?.order ?? 0
            let r = settings.features[right.id]?.order ?? 0
            return l == r ? left.id < right.id : l < r
        }
    }

    private func indicatorRow(_ feature: FeatureDescriptor) -> some View {
        let enabled = settings.isEnabled(feature.id)
        let held = dragging == feature.id
        let hovered = hoveredRow == feature.id && dragging == nil
        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(held ? 0.75 : hovered ? 0.5 : 0.28))
                Text(feature.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.45))
                Spacer(minLength: 0)
                Toggle("", isOn: enabledBinding(feature.id)).labelsHidden()
            }

            if enabled, !feature.options.isEmpty {
                // A menu, not a segmented control.
                //
                // Segmented lays every choice out side by side at whatever
                // width the longest label wants, and refuses to shrink — so
                // "Symbol and number / Number only / Word" simply ran off the
                // page and took the column's whole layout with it, clipping the
                // description above as well. A menu is the same choice in the
                // width of one label, and it does not care how many options a
                // feature grows later.
                HStack {
                    Picker("", selection: styleBinding(feature.id)) {
                        ForEach(feature.options) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    Spacer(minLength: 0)
                }
                .padding(.leading, 24)
            }
        }
        .padding(.vertical, 8)
        // The row being carried is left behind as the space it will drop into,
        // rather than as a second copy of itself: dimmed nearly out, with a
        // shallow well drawn where it sits. The solid one is the piece under
        // the pointer, and one row should only look solid in one place.
        .opacity(held ? 0.32 : 1)
        .background(rowWell(held: held, hovered: hovered))
        .contentShape(Rectangle())
        // Leaving one row for the next fires both events, in either order, so
        // a row only ever clears the hover it still holds.
        .onHover { inside in
            hoveredRow = inside ? feature.id : (hoveredRow == feature.id ? nil : hoveredRow)
        }
        .animation(reorderSpring, value: held)
        .animation(.easeOut(duration: 0.16), value: hovered)
        .dragToReorder {
            withAnimation(reorderSpring) { dragging = feature.id }
            return NSItemProvider(object: feature.id as NSString)
        } preview: {
            dragPreview(feature)
        }
        .onDrop(
            of: [UTType.text],
            delegate: ReorderDrop(
                target: feature.id,
                order: orderedDescriptors.map(\.id),
                dragging: $dragging,
                settle: reorderSpring,
                apply: { order in
                    // The list rearranging under the pointer is the whole
                    // animation: every row that has to move travels to its new
                    // place on one spring, instead of the order changing
                    // between one frame and the next.
                    withAnimation(reorderSpring) { settings.setOrder(order) }
                }
            )
        )
    }

    /// The shallow well a row sits in: drawn where the row was picked up from,
    /// and hinted at under the pointer so a row reads as something you can take
    /// hold of before you try to.
    ///
    /// Wider than the row by the card's own padding, so it looks like a recess
    /// in the card rather than a box floating inside one.
    private func rowWell(held: Bool, hovered: Bool) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.white.opacity(held ? 0.055 : hovered ? 0.03 : 0))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        settings.accent.color.opacity(held ? 0.3 : 0),
                        lineWidth: 1
                    )
            )
            .padding(.horizontal, -8)
            .padding(.vertical, 1)
    }

    /// What actually follows the pointer.
    ///
    /// Without this, macOS carries a snapshot of the whole row — full width,
    /// with a live switch and a menu in it — which reads as the interface
    /// having come loose. A small piece naming the indicator is what is being
    /// moved, and it is the size of the thing rather than the size of the row.
    ///
    /// Its colours are stated outright rather than inherited: the preview is
    /// drawn on its own, away from the panel that sets the dark scheme, so
    /// anything left to the environment comes out light on light.
    private func dragPreview(_ feature: FeatureDescriptor) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(settings.accent.color)
            Text(feature.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.13))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(settings.accent.color.opacity(0.45), lineWidth: 1)
                )
        )
        .environment(\.colorScheme, .dark)
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(
                "Appearance",
                detail: "Only the panel that drops down. The notch and strip stay black."
            )

            SettingCard {
                SettingRow(
                    "Accent colour",
                    detail: "Tints icons, bars and highlights.",
                    stacked: true
                ) {
                    HStack(spacing: 8) {
                        ForEach(AccentColor.all) { accent in
                            accentDot(accent)
                        }
                    }
                }

                SettingDivider()

                SettingRow(
                    "Panel fill",
                    detail: "Frosted picks up what is behind it. Solid matches the notch.",
                    stacked: true
                ) {
                    Picker("", selection: $settings.appearance.panelFill) {
                        ForEach(AppearanceSettings.PanelFill.allCases, id: \.self) { fill in
                            Text(fill.label).tag(fill)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                SettingDivider()

                SettingRow(
                    "Motion",
                    detail: "How eagerly the island opens and closes.",
                    stacked: true
                ) {
                    Picker("", selection: $settings.appearance.motion) {
                        ForEach(AppearanceSettings.Motion.allCases, id: \.self) { motion in
                            Text(motion.label).tag(motion)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                SettingDivider()

                SettingRow(
                    "Panel roundness",
                    detail: "\(Int(settings.appearance.panelCornerRadius)) pt at the bottom corners.",
                    stacked: true
                ) {
                    Slider(value: whole($settings.appearance.panelCornerRadius), in: 8...36)
                        .frame(maxWidth: .infinity)
                }

                SettingDivider()

                SettingRow(
                    "Dividing lines",
                    detail: separatorDetail,
                    stacked: true
                ) {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            Text("Thickness")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.55))
                                .frame(width: 62, alignment: .leading)
                            Slider(
                                value: $settings.appearance.separatorThickness,
                                in: AppearanceSettings.separatorThicknessRange,
                                step: 0.5
                            )
                        }
                        HStack(spacing: 10) {
                            Text("Strength")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.55))
                                .frame(width: 62, alignment: .leading)
                            Slider(
                                value: $settings.appearance.separatorOpacity,
                                in: AppearanceSettings.separatorOpacityRange
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            SettingCard {
                ResetRow(
                    title: "Reset appearance",
                    detail: "Puts the colour, fill, motion, rounding and separators back to how they arrived. Nothing on the other pages changes.",
                    confirmLabel: "Reset appearance",
                    action: settings.resetAppearance
                )
            }

            Spacer(minLength: 0)
        }
    }

    private func accentDot(_ accent: AccentColor) -> some View {
        let selected = settings.appearance.accentID == accent.id
        return Button {
            settings.appearance.accentID = accent.id
        } label: {
            Circle()
                .fill(accent.color)
                .frame(width: 18, height: 18)
                .overlay(
                    Circle().strokeBorder(
                        Color.white.opacity(selected ? 0.95 : 0.16),
                        lineWidth: selected ? 2 : 1
                    )
                )
                .padding(2)
        }
        .buttonStyle(.plain)
        .help(accent.name)
    }

    private var alerts: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader("Alerts", detail: "What happens when something finishes, or wants your attention.")

            SettingCard {
                SettingRow(
                    "Keep a finished alert for",
                    detail: "\(Int(settings.alerts.noticeSeconds)) seconds, then it goes. No timer beside it.",
                    stacked: true
                ) {
                    Slider(value: whole($settings.alerts.noticeSeconds), in: 1...10)
                        .frame(maxWidth: .infinity)
                }


            }

            Spacer(minLength: 0)
        }
    }

    private var position: some View {
        let screen = NotchGeometry.preferredScreen()
        let key = screen.map { NotchGeometry.displayKey(for: $0) } ?? "display-unknown"
        let measured = screen.map { NotchGeometry.current(for: $0) }
        let current = settings.adjustment(for: key)

        return VStack(alignment: .leading, spacing: 22) {
            PageHeader(
                "Position",
                detail: measured?.hasNotch == true
                    ? "Your display has a notch, and the island is measured to match it exactly. Nudge it here if anything looks off."
                    : "This display has no notch, so the island sits just below the menu bar instead of covering it. Nudge it here to taste."
            )

            SettingCard {
                SettingRow(
                    "Fit",
                    detail: current.isAutomatic ? "Measured automatically." : "Adjusted by hand."
                ) {
                    Button("Reset to automatic") {
                        settings.setAdjustment(IslandAdjustment(), for: key)
                    }
                    .disabled(current.isAutomatic)
                }
            }

            // Two groups rather than four rows in a list. Moving the island and
            // resizing it are different intentions, and a heading over each
            // says which is which faster than a sentence under every slider.
            SettingCard {
                SettingGroupLabel("Move")
                adjustmentSlider(
                    "Sideways",
                    value: adjustmentBinding(key, \.horizontal),
                    range: IslandAdjustment.horizontalRange
                )
                adjustmentSlider(
                    "Down",
                    value: adjustmentBinding(key, \.vertical),
                    range: IslandAdjustment.verticalRange
                )
            }

            SettingCard {
                SettingGroupLabel("Size")
                adjustmentSlider(
                    "Width",
                    value: adjustmentBinding(key, \.width),
                    range: IslandAdjustment.widthRange
                )
                adjustmentSlider(
                    "Height",
                    value: adjustmentBinding(key, \.height),
                    range: IslandAdjustment.heightRange
                )
            }

            Text("Remembered per display.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }

    /// Keeps a slider's value whole without asking it for a `step`.
    ///
    /// macOS draws one tick mark under a stepped slider for every step in its
    /// range. Over the sideways range that is 481 of them, which renders as a
    /// solid bar beneath the track and reads as a rendering fault rather than a
    /// scale — the shorter ranges gave it away by showing the individual dashes.
    /// Rounding here keeps the numbers whole and leaves the track clean.
    private func whole(_ binding: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { binding.wrappedValue.rounded() },
            set: { binding.wrappedValue = $0.rounded() }
        )
    }

    /// One adjustment: a short name, its value, and a full-width track.
    ///
    /// The old shape put a name and a sentence of explanation on the left and
    /// the slider in whatever space was left on the right — so four of them
    /// stacked gave four paragraphs and four stubs of track crushed against the
    /// edge, on a page that is nothing but sliders. The words were the problem:
    /// "Move sideways" needs no sentence under it, and "Currently 12 pt" is a
    /// value, not prose.
    ///
    /// So the name and the value share one line, and the track gets the whole
    /// width below them. Nothing is lost — the number is still there, and it is
    /// easier to read where it is now.
    private func adjustmentSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer(minLength: 8)
                Text("\(Int(value.wrappedValue)) pt")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(
                        Int(value.wrappedValue) == 0
                            ? .white.opacity(0.35)
                            : settings.accent.color
                    )
                    .monospacedDigit()
            }
            Slider(value: whole(value), in: range)
                .frame(maxWidth: .infinity)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private func adjustmentBinding(
        _ key: String,
        _ path: WritableKeyPath<IslandAdjustment, Double>
    ) -> Binding<Double> {
        Binding(
            get: { settings.adjustment(for: key)[keyPath: path] },
            set: { newValue in
                var adjustment = settings.adjustment(for: key)
                adjustment[keyPath: path] = newValue
                settings.setAdjustment(adjustment, for: key)
            }
        )
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(
                "Privacy",
                detail: "Everything stays on this Mac."
            )

            // Four words that are each their own answer, before any prose.
            //
            // This page was five dense paragraphs stacked in one card, and the
            // effect of putting every reassurance next to every other one is
            // that none of them lands — a wall of text about privacy reads as
            // something to skip, which is the opposite of the point. The things
            // that are simply NONE are said as one word each, because that is
            // the whole answer and anything added to it is dilution.
            HStack(spacing: 8) {
                PrivacyNone("Accounts", "nothing to sign in to")
                PrivacyNone("Analytics", "nothing counted")
            }
            HStack(spacing: 8) {
                PrivacyNone("Files written", "settings only")
                PrivacyNone("Audio", "never listened to")
            }

            SettingCard {
                // Network is NOT in the None grid above, and that is the point.
                // It used to be, reading "Network — None — no requests at all",
                // which was false: covers are downloaded, as they always were.
                // The grid's whole meaning is that the format is reserved for
                // absolutes, so an almost-absolute put there costs every other
                // tile its credibility.
                PrivacyLine(
                    "The one request it makes",
                    "Fetching the cover for what's playing, over HTTPS, only from the image servers of the services you allow on the General page, size-capped, and refused if a redirect would lead elsewhere. Turn both off and nothing touches the network at all. Nothing about you is ever sent anywhere."
                )
                SettingDivider()
                PrivacyLine(
                    "Nothing runs until you say so",
                    "On a new install every indicator is stopped until the opening window is answered. Before that the app has opened no file, run no command, and could not have raised any of the requests below."
                )
                SettingDivider()
                PrivacyLine(
                    "Off means off",
                    "An indicator switched off is never started — it reads nothing and asks for nothing. Switching one off stops the work, not just the display."
                )
                SettingDivider()
                // The one reading here that is about YOU rather than about the
                // machine, so it is named on this page rather than left to be
                // discovered. It needs no permission from macOS, which is
                // exactly why it would otherwise never be mentioned anywhere.
                PrivacyLine(
                    "The one thing it learns about you",
                    "Everything else here reads counters about the hardware. Naming the programs that used the most data reads which programs you run, which is a fact about you rather than about the Mac — so it has its own switch on the General page, and off means the tool that answers it is never run. It is Apple's own nettop, the one Activity Monitor uses: it asks for byte totals per program and gets no address, site or port back, so this app cannot see where any of it went. What it records — program names and byte counts — never leaves the Mac, and switching it off deletes it."
                )
            }

            // Every permission macOS can put in front of you, in the order you
            // are likely to meet them.
            //
            // Written as one row each rather than as prose, because the three
            // questions somebody actually has are always the same — when am I
            // asked, why, and what breaks if I say no — and a paragraph makes
            // you hunt for all three. The last question is the one usually left
            // out, and it is the one that decides whether saying no feels safe.
            SectionLabel("What macOS may ask you")

            SettingCard {
                PermissionRow(
                    icon: "music.note",
                    name: "Control Spotify or Apple Music",
                    asked: "First time you press play, pause or skip on one of their tracks.",
                    why: "A paused Spotify or Music hands back the system's media session, and only its own controls can start it again.",
                    ifDenied: "Only those buttons, only for those two apps. Every other player carries on."
                )
                SettingDivider()
                PermissionRow(
                    icon: "square.on.square",
                    name: "Control your browser",
                    asked: "Older systems only, and only if a web video is playing with no picture yet.",
                    why: "To read the playing tab's address for its thumbnail. The tab list never leaves the helper; only that one address returns.",
                    ifDenied: "A web video shows a plain tile. Nothing else changes."
                )
                SettingDivider()
                PermissionRow(
                    icon: "folder",
                    name: "Your Downloads folder",
                    asked: "First time the download notice looks there.",
                    why: "To read file names, so the notch can say when a download finishes.",
                    ifDenied: "No download notice. Nothing else is affected, and switching Downloads off stops it looking at all."
                )
                SettingDivider()
                PermissionRow(
                    icon: "bell",
                    name: "Notifications",
                    asked: "First time you start a timer.",
                    why: "To post a banner when the timer reaches zero.",
                    ifDenied: "The timer still chimes and still shows \"Time's up\" at the notch."
                )
                SettingDivider()
                PermissionRow(
                    icon: "accessibility",
                    name: "Accessibility",
                    asked: "Only if you switch on \"Control video in your browser\". It is off until you do.",
                    why: "The keyboard's play, next and previous keys are the only way to reach a browser video, and macOS gates those three keys behind this.",
                    ifDenied: "The buttons still work for Spotify and Apple Music. Three key presses are all it is ever used for; it never reads a keystroke."
                )
            }

            SectionLabel("What it never asks for")

            SettingCard {
                PrivacyLine(
                    "Screen Recording, Input Monitoring, Full Disk Access",
                    "Never requested, under any setting. If macOS ever shows you a request for one of these in this app's name, something is wrong and you should not grant it."
                )
                SettingDivider()
                PrivacyLine(
                    "The microphone",
                    "The app holds no microphone permission and could not use one. It asks macOS a yes-or-no question — does this app have an input stream open — and nothing is ever listened to, recorded or transcribed."
                )
            }

            SectionLabel("Terms")

            SettingCard {
                PrivacyLine(
                    "Your licence",
                    "HashNotch is free software under the GNU General Public License, version 3 or later. You may use it for anything, read all of it, change it, and pass it on. Anything you distribute that is built on it must stay free too, with its source available."
                )
                SettingDivider()
                PrivacyLine(
                    "No warranty",
                    "It is provided as is, with no warranty of any kind. You run it at your own risk, and the author is not liable for any loss or damage arising from its use — as set out in sections 15 and 16 of the licence."
                )
                SettingDivider()
                PrivacyLine(
                    "What it is not for",
                    "The readings are for your information only. Do not rely on them where being wrong would be dangerous or costly — the temperatures, battery figures and token counts are read from your Mac and other tools, and none of them are guaranteed to be accurate or available."
                )
                SettingDivider()
                PrivacyLine(
                    "Your data is yours",
                    "There is no account, no server and no collection, so there is nothing for anyone to hand over, sell, lose or be compelled to produce. That is a property of the design rather than a promise about conduct, and you can confirm it by reading the source."
                )
                SettingDivider()
                PrivacyLine(
                    "Other people's names",
                    "Apple, Spotify, YouTube and every other product named in this app belong to their owners. They are named to say what works with what, and none of them endorse or are connected with this app."
                )
            }

            Text("Every line on this page is checkable by reading the source. The full detail is in SECURITY.md, and the licence in full is in the LICENSE file beside it.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    // MARK: Bindings

    private func enabledBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { settings.features[id]?.enabled ?? true },
            set: { value in settings.update(id) { $0.enabled = value } }
        )
    }

    private func styleBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { settings.features[id]?.styleID ?? "default" },
            set: { value in settings.update(id) { $0.styleID = value } }
        )
    }

    private var loginDetail: String {
        // Ask WHY it is unavailable rather than assuming.
        //
        // This used to answer every unavailable case with "available once Hash
        // D Island is running from your Applications folder" — which is the
        // right answer for a bare binary and a false one on macOS 12, where the
        // app IS in Applications and opening at login genuinely cannot work
        // because the system interface for it did not exist yet. Telling
        // somebody to do a thing they have already done is the worst kind of
        // explanation: it costs them the attempt and teaches them not to
        // believe the next message.
        if let reason = LoginItem.unavailableReason {
            return reason
        }
        if LoginItem.needsApproval {
            return "macOS is waiting for you to allow this in System Settings."
        }
        return "Comes back every time you start your Mac."
    }

    /// One service's covers, on or off. Writing it also updates the policy the
    /// downloader runs on, so the switch and what the network actually does can
    /// never drift apart.
    private func artworkBinding(_ service: ArtworkService) -> Binding<Bool> {
        Binding(
            get: { settings.isArtworkEnabled(service) },
            set: { value in
                settings.setArtworkEnabled(service, value)
                ArtworkPolicy.setEnabledServices(settings.enabledArtworkServiceIDs)
            }
        )
    }

    /// Turning it on asks macOS for the permission at that moment, which is
    /// the only moment the request makes sense — an app that asks at launch for
    /// something it may never do is an app people say no to.
    ///
    /// The panel and this window go first, and that is not politeness. Both sit
    /// above the ordinary window level, so the Accessibility dialog opened
    /// BEHIND them: the switch was flipped, nothing appeared to happen, and the
    /// thing waiting for an answer was underneath the window it was asked from.
    ///
    /// The short wait is for the same reason the opening window waits — asking
    /// a window to close only starts a fade, and it is on screen throughout.
    /// Long enough for both to be gone, short enough to read as one action.
    private var mediaKeysBinding: Binding<Bool> {
        Binding(
            get: { settings.canPressMediaKeys },
            set: { value in
                settings.canPressMediaKeys = value
                if value {
                    onDismissAll()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        MediaControl.requestPermission()
                    }
                }
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            // Read the OS's actual login-item state, not our stored copy — the
            // user can also change it in System Settings behind our back.
            get: { LoginItem.isSupported ? LoginItem.isEnabled : settings.launchAtLogin },
            set: { value in
                let ok = LoginItem.setEnabled(value)
                settings.launchAtLogin = ok ? value : LoginItem.isEnabled
            }
        )
    }
}

/// A row whose button undoes something, and asks once before it does.
///
/// The confirmation is the row itself changing rather than a dialog, because
/// this window is borderless and floats beside the island — putting a sheet on
/// it means a second surface hovering over the first, for a question with two
/// words of context. Here the button is replaced in place by "Cancel" and a
/// confirm, so the question is asked exactly where the answer will land.
///
/// The reset is never one click away, even though the appearance one is cheap
/// to undo by hand. Someone who has spent time arranging their island should
/// not be able to lose it by clicking slightly the wrong thing.
private struct ResetRow: View {
    let title: String
    let detail: String
    let confirmLabel: String
    let action: () -> Void

    @State private var asking = false

    var body: some View {
        SettingRow(title, detail: detail) {
            if asking {
                HStack(spacing: 6) {
                    Button("Cancel") { asking = false }
                        .buttonStyle(.bordered)
                    Button(confirmLabel) {
                        asking = false
                        action()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            } else {
                Button("Reset") { asking = true }
                    .buttonStyle(.bordered)
            }
        }
    }
}

/// Drops one indicator onto another to reorder the list.
private struct ReorderDrop: DropDelegate {
    let target: String
    let order: [String]
    @Binding var dragging: String?
    /// How the row put down comes back to itself. The same spring the move ran
    /// on, so letting go is the end of one movement rather than a cut.
    let settle: Animation
    let apply: ([String]) -> Void

    func dropEntered(info: DropInfo) {
        guard let source = dragging, source != target else { return }
        apply(SettingsReorder.moving(source, before: target, in: order))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        withAnimation(settle) { dragging = nil }
        return true
    }
}

/// Catches a drag that ended anywhere other than on a row.
///
/// `performDrop` is the only place the held id was cleared, and it only runs
/// when a drag lands ON a row. Let go over the gap between two rows, over the
/// tabs, or outside the window, and nothing ran — so the id stayed set for
/// the rest of the session. The row it named stayed dimmed, and every later
/// hover over any row fired a reorder against that stale id, which is what made
/// the settings window appear to freeze after reordering indicators.
///
/// This sits behind the whole list and accepts whatever the rows did not.
private struct ReorderCancel: DropDelegate {
    @Binding var dragging: String?
    let settle: Animation

    func performDrop(info: DropInfo) -> Bool {
        withAnimation(settle) { dragging = nil }
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .cancel) }
}

/// How the reordering moves, kept apart from the view so it can be checked.
///
/// One spring, scaled by the two things every other animation in this app is
/// scaled by: what the person asked for under Motion, and what this macOS can
/// draw in time. A settings window that ignored the Motion setting would be the
/// one place in the app that does.
public enum ReorderMotion {
    /// Seconds the move takes at Standard motion on a current system. The
    /// Motion setting moves it either side of this.
    ///
    /// Short enough that the list is never something you wait for, long enough
    /// that the eye can follow one row past another. Rows that arrive too
    /// quickly stop reading as having moved and start reading as having
    /// swapped, which tells you the order changed but not how.
    public static let baseResponse: Double = 0.34

    /// Just short of critical damping: a row arrives with the smallest
    /// suggestion of weight and does not bounce past its place. A list that
    /// bounces looks like a toy, and this one is a list of settings.
    public static let damping: Double = 0.86

    public static func response(
        for motion: AppearanceSettings.Motion,
        on generation: SystemGeneration = .current
    ) -> Double {
        baseResponse * motion.responseScale * generation.motionScale
    }
}

/// The reordering itself, kept apart from the view so it can be checked.
public enum SettingsReorder {
    /// `source` lifted out of the list and dropped at `target`'s position.
    /// Unknown ids leave the order untouched rather than corrupting it.
    public static func moving(_ source: String, before target: String, in order: [String]) -> [String] {
        guard source != target,
              let from = order.firstIndex(of: source),
              let to = order.firstIndex(of: target)
        else { return order }

        var ids = order
        ids.remove(at: from)
        ids.insert(source, at: to)
        return ids
    }
}

// MARK: Small building blocks

/// Published so a feature that supplies its own settings page can build it out
/// of the same pieces the window's own pages are built from. A page that looks
/// like a stranger inside the window is worse than no page.
public struct PageHeader: View {
    let title: String
    let detail: String

    public init(_ title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 19, weight: .semibold, design: .rounded))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

public struct SettingCard<Content: View>: View {
    @ViewBuilder var content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                    )
            )
    }
}

public struct SettingRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var control: Control

    /// Whether the control sits below the label rather than beside it.
    ///
    /// Beside is right for a switch, which is small and reads as part of the
    /// same line. It is wrong for a slider or a row of choices: the column here
    /// is about 270 points wide, and a 220-point control beside a label leaves
    /// the label 40 points to live in. Those go underneath, full width, where
    /// they have room and line up with each other down the page.
    ///
    /// **The rule, since this has now been got wrong twice:** anything wider
    /// than about 120 points must be stacked. A control with a fixed width wins
    /// the space outright, and the label does not merely wrap — it runs out of
    /// room to wrap between words and starts breaking them mid-word, so "Accent
    /// colour" comes out as "Accen / t colour". `minimumLabelWidth` below makes
    /// that fail visibly rather than quietly.
    let stacked: Bool

    public init(
        _ title: String,
        detail: String,
        stacked: Bool = false,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.detail = detail
        self.stacked = stacked
        self.control = control()
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12.5, weight: .medium))
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                // Explanations are sentences, and sentences need leading. Set
                // solid they read as a wall and the eye skips them, which is
                // the opposite of what an explanation is for.
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    public var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 11) {
                    label
                    control.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    label
                        // The words come first. Without this a control that can
                        // stretch takes what it likes and the label is left
                        // breaking mid-word to fit whatever remains.
                        .layoutPriority(1)
                        .frame(minWidth: settingRowMinimumLabelWidth, alignment: .leading)
                    Spacer(minLength: 8)
                    control
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
    }

}

/// The least room a label may have beside its control before the pairing is
/// simply wrong and the row should be stacked instead. Enough for two words of
/// the title at this size, so a squeeze shows up as a row that overflows its
/// card rather than as text quietly shredded between letters.
///
/// File scope rather than a member: `SettingRow` is generic over its control,
/// and a generic type cannot hold a stored static.
private let settingRowMinimumLabelWidth: CGFloat = 150

/// A quiet heading between cards, so a long page reads as a few short lists
/// rather than one unbroken column of reassurance.
private struct SectionLabel: View {
    let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.42))
            .padding(.top, 4)
    }
}

/// One macOS permission, answered in the three parts anybody actually wants.
///
/// When am I asked, why, and what breaks if I say no. Prose makes you hunt for
/// all three and usually omits the last, which is the one that decides whether
/// refusing feels safe — so it is given its own line, in its own colour, on
/// every row. A permission page that only argues for saying yes is a page
/// nobody believes.
private struct PermissionRow: View {
    let icon: String
    let name: String
    let asked: String
    let why: String
    let ifDenied: String

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // The icon sits beside the NAME only, not beside the whole row.
            // Indenting three paragraphs past it cost a fifth of the column,
            // and this column is about 285 points wide.
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 19, height: 19)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                    )
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
            }
            .padding(.bottom, 1)

            labelled("Asked", asked, tint: .white.opacity(0.5))
            labelled("For", why, tint: .white.opacity(0.5))
            labelled("If you refuse", ifDenied, tint: .green.opacity(0.9))
        }
    }

    /// The label reads as a lead-in to the sentence rather than a column beside
    /// it, so the text keeps the full width of the card.
    ///
    /// It was a fixed 68-point label with the text in what remained, which is a
    /// perfectly good shape in a wide window and a bad one here: it left about
    /// 200 points for prose, so every line broke after three or four words and
    /// each permission grew into a tall grey ribbon. Concatenated `Text` flows
    /// as one paragraph — the label is simply its first word, set apart by
    /// weight and colour instead of by position.
    private func labelled(_ label: String, _ text: String, tint: Color) -> some View {
        // Built as one attributed string rather than two concatenated `Text`s:
        // styling a `Text` with `foregroundStyle` needs macOS 14, and the older
        // `foregroundColor` is deprecated loudly enough to fail the build's
        // no-warnings gate. `AttributedString` does the same job from macOS 12.
        var head = AttributedString(label.uppercased() + "  ")
        head.font = .system(size: 9, weight: .bold)
        head.foregroundColor = tint
        var rest = AttributedString(text)
        rest.font = .system(size: 10.5)
        rest.foregroundColor = .secondary

        return Text(head + rest)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PrivacyLine: View {
    let title: String
    let detail: String

    public init(_ title: String, _ detail: String) {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
    }
}

public struct SettingDivider: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
            // A hairline with nothing either side of it does not separate
            // anything; it just draws a line through a wall of text.
            .padding(.vertical, 2)
    }
}

private extension View {
    /// `scrollIndicators(.never)` where it exists, and nothing where it does
    /// not. Kept as one modifier so the call site reads as intent rather than
    /// as a version check in the middle of a layout.
    @ViewBuilder
    func hideScrollIndicatorsIfPossible() -> some View {
        if #available(macOS 13, *) {
            self.scrollIndicators(.never)
        } else {
            self
        }
    }

    /// Starts a reorder, carrying `preview` under the pointer where macOS can
    /// be told what to carry, and the system's own snapshot of the row where it
    /// cannot. Monterey has no `onDrag(_:preview:)`, and a drag that works
    /// while looking plainer is the right thing to lose there.
    @ViewBuilder
    func dragToReorder<Preview: View>(
        _ data: @escaping () -> NSItemProvider,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        if #available(macOS 13, *) {
            self.onDrag(data, preview: preview)
        } else {
            self.onDrag(data)
        }
    }
}

private extension SettingsView {
    /// Says what the sliders currently amount to, including the case where they
    /// amount to nothing — turning the lines off is a preference, not a fault,
    /// and the row should say so rather than describing a line that is not there.
    var separatorDetail: String {
        let thickness = settings.appearance.separatorThickness
        guard thickness > 0, settings.appearance.separatorOpacity > 0 else {
            return "Off — the indicators run together."
        }
        let percent = Int((settings.appearance.separatorOpacity * 100).rounded())
        return String(format: "%.1f pt at %d%% between each indicator.", thickness, percent)
    }
}

/// A single-word answer, for the things that are simply none.
///
/// The word carries it. A tile that says "None" in the accent colour, with four
/// words under it saying what of, is read in the time it takes to glance —
/// where the same fact inside a paragraph is read by nobody. Reserved for
/// claims that really are absolute, so the format itself means something.
struct PrivacyNone: View {
    let title: String
    let detail: String

    public init(_ title: String, _ detail: String) {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text("None")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.42))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }
}

/// A quiet heading inside a card, for when a group of controls needs naming but
/// does not need a sentence.
public struct SettingGroupLabel: View {
    let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .kerning(1.0)
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 2)
    }
}
