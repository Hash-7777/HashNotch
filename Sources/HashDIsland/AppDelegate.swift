import AppKit
import Combine
import HashDIslandKit

/// Boots the HUD: builds the registry from the manifest, loads settings, starts
/// the features, and shows the notch overlay. There is no menu-bar item — the
/// panel's gear button is the way into settings.
/// Deliberately thin — all behavior lives in the core and the feature modules.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var registry: FeatureRegistry?
    private var context: FeatureContext?
    private var controller: NotchWindowController?
    private var settingsWindow: SettingsWindowController?
    /// Held only until it is answered; a new install sees it once.
    private var firstRunWindow: FirstRunWindowController?
    /// The "quit?" window. Held here, like every other window the app puts up,
    /// because nothing else retains it — a controller made at the moment of
    /// asking would be released before the question could be answered.
    private var quitConfirmation: QuitConfirmation?
    /// Set for one programmatic open, so settings appears without dragging the
    /// panel open behind it. Cleared as soon as that open happens.
    private var opensSettingsAlone = false
    /// Set when the opening window was refused, so the settings file is removed
    /// again on the way out — see `forgetPreferences`.
    private var declined = false
    private var power: PowerCoordinator?
    private var screenObserver: NSObjectProtocol?
    private var rebuildWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsStore()
        let registry = FeatureRegistry()
        registry.register(FeatureManifest.enabledFeatures())
        settings.seed(features: registry.features)

        let context = FeatureContext(settings: settings)
        // The download policy is a plain static because it is consulted from a
        // URLSession queue. Seed it from the store at launch, and keep it in
        // step, so a service switched off is switched off for the network and
        // not merely in the window.
        ArtworkPolicy.setEnabledServices(settings.enabledArtworkServiceIDs)
        settings.$artworkServices
            .sink { _ in
                DispatchQueue.main.async {
                    ArtworkPolicy.setEnabledServices(settings.enabledArtworkServiceIDs)
                }
            }
            .store(in: &cancellables)

        // No menu-bar item: the island's gear button is the settings entry.
        let settingsWindow = SettingsWindowController(settings: settings, registry: registry)
        // The gear opens settings beside the panel it was clicked from, and
        // holds that panel open for as long as they are both showing.
        context.openSettings = { [weak self] in self?.toggleSettings() }
        // Landing on the page that holds the switch the island just named.
        context.openSettingsPage = { [weak self] page in self?.openSettings(at: page) }

        // The "quit?" question. Built once and kept, because the window has to
        // outlive the click that raised it, and wired here rather than in
        // `wire(_:)` because it belongs to the app rather than to whichever
        // overlay controller is currently on screen — a display change replaces
        // the controller, and the question is not affected by that.
        let quitConfirmation = QuitConfirmation(accent: { settings.accent.color })
        self.quitConfirmation = quitConfirmation
        context.confirmQuit = { [weak quitConfirmation] in quitConfirmation?.ask() }
        settingsWindow.onVisibilityChange = { [weak self] visible in
            guard let self else { return }
            // Settings normally holds the panel open beside it, because it was
            // opened FROM that panel and leaving it to collapse would strand
            // the window next to nothing. An open asked for on the command line
            // has no panel behind it to belong to, so it skips the pin and
            // appears on its own.
            if visible, self.opensSettingsAlone {
                self.opensSettingsAlone = false
                return
            }
            self.controller?.setPinnedOpen(visible)
        }

        // Only the features that are switched on are started at all — and on a
        // brand-new install, not even those, until the first-run window has
        // been answered. `syncRunning` refuses to start anything while consent
        // is outstanding, so this call is safe either way and does nothing on a
        // first launch.
        registry.syncRunning(context: context)

        let controller = NotchWindowController(registry: registry, context: context)
        controller.show()
        // So a feature can get out of the way of a system dialog it just
        // raised. Wired here, like openSettings, because the controller does
        // not exist until now.
        wire(controller, context: context, settingsWindow: settingsWindow)

        let power = PowerCoordinator(registry: registry, context: context)
        // A locked Mac is exactly when the notch's summary of your afternoon
        // should not be readable, so the overlay leaves the screen rather than
        // relying on the login window to cover it.
        power.onConcealed = { [weak controller] concealed in
            concealed ? controller?.hide() : controller?.show()
        }
        power.begin()

        self.registry = registry
        self.context = context
        self.controller = controller
        self.settingsWindow = settingsWindow
        self.power = power

        // Displays change under us (resolution switch, monitor plug/unplug,
        // moving to a screen with a different notch). Rebuild the overlay so it
        // is always sized and positioned for the current screen. The
        // notification fires in bursts, so coalesce.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleOverlayRebuild() }
        }

        // Battery saver changes how often everything samples, and a running
        // sampler's interval is fixed — so the features are restarted, which is
        // exactly what already happens on screen sleep and wake.
        settings.$batterySaver
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.restartFeatures() }
                }
            }
            .store(in: &cancellables)

        // How often the token count runs is fixed when its sampler starts, for
        // the same reason battery saver is: an interval cannot be changed under
        // a running timer. Restarting is what already happens on screen sleep
        // and wake, so it is a path the features are built to survive.
        settings.$tokenScanInterval
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.restartFeatures() }
                }
            }
            .store(in: &cancellables)

        // Switching a feature off stops it reading, not just showing. The
        // whole config dictionary is watched because @Published fires for any
        // change in it (a reorder, a style); syncRunning only touches a feature
        // whose on/off state actually differs from what it is doing, so the
        // extra calls cost nothing. Deferred a hop because @Published fires in
        // willSet, where the store still holds the previous value.
        settings.$features
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.syncFeatures() }
                }
            }
            .store(in: &cancellables)

        // Position corrections are watched by the overlay controller itself,
        // which owns the geometry they change.

        // Development aid, inert unless HASHDISLAND_DEBUG asks for it. Whether
        // the system will accept this bundle as a login item cannot be learned
        // from outside the app — SMAppService always answers about whoever is
        // asking — so the only way to see the real error is from in here.
        if (ProcessInfo.processInfo.environment["HASHDISLAND_DEBUG"] ?? "").contains("login") {
            FileHandle.standardError.write(Data(
                "[login] bundle=\(Bundle.main.bundleURL.path)\n[login] status=\(LoginItem.statusDescription)\n".utf8
            ))
            let ok = LoginItem.setEnabled(true)
            FileHandle.standardError.write(Data(
                "[login] register returned \(ok), status now \(LoginItem.statusDescription)\n".utf8
            ))
        }

        // A new install is told what the indicators read BEFORE any of them
        // read anything, and nothing starts until it answers.
        //
        // This used to open the settings window instead, purely so the app was
        // easy to find — but by then every feature was already running, which
        // made the settings window a place to undo something rather than a
        // place to decide it.
        if !settings.hasAcceptedReading {
            let firstRun = FirstRunWindowController(settings: settings)
            // Called only once that window is off screen, which is what keeps
            // macOS's own Downloads prompt from landing on top of it — starting
            // the indicators is what raises that prompt.
            firstRun.onAccept = { [weak self] in
                self?.acceptReading()
            }
            firstRun.onDecline = { [weak self] in
                self?.declineReading()
            }
            self.firstRunWindow = firstRun
            firstRun.show()
        } else if let page = Self.requestedSettingsPage() {
            // Open straight onto a settings page when the command line asks.
            //
            // For working ON the app rather than for using it: rebuilding to
            // look at one page meant hovering the notch and clicking through to
            // it on every single launch, which is a toll paid dozens of times
            // in an afternoon. `--settings-page privacy` lands there directly.
            //
            // Never on a first run — the window asking what may be read has to
            // be the only thing on screen, and a second panel opening behind it
            // would be both confusing and a strange thing for that particular
            // window to be competing with.
            //
            // Opened ALONE. Settings normally pins the panel open beside it,
            // which is right when the gear was clicked on that panel and wrong
            // here: it dragged the whole island open on every launch, so a
            // rebuild landed on a 756-point panel of rows that had not yet read
            // anything, next to the window actually being looked at.
            opensSettingsAlone = true
            openSettings(at: page)
        }
    }

    /// The settings page named by `--settings-page <id>`, if any.
    ///
    /// TWO dashes deliberately. `UserDefaults` parses the argument domain and
    /// reads any `-name value` pair as a preference, so a single dash would
    /// quietly write a setting called `settings-page` rather than being read
    /// here. Two dashes are invisible to it.
    private static func requestedSettingsPage() -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "--settings-page"),
              arguments.index(after: flag) < arguments.endIndex else { return nil }
        let page = arguments[arguments.index(after: flag)]
        return page.isEmpty ? nil : page
    }

    /// Record that the reading was agreed to, and start what is switched on.
    private func acceptReading() {
        guard let registry, let context else { return }
        context.settings.hasAcceptedReading = true
        registry.syncRunning(context: context)
    }

    /// Say no, and mean it.
    ///
    /// Quitting is the whole answer. Nothing has read anything yet — that is
    /// the point of the gate — so there is no reading to stop and no state to
    /// unwind. Leaving the app running on a refusal would leave something in
    /// the notch doing nothing, waiting to ask again.
    ///
    /// The preferences are removed on the way out, so refusing leaves the Mac
    /// as it was found. It is a new install by definition (the window only
    /// appears when nobody has answered), so the only thing in that file is
    /// defaults nobody chose — and an app told no should not leave a file
    /// behind to remember being told. Opening it again asks again, which is
    /// the correct behaviour for somebody who changes their mind.
    private func declineReading() {
        registry?.stopAll()
        declined = true
        forgetPreferences()
        NSApp.terminate(nil)
    }

    /// Wipe the app's stored settings.
    ///
    /// Called twice on a refusal, deliberately. The store saves on the next
    /// runloop tick rather than immediately, so a write scheduled before the
    /// refusal could land after the file was removed and quietly recreate the
    /// very thing that was just deleted. Doing it again as the last act before
    /// the process exits means the file is gone whatever the ordering was.
    private func forgetPreferences() {
        guard let domain = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }

    private func restartFeatures() {
        guard let registry, let context else { return }
        registry.stopAll()
        registry.syncRunning(context: context)
    }

    private func toggleSettings() {
        guard let controller, let settingsWindow else { return }
        settingsWindow.toggle(anchor: controller.panelAnchor, on: NotchGeometry.preferredScreen())
    }

    /// Open settings ON a page, for when the island has named a switch.
    private func openSettings(at page: String) {
        guard let controller, let settingsWindow else { return }
        settingsWindow.show(
            anchor: controller.panelAnchor,
            on: NotchGeometry.preferredScreen(),
            section: page
        )
    }

    /// Start or stop the features whose switch has just changed.
    private func syncFeatures() {
        guard let registry, let context else { return }
        registry.syncRunning(context: context)
    }

    private func scheduleOverlayRebuild() {
        rebuildWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.rebuildOverlay() }
        }
        rebuildWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Give a controller everything it cannot reach on its own.
    ///
    /// Every one of these is a closure onto something the controller has no
    /// way to see — the settings window it must not dismiss itself for, and
    /// the panel a feature may need to get out of the way. They exist in one
    /// place because a REBUILT overlay needs exactly the same set, and until
    /// now it got none of them: `rebuildOverlay` made a fresh controller and
    /// wired nothing, so after any screen change the new controller believed
    /// there was no settings window at all. A click inside settings then
    /// looked like a click on empty space and shut the panel — the bug this
    /// went looking for, still live in a second form after the first was
    /// fixed. Adding a closure here now reaches both paths by construction.
    ///
    /// Everything this needs is a PARAMETER, and that is the whole point.
    /// These closures used to capture `self.settingsWindow`, and a capture
    /// list reads the property once, at the moment the closure is made — which
    /// at launch is before that property has been assigned. All three captured
    /// nil and stayed nil for the life of the app: the overlay could not see
    /// the settings window's frame, could not recognise a click inside it, and
    /// could not close it. That is why a click away shut the panel and left
    /// settings sitting there needing a second click, and why clicking inside
    /// settings dismissed the panel behind it. Taking the window as an argument
    /// makes the mistake unsayable — there is nothing to read too early.
    private func wire(
        _ controller: NotchWindowController,
        context: FeatureContext,
        settingsWindow: SettingsWindowController
    ) {
        // So a feature can get out of the way of a system dialog it just
        // raised. Wired here, like openSettings, because the controller does
        // not exist until now.
        context.closePanel = { [weak controller] in controller?.collapse() }
        // The quit button's version of the above: everything the app has on
        // screen goes, whatever is holding it open, and hover is told to stand
        // down so the pointer still sitting on the panel cannot put it back.
        context.dismissAll = { [weak controller] in controller?.dismissAll() }
        // So a click anywhere that is not this app puts the whole thing away.
        // The controller cannot see the settings window, and the settings
        // window can be dragged, so it asks rather than being told once.
        controller.settingsFrame = { [weak settingsWindow] in settingsWindow?.visibleFrame }
        controller.isSettingsWindow = { [weak settingsWindow] window in
            settingsWindow?.owns(window) == true
        }
        controller.closeSettings = { [weak settingsWindow] in settingsWindow?.hide() }
        // So a switch that is about to make macOS ask for something can clear
        // the screen first. Both of this app's windows sit above the ordinary
        // level, so a permission dialog opens behind them otherwise.
        settingsWindow.onDismissAll = { [weak controller] in controller?.dismissAll() }
    }

    private func rebuildOverlay() {
        guard let registry, let context, let settingsWindow else { return }
        controller?.hide()
        let fresh = NotchWindowController(registry: registry, context: context)
        wire(fresh, context: context, settingsWindow: settingsWindow)
        fresh.show()
        controller = fresh
        // A display change builds a new overlay, and the new one knows nothing
        // about the settings still open beside it. Without this the panel it is
        // attached to would quietly collapse behind it.
        if settingsWindow.isVisible { fresh.setPinnedOpen(true) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Last chance to honour a refusal, after any coalesced save has had its
        // turn. Nothing else may write preferences from here on.
        if declined { forgetPreferences() }
        rebuildWork?.cancel()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        power?.end()
        registry?.stopAll()
    }
}
