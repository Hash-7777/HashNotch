import SwiftUI
import AppKit

/// A frosted-glass background (like macOS Control Center), backed by
/// `NSVisualEffectView` with behind-window blending so it blurs the wallpaper
/// and windows behind it.
public struct VisualEffectView: NSViewRepresentable {
    public let material: NSVisualEffectView.Material

    public init(material: NSVisualEffectView.Material = .hudWindow) {
        self.material = material
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    public func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
