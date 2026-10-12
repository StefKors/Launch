import SwiftUI

struct ItemIcon: View {
    let icon: LauncherItem.Icon
    var size: CGFloat = 32

    var body: some View {
        switch icon {
        case .file(let path):
            Image(nsImage: IconCache.shared.icon(forFile: path))
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.55))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}
