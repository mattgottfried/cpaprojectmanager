import SwiftUI

/// Circular initials bubble for a client.
struct Avatar: View {
    let initials: String
    var size: CGFloat = 44

    var body: some View {
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [Theme.brand, Theme.brandDark],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Circle()
            )
    }
}
