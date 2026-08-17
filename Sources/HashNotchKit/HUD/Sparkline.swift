import SwiftUI

/// A small filled line chart of recent samples, for readouts where the shape of
/// the last half-minute says more than the current number.
///
/// Values are given already normalised to 0...1, because only the caller knows
/// what its own ceiling means — a processor tops out at 1 by definition, where
/// a network graph has to pick a scale from what it has seen.
///
/// Draws nothing at all below two points. One sample is not a trend, and a
/// single dot on an axis reads as a fault rather than as "not enough yet".
public struct Sparkline: View {
    private let values: [Double]
    private let tint: Color
    /// Whether to draw the floor and ceiling the values are measured against.
    private let showsScale: Bool

    public init(values: [Double], tint: Color, showsScale: Bool = false) {
        self.values = values
        self.tint = tint
        self.showsScale = showsScale
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                if showsScale { scale(in: geo.size) }
                line(in: geo.size)
            }
        }
    }

    /// A solid rule at nothing and a dashed one at full.
    ///
    /// Without them a line is only readable against itself: a processor idling
    /// and a processor at half draw the same shape, because the eye has nothing
    /// to measure the height against. The floor is solid because it is a real
    /// value — zero — and the ceiling dashed because it is a limit rather than a
    /// reading. Both sit well under the line's own weight so the data still
    /// leads.
    private func scale(in size: CGSize) -> some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 0, y: size.height - 1))
                path.addLine(to: CGPoint(x: size.width, y: size.height - 1))
            }
            .stroke(Color.white.opacity(0.16), lineWidth: 0.5)

            Path { path in
                path.move(to: CGPoint(x: 0, y: 1))
                path.addLine(to: CGPoint(x: size.width, y: 1))
            }
            .stroke(
                Color.white.opacity(0.10),
                style: StrokeStyle(lineWidth: 0.5, dash: [3, 4])
            )
        }
    }

    /// A shape needs two points; one sample is a dot and none is nothing.
    package static let minimumSamplesForShape = 2

    /// Whether there is still too little to draw a shape, so only the baseline
    /// is shown. Pure and package-visible because what happens BELOW this
    /// threshold is the interesting case: it used to be "draw nothing", which a
    /// reader cannot tell apart from the graph being switched off.
    package static func showsBaselineOnly(sampleCount: Int) -> Bool {
        sampleCount < minimumSamplesForShape
    }

    @ViewBuilder
    private func line(in size: CGSize) -> some View {
        if Self.showsBaselineOnly(sampleCount: values.count) {
            // Not enough samples to draw a shape yet — so draw the floor.
            //
            // Two points are needed for a line, and until then this drew
            // NOTHING: no line, no fill, no dot, just empty space where a graph
            // belongs. That is indistinguishable from the graph being switched
            // off, and it is exactly what somebody meets on a fresh launch,
            // because the readouts that live in the panel only sample while the
            // panel is open. Open it for the first time and the internet graph
            // is simply absent — which reads as "graphs are not on by default"
            // when they are, and sends people into Settings to turn on
            // something that was already on.
            //
            // A flat line at the baseline says the right thing instead: the
            // graph is here, and it has nothing to show yet. It fills in the
            // moment a second sample lands.
            Path { path in
                path.move(to: CGPoint(x: 0, y: size.height - 1))
                path.addLine(to: CGPoint(x: size.width, y: size.height - 1))
            }
            .stroke(tint.opacity(0.45), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        } else {
            let path = shape(in: size)
            ZStack {
                // The fill under the line does the work at this size; the
                // line alone is too thin to read at a glance.
                path.filled(in: size)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.38), tint.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                path.stroked
                    .stroke(
                        tint,
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
                    )
                // A dot on the newest sample, so the eye knows which end is
                // now. Without it a graph reads equally well backwards.
                if let last = path.points.last {
                    Circle()
                        .fill(tint)
                        .frame(width: 3, height: 3)
                        .position(last)
                }
            }
        }
    }

    private func shape(in size: CGSize) -> Line {
        Line(values: values, size: size)
    }

    /// The points, shared by the stroke and the fill so they cannot drift apart.
    private struct Line {
        let values: [Double]
        let size: CGSize

        var points: [CGPoint] {
            guard values.count >= 2 else { return [] }
            let step = size.width / CGFloat(values.count - 1)
            return values.enumerated().map { index, value in
                let clamped = min(max(value, 0), 1)
                // Inset by a hair top and bottom so a flat line at either
                // extreme is still visible rather than welded to the edge.
                let y = size.height - 1 - CGFloat(clamped) * (size.height - 2)
                return CGPoint(x: CGFloat(index) * step, y: y)
            }
        }

        /// A smooth curve through the samples rather than a run of straight
        /// segments.
        ///
        /// At this size a polyline of thirty points reads as a row of spikes —
        /// every sample looks like an event. A curve carries the same data and
        /// shows the shape of it, which is the only thing a graph this small
        /// can usefully say. The control points are the midpoints between
        /// samples, which keeps the curve passing through every reading rather
        /// than smoothing the peaks away.
        var stroked: Path {
            var path = Path()
            let p = points
            guard let first = p.first else { return path }
            path.move(to: first)
            guard p.count > 2 else {
                for point in p.dropFirst() { path.addLine(to: point) }
                return path
            }
            for index in 1..<p.count {
                let previous = p[index - 1]
                let current = p[index]
                let mid = CGPoint(
                    x: (previous.x + current.x) / 2,
                    y: (previous.y + current.y) / 2
                )
                path.addQuadCurve(to: mid, control: previous)
            }
            path.addLine(to: p[p.count - 1])
            return path
        }

        func filled(in size: CGSize) -> Path {
            var path = stroked
            guard let first = points.first, let last = points.last else { return path }
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.addLine(to: CGPoint(x: first.x, y: size.height))
            path.closeSubpath()
            return path
        }
    }
}
