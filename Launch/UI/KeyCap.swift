import SwiftUI

/// One key drawn as a small rounded cap.
struct KeyCap: View {
    enum Key: Hashable {
        case command, option, `return`, delete
        case text(String)

        /// SF Symbols, not the Unicode glyphs (⌘ ↩): those sit on the text
        /// baseline and look off-centre inside a cap.
        fileprivate var symbolName: String? {
            switch self {
            case .command: "command"
            case .option: "option"
            case .return: "return"
            case .delete: "delete.left"
            case .text: nil
            }
        }
    }

    let key: Key

    var body: some View {
        content
            .foregroundStyle(.secondary)
            .frame(minWidth: 22)
            .frame(height: 22)
            .padding(.horizontal, 2)
            .background(.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        if let name = key.symbolName {
            Image(systemName: name)
                .font(.system(size: 11, weight: .semibold))
        } else if case .text(let text) = key {
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
    }
}
