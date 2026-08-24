# Architecture

HashNotch is built so that every capability is a **plug-in**. The core knows how
to draw an island around the notch and how to talk to a feature through one small
protocol — it never knows what any feature actually does. That is what lets
features be added or removed without editing the core.

## Modules

```
HashNotchKit      Core framework. Notch detection, the overlay window, the
                  island and panel, the theme, shared UI pieces, settings, and
                  the NotchFeature contract. Depends on nothing in this repo.

FeatureMedia      One self-contained feature each. Every feature module depends
FeatureActivities only on HashNotchKit — never on another feature.
FeatureDownloads
FeatureTimer
FeatureTokens
FeatureNetwork
FeatureBattery
FeatureAirPods
FeatureCall
FeatureThermal
FeatureCPU
FeatureMemory
FeatureStorage

HashNotch       The executable. The only place features are wired together.
                  Depends on the core + every feature it enables.

HashNotchChecks   Framework-free checks for the core and the parsers, runnable
                  under the Command Line Tools (`swift run HashNotchChecks`).
```

Dependencies only ever point **inward** toward the core:

```
FeatureMedia ────┐
FeatureBattery ──┼─▶ HashNotchKit
… every other ───┘
       ▲
HashNotch ─────┘   (also depends on each feature, to register them)
```

## The feature contract

Every feature implements `NotchFeature` (in `HashNotchKit`):

```swift
@MainActor
public protocol NotchFeature: AnyObject {
    var id: String { get }
    var title: String { get }
    var placement: FeaturePlacement { get }
    var displayOptions: [FeatureOption] { get }

    /// Compact readout.
    func makeView(context: FeatureContext) -> AnyView
    /// Richer row for the open panel; nil to show nothing there.
    func makeExpandedView(context: FeatureContext) -> AnyView?
    /// Always-on views flanking the notch while this feature is live;
    /// nil for none.
    func makeCompactLeadingView(context: FeatureContext) -> AnyView?
    func makeCompactTrailingView(context: FeatureContext) -> AnyView?

    /// Where this feature comes in the queue for the live strip.
    var livePriority: Int { get }
    /// The colour the island's edge wears while this feature owns the strip,
    /// and how hard that line should press. nil / 0 for no colour at all.
    var outlineTint: Color? { get }
    var outlineUrgency: Double { get }
    /// Handle a sideways swipe across the open panel; false to pass it on.
    func handleSwipe(_ direction: SwipeDirection) -> Bool

    func start(context: FeatureContext)   // begin sampling
    func stop()                           // release resources
}
```

Everything but `id`, `title`, `placement` and `makeView` has a default, so a
simple feature implements four members.

A feature owns its own data source (an `ObservableObject` monitor) and its own
SwiftUI views. `FeatureContext` is how it reaches shared services: the settings
store, `LivePresence` (to say "I have something live right now"), and the
closure that opens the settings window.

## The three states

`NotchIslandView` draws three separate layers, stacked, each with its own shape:

- **Collapsed** — a black shape matching the physical notch exactly, so at rest
  the app is invisible. On a display with no notch there is nothing to hide
  behind, so `NotchGeometry` hangs the island from the top of the screen exactly
  as the hardware notch does and makes it exactly as tall as the menu bar,
  filling the band between the app menus and the status icons rather than
  floating below the bar attached to nothing.
- **Live** — a slim strip that appears *beside* the notch, at menu-bar height,
  whenever any feature signals `LivePresence`: artwork and title to one side,
  a countdown to the other. No hover needed.
- **Expanded** — a rounded panel that drops straight down below the menu bar,
  listing every enabled feature's `makeExpandedView`, with the settings gear in
  its corner. Because it opens *below* the menu bar, it can never overlap app
  menus or status items.

Window frames and hover zones both hang from `NotchGeometry.islandTop` rather
than the screen's top edge, which is what lets the notchless case work without
a second layout path. A user's `IslandAdjustment` — remembered per display — is
applied to the measured geometry before anything else reads it, so a hand
correction needs no special case either.

`NotchWindowController` owns the overlay window. The window keeps **one** width
for its whole life — the widest any state needs — and only its height follows
the state. A window sized tight to the current state has to move its left edge
to stay centred on the notch, and that move is instant while SwiftUI animates
the content re-centring inside it; the two do not cancel and the island visibly
sweeps sideways. Growing downward moves nothing that is anchored to the top,
and the unused width is invisible because the window is transparent. Hover is
detected with observe-only mouse-position monitors against tight, hysteretic
zones (a small notch-sized zone to open; a keep-open area that must fully
contain every zone that can trigger opening, or the panel flickers at the
edges). The window is click-through in every state except while the panel is
open.

Low-power behavior also lives in the core: `PollingSampler` uses tolerant,
coalesced timers; monitors publish only when a displayed value actually changes;
`VisibleSampler` keeps panel-only readouts idle until the panel is open; and
`PowerCoordinator` stops all sampling while the screen is asleep.

## Customization (settings)

User choices live in `SettingsStore` (in `HashNotchKit`), persisted to
`UserDefaults`. It is the single source of truth for:

- which features are enabled and in what order,
- each feature's chosen display style,
- appearance (accent, panel fill, corner rounding, motion) and alert length,
- battery saver, which scales every sampling interval,
- the per-display `IslandAdjustment`, and
- open-at-login.

"Enabled" governs whether a feature **runs**, not merely whether it is drawn.
`FeatureRegistry.syncRunning(context:)` reconciles the running set with the
store — starting an enabled feature that is stopped, stopping a disabled one
that is running, and leaving anything already correct untouched — and the app
calls it whenever the feature settings change, on wake, and at launch. A
feature that is off opens no files and spawns no subprocess, which is what
makes the switch a privacy control rather than a display one.

Features declare their display choices via `displayOptions` and read the
selected one with `context.settings.style(for: id)` inside `makeView`. The
island observes the store, so changing a setting updates the notch live.

There is no menu-bar item: `SettingsView` is reached through the gear button in
the expanded panel (`FeatureContext.openSettings`), and it is also where the app
is quit.

## Adding a feature

1. Create `Sources/Feature<Name>/` with:
   - a `Monitor` (`ObservableObject`) that samples your data,
   - a SwiftUI `View`,
   - a type conforming to `NotchFeature` that ties them together.
2. In `Package.swift`, add a `.target(name: "Feature<Name>", dependencies:
   ["HashNotchKit"])` and add `"Feature<Name>"` to the `HashNotch` target's
   dependencies.
3. In `Sources/HashNotch/FeatureManifest.swift`, `import Feature<Name>` and add
   one line to the returned array.

The core (`HashNotchKit`) does not change.

## Removing a feature

Delete its line from `FeatureManifest.swift`. Optionally delete the module folder
and its `Package.swift` entries. Nothing else is affected.

## Why this shape

- **Isolation** — a bug or a rewrite in one feature can't reach another; the
  compiler enforces the module boundaries.
- **Scale** — new features are additive. The core and existing features stay
  untouched, so the risk of each addition stays flat as the app grows.
- **Testability** — the core is verified against a stub feature, with no real
  feature present, proving the decoupling holds.
