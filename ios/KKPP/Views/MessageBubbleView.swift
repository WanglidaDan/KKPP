import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    var onEditTime: ((ChatMessage.SchedulePreview) -> Void)? = nil
    var onEditRepeat: ((ChatMessage.SchedulePreview) -> Void)? = nil
    var onDelete: ((ChatMessage.SchedulePreview) -> Void)? = nil
    var onAddLocation: ((ChatMessage.SchedulePreview) -> Void)? = nil
    var onSelectOperation: ((UUID, UUID) -> Void)? = nil
    var onConfirmOperation: ((UUID) -> Void)? = nil
    var onCancelOperation: ((UUID) -> Void)? = nil

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 52)
                messageContent
            } else {
                messageContent
                Spacer(minLength: 26)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder
    private var messageContent: some View {
        if let operationCard = message.operationCard {
            operationCardView(operationCard)
        } else if let schedulePreview = message.schedulePreview {
            scheduleCard(schedulePreview)
        } else {
            textMessage
        }
    }

    private var textMessage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message.content)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .lineSpacing(4)
                .foregroundStyle(.white.opacity(0.96))
                .frame(
                    maxWidth: message.role == .assistant ? .infinity : 300,
                    alignment: .leading
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(bubbleColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )

            if message.role != .user, !message.statusLines.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(message.statusLines, id: \.self) { line in
                        Text(line)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.34))
                    }
                }
                .padding(.horizontal, 6)
            }
        }
        .frame(maxWidth: message.role == .assistant ? .infinity : 320, alignment: .leading)
    }

    private var bubbleColor: Color {
        switch message.role {
        case .user:
            return Color(hex: 0x10B981)
        case .assistant:
            return Color(hex: 0x1F1F1F)
        case .system:
            return Color(hex: 0x141414)
        }
    }

    private var borderColor: Color {
        switch message.role {
        case .user:
            return Color.clear
        case .assistant:
            return Color.white.opacity(0.04)
        case .system:
            return Color.green.opacity(0.18)
        }
    }

    private func operationCardView(_ card: ChatMessage.OperationCard) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if card.style == .completed {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x10B981))
                    Text(card.headline)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text(card.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.56))
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.headline)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(card.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.58))
                }
            }

            VStack(spacing: 10) {
                ForEach(card.items) { item in
                    Button {
                        onSelectOperation?(message.id, item.id)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 5) {
                                Circle()
                                    .fill(itemIndicatorColor(card: card, item: item))
                                    .frame(width: 12, height: 12)
                                Text(item.kind.title)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.44))
                            }
                            .frame(width: 28)

                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.48))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            VStack(alignment: .trailing, spacing: 10) {
                                Text(item.timeText)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.64))
                                Image(systemName: card.style == .completed ? "chevron.right" : "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(card.selectedItemID == item.id ? Color(hex: 0x10B981) : .white.opacity(0.32))
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(hex: 0x181818))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(card.selectedItemID == item.id ? Color(hex: 0x10B981) : Color.white.opacity(0.05), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if card.style == .proposal {
                VStack(alignment: .leading, spacing: 10) {
                    Text("需要补充信息")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.54))

                    HStack(spacing: 10) {
                        Button("删除") {
                            onCancelOperation?(message.id)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )

                        Button(card.confirmationTitle) {
                            onConfirmOperation?(message.id)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(hex: 0x10B981))
                        )
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(hex: 0x121212))
                .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private func itemIndicatorColor(card: ChatMessage.OperationCard, item: ChatMessage.OperationItem) -> Color {
        if card.style == .completed {
            return Color(hex: 0x10B981)
        }
        return card.selectedItemID == item.id ? Color(hex: 0x10B981) : Color.white.opacity(0.15)
    }

    private func scheduleCard(_ preview: ChatMessage.SchedulePreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Circle()
                    .fill(Color(hex: 0x10B981))
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 6) {
                    Text(preview.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(preview.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(preview.location)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.84))
                Text(preview.reminderText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                actionButton("改时间", systemImage: "calendar.badge.clock", tint: Color(hex: 0x1E40AF)) {
                    onEditTime?(preview)
                }
                actionButton("改重复", systemImage: "repeat", tint: Color.white.opacity(0.12)) {
                    onEditRepeat?(preview)
                }
                actionButton("删除", systemImage: "trash", tint: Color.red.opacity(0.18)) {
                    onDelete?(preview)
                }
                actionButton("加地点", systemImage: "mappin.and.ellipse", tint: Color.green.opacity(0.16)) {
                    onAddLocation?(preview)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(hex: 0x121212))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private func actionButton(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(.white.opacity(0.88))
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(tint)
                )
        }
        .buttonStyle(.plain)
    }
}

private extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
