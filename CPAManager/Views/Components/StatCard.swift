import SwiftUI

/// Compact metric tile used on the dashboard.
struct StatCard: View {
    let value: String
    let label: String
    let systemImage: String
    var color: Color = Theme.brand

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(color)
            Text(value)
                .font(.title.bold())
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
