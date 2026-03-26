import SwiftUI

struct PermissionBannerView: View {
    let microphoneAuthorized: Bool
    let speechAuthorized: Bool
    let calendarGranted: Bool
    let connectionState: ChatViewModel.ConnectionState
    let backendHost: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(statusText, systemImage: statusIcon)
                .font(.subheadline.weight(.semibold))
            Text(detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("后端地址：\(backendHost)")
                .font(.caption2)
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
        switch connectionState {
        case .checking:
            return "正在检查本地连接"
        case .connected:
            return allGranted ? "所有核心权限已就绪" : "请确认 KKPP 权限设置"
        case .disconnected:
            return "未连接到本地后端"
        }
    }

    private var detailText: String {
        switch connectionState {
        case .checking:
            return "KKPP 正在检查与你的本地后端是否连通。"
        case .connected:
            return allGranted
                ? "你可以直接按住麦克风说出日程需求，我会帮你整理并加入日历。"
                : "KKPP 需要麦克风、语音识别和日历权限，才能像私人秘书一样帮你完成记录和查询。"
        case .disconnected(let reason):
            return reason
        }
    }

    private var statusIcon: String {
        switch connectionState {
        case .checking:
            return "antenna.radiowaves.left.and.right"
        case .connected:
            return allGranted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
        case .disconnected:
            return "wifi.exclamationmark"
        }
    }
}
