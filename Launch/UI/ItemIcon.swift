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
        case .tile(let symbol, let tint):
            // Squircle like a macOS app icon: a soft top-to-bottom gradient
            // and a faint edge, with a white glyph.
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [tint.color.opacity(0.85), tint.color], startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), lineWidth: max(0.5, size * 0.02))
                }
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.5, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
        }
    }
}

extension IconTint {
    var color: Color {
        switch self {
        case .red: Color(red: 0.93, green: 0.23, blue: 0.22)
        }
    }
}
