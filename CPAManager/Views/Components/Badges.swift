import SwiftUI

/// Small colored pill for a project status.
struct StatusBadge: View {
    let status: ProjectStatus
    var flow: StatusFlow = .taxReturn
    var body: some View {
        Label(flow.label(status), systemImage: status.systemImage)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.15), in: Capsule())
            .foregroundStyle(status.color)
    }
}

struct ClientStatusBadge: View {
    let status: ClientStatus
    var body: some View {
        Label(status.label, systemImage: status.systemImage)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.15), in: Capsule())
            .foregroundStyle(status.color)
    }
}

struct EntityBadge: View {
    let entityType: EntityType
    var body: some View {
        Text(entityType.code)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

struct InvoiceStatusBadge: View {
    let status: InvoiceStatus
    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.15), in: Capsule())
            .foregroundStyle(status.color)
    }
}

struct QBOSyncStateBadge: View {
    let state: QBOSyncState
    var body: some View {
        Label(state.label, systemImage: state.systemImage)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(state.color.opacity(0.15), in: Capsule())
            .foregroundStyle(state.color)
    }
}

struct PriorityBadge: View {
    let priority: Priority
    var body: some View {
        if priority != .normal {
            Text(priority.label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(priority.color.opacity(0.15), in: Capsule())
                .foregroundStyle(priority.color)
        }
    }
}

/// Rounded icon tile for a service type.
struct ServiceTypeIcon: View {
    let serviceType: ServiceType
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: serviceType.systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Theme.brand)
            .frame(width: size, height: size)
            .background(Theme.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}
