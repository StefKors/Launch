import SwiftUI

enum PermissionState {
    case granted
    /// Launch won't work properly until this is done.
    case needed
    /// Nice to have; the app works without it.
    case optional
}

/// One permission or system setting: its state, why it matters, and the
/// buttons that fix it.
struct PermissionRow<Actions: View>: View {
    let state: PermissionState
    let title: String
    let detail: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PermissionStatusIcon(state: state)
                .font(.system(size: 20))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    if state == .optional {
                        Text("Optional")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.primary.opacity(0.08), in: Capsule())
                    }
                }
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if state != .granted {
                    HStack(spacing: 8) { actions }
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The check, warning or dashed circle in front of a permission.
private struct PermissionStatusIcon: View {
    let state: PermissionState

    var body: some View {
        switch state {
        case .granted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .needed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .optional:
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        }
    }
}
