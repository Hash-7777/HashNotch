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
///
/// A row may also carry an ACCESSORY: something that belongs to the label
/// rather than to the value, drawn immediately after the words.
///
/// The battery is why this exists. Its drawn shape had been sitting on the
/// right, in among the figures, where it read as one more value — and it is not
/// one. It is a picture of what the row is about, which is what a label is for.
/// Beside the word, it names the row; beside the numbers, it competes with them.
public struct NotchRow<Accessory: View, Trailing: View>: View {
    let label: String
    let emphasized: Bool
    let theme: Theme
    let accessory: Accessory
    let trailing: Trailing

    public init(
        _ label: String,
        emphasized: Bool = false,
        theme: Theme,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.label = label
        self.emphasized = emphasized
        self.theme = theme
        self.accessory = accessory()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 12) {
            // The label and anything belonging to it travel together, close,
            // and the 12-point column gap stays between the label and the
            // VALUE where it belongs. An accessory a column-gap away from its
            // own words reads as a third thing on the row.
            HStack(spacing: 6) {
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
            accessory
            }
            Spacer(minLength: 8)
            trailing
                // The value gets the room it needs before the label does.
                //
                // Both are held to one line, so when the two together do not
                // fit, something has to give — and without saying which,
                // SwiftUI squeezed them evenly and cut the FIGURE short. A
                // month's download came out as "14.18…", which is the one thing
                // in the row that cannot survive being abbreviated: a label can
                // be inferred from the row it is on, and a number cannot be
                // inferred from anything.
                .layoutPriority(1)
                // The same rule as the label, and for the same reason.
                //
                // Holding the label to one line fixed half the problem and left
                // the other half in plain sight: the VALUE is caller-supplied
                // and was unconstrained, so a long one wrapped instead — "held
                // at 80% for battery health" became two lines and took the row
                // and everything under it down with it.
                //
                // This binds each piece of TEXT to one line, not the container,
                // so a row that deliberately stacks two figures still stacks
                // them. Only wrapping is prevented, which was never intended
                // anywhere.
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: Panel.rowWidth)
    }
}

/// The ordinary row, with no accessory. Every existing caller keeps working
/// unchanged; only a row that wants a picture beside its name says so.
extension NotchRow where Accessory == EmptyView {
    public init(
        _ label: String,
        emphasized: Bool = false,
        theme: Theme,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            label, emphasized: emphasized, theme: theme,
            accessory: { EmptyView() }, trailing: trailing
        )
    }
}
