import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .assistant || message.role == .system {
                bubble
                Spacer(minLength: 48)
            } else {
                Spacer(minLength: 48)
                bubble
            }
        }
    }

    private var bubble: some View {
        Text(message.content)
            .font(.body)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .foregroundStyle(textColor)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(backgroundColor)
            )
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return Color(red: 0.12, green: 0.41, blue: 0.81)
        case .assistant, .system:
            return Color(.secondarySystemBackground)
        }
    }

    private var textColor: Color {
        message.role == .user ? .white : .primary
    }
}
