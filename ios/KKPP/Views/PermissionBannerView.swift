import SwiftUI

struct PermissionBannerView: View {
    let microphoneAuthorized: Bool
    let speechAuthorized: Bool
    let calendarGranted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(statusText, systemImage: statusIcon)
                .font(.subheadline.weight(.semibold))
            Text(detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var allGranted: Bool {
        microphoneAuthorized && speechAuthorized && calendarGranted
    }

    private var statusText: String {
        allGranted ? "所有核心权限已就绪" : "请确认 KKPP 权限设置"
    }

    private var detailText: String {
        allGranted
            ? "你可以直接按住麦克风说出日程需求，我会帮你整理并加入日历。"
            : "KKPP 需要麦克风、语音识别和日历权限，才能像私人秘书一样帮你完成记录和查询。"
    }

    private var statusIcon: String {
        allGranted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
    }
}
