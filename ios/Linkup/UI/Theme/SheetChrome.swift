import SwiftUI

/// The one close button every sheet uses: a 44pt glass circle with an xmark, placed top-trailing.
struct SheetCloseButton: View {
    var action: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            if let action { action() } else { dismiss() }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Close")
    }
}

/// Standard sheet header: centered title, optional leading control, close button trailing.
struct SheetHeader<Leading: View>: View {
    let title: String
    var onClose: (() -> Void)?
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        ZStack {
            Text(title)
                .font(Theme.sans(17).weight(.semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            HStack {
                leading()
                Spacer()
                SheetCloseButton(action: onClose)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}

extension SheetHeader where Leading == EmptyView {
    init(title: String, onClose: (() -> Void)? = nil) {
        self.init(title: title, onClose: onClose, leading: { EmptyView() })
    }
}
