import SwiftUI

/// Shared building blocks so every feature's expanded detail reads as one clean,
/// consistent list — a section header and an aligned label/value row.
public enum Panel {
    /// Standard width for a detail row, so values line up across features.
    public static let rowWidth: CGFloat = 260
}

/// Uppercase, muted section title.
public struct NotchSectionHeader: View {
    let title: String
    let theme: Theme

    public init(_ title: String, theme: Theme) {
        self.title = title
        self.theme = theme
    }

    public var body: some View {
        // Dimmer and more widely spaced than the rows beneath it, not bolder.
        //
        // A heading has to read as a different KIND of thing from the numbers
        // under it, and the obvious way — making it louder — puts it in
        // competition with the readouts, which are the reason the panel is
        // open. Quieter and wider apart reads as a label rather than as data,
        // the way small caps do on a printed page, and it leaves the figures
        // the brightest thing in view.
        Text(title.uppercased())
            .font(.system(size: 8.5, weight: .semibold))
            .kerning(1.1)
            .foregroundStyle(theme.subtitleColor.opacity(0.72))
            .padding(.bottom, 2)
    }
}

/// A label on the left and caller-styled trailing content on the right, aligned
/// to a shared width so columns line up.
public struct NotchRow<Trailing: View>: View {
    let label: String
    let emphasized: Bool
    let theme: Theme
    let trailing: Trailing

    public init(
        _ label: String,
        emphasized: Bool = false,
        theme: Theme,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.label = label
        self.emphasized = emphasized
        self.theme = theme
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundStyle(emphasized ? theme.textColor : theme.subtitleColor)
                // A row is one line, always.
                //
                // The row is a fixed width, so when the value beside it grows —
                // "9.55 GB" where there was "212 MB", two figures where there
                // was one — the label is what gets squeezed, and SwiftUI's
                // answer to a squeezed label is to wrap it. "Used today"
                // becomes two lines, the row becomes twice as tall, and every
                // row below it steps down. That is a panel whose shape depends
                // on how much data somebody has used, which is not a panel.
                //
                // So the label holds its line and gives up a little size
                // instead, down to four fifths — the difference between a label
                // that is momentarily smaller and a layout that jumps.
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            trailing
        }
        .frame(width: Panel.rowWidth)
    }
}
