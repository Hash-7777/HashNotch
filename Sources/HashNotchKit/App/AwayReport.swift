import Combine
import Foundation

/// The digest waiting to be shown, if there is one.
///
/// A shared service on `FeatureContext`, like presence and visibility, so the
/// feature that DRAWS the digest never has to know which features supplied the
/// numbers in it — and none of those features has to know it is being read.
/// Both ends only ever talk to the core.
@MainActor
public final class AwayReport: ObservableObject {
    /// The line to show, or nil when there is nothing worth saying.
    @Published public private(set) var line: String?
    /// What went into it, for the panel, which has room to break it up.
    @Published public private(set) var changes: [AwayChange] = []
    @Published public private(set) var awayFor: TimeInterval = 0

    public init() {}

    public func post(line: String, changes: [AwayChange], awayFor: TimeInterval) {
        self.line = line
        self.changes = changes
        self.awayFor = awayFor
    }

    /// Read and done. A digest is a thing that happened once; leaving it up
    /// until something else displaces it would turn news into decoration.
    public func clear() {
        line = nil
        changes = []
        awayFor = 0
    }
}
