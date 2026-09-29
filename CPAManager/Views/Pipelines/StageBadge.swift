import SwiftUI

extension StageColor {
    var color: Color {
        switch self {
        case .gray:   return .gray
        case .blue:   return .blue
        case .teal:   return .teal
        case .green:  return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .red:    return .red
        case .purple: return .purple
        }
    }
}

/// Stage pill for either kind of pipeline (built-in status or custom stage).
struct StageBadge: View {
    let info: StageInfo

    var body: some View {
        Label(info.name, systemImage: info.systemImage)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(info.color.color.opacity(0.15), in: Capsule())
            .foregroundStyle(info.color.color)
    }
}
