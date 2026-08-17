import HashNotchKit
import FeatureNetwork
import FeatureBattery
import FeatureThermal
import FeatureTokens
import FeatureMedia
import FeatureActivities
import FeatureTimer
import FeatureDownloads
import FeatureAirPods
import FeatureCall
import FeatureStorage
import FeatureCPU
import FeatureMemory

/// The one and only place features are turned on or off.
///
/// ── To ADD a feature ──────────────────────────────────────────────
///   1. Create `Sources/Feature<Name>/…` with a type conforming to
///      `NotchFeature`.
///   2. Add the target (and its dependency on this executable) in Package.swift.
///   3. `import Feature<Name>` above and add one line to the array below.
///
/// ── To REMOVE a feature ───────────────────────────────────────────
///   Delete its line below. (Optionally delete its module + Package.swift entry.)
///
/// The core (HashNotchKit) never changes for either.
enum FeatureManifest {
    /// Which features exist. The ORDER they appear in on a fresh install is
    /// `FeatureRegistry.defaultOrder`, applied below — so this list can stay
    /// whatever reads most clearly, and adding a line here can never silently
    /// rearrange everybody's panel. A feature not named in that order simply
    /// goes to the end, which is what a new one should do.
    @MainActor
    static func enabledFeatures() -> [NotchFeature] {
        FeatureRegistry.inDefaultOrder([
            MediaFeature(),
            ActivitiesFeature(),
            DownloadsFeature(),
            TimerFeature(),
            TokensFeature(),
            NetworkFeature(),
            BatteryFeature(),
            AirPodsFeature(),
            CallFeature(),
            ThermalFeature(),
            CPUFeature(),
            MemoryFeature(),
            StorageFeature(),
        ])
    }
}
