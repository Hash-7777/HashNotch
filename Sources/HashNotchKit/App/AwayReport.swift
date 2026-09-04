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

    /// The last spell away, whether or not it was worth a digest.
    ///
    /// The digest above needs something to have CHANGED and five minutes to
    /// have passed. A tally of the day needs neither: two minutes away is still
    /// two minutes away, and a piece of work you walked out of was walked out
    /// of however little happened while you were gone. So this is recorded on
    /// every return and the digest is decided separately.
    @Published public private(set) var lastReturn: AwaySpell?

    public init() {}

    public func recordReturn(leftAt: Date, returnedAt: Date) {
        lastReturn = AwaySpell(leftAt: leftAt, returnedAt: returnedAt)
    }

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

/// One spell with the screen away.
public struct AwaySpell: Equatable, Sendable {
    public let leftAt: Date
    public let returnedAt: Date

    public init(leftAt: Date, returnedAt: Date) {
        self.leftAt = leftAt
        self.returnedAt = returnedAt
    }
}
