import CoreLocation
import EventKit
import Intents
import SwiftUI
import UserNotifications

struct PermissionBannerView: View {
    let microphoneAuthorized: Bool
    let speechAuthorized: Bool
    let calendarStatus: EKAuthorizationStatus
    let locationStatus: CLAuthorizationStatus
    let reminderStatus: EKAuthorizationStatus
    let notificationStatus: UNAuthorizationStatus
    let siriStatus: INSiriAuthorizationStatus
    let connectionState: ChatViewModel.ConnectionState
    let backendHost: String
    let requestSpeech: () -> Void
    let requestCalendar: () -> Void
    let requestLocation: () -> Void
    let requestReminders: () -> Void
    let requestNotifications: () -> Void
    let requestSiri: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label(statusText, systemImage: statusIcon)
                    .font(.subheadline.weight(.semibold))
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("后端地址：\(backendHost)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                permissionChip(title: "麦克风", granted: microphoneAuthorized, action: requestSpeech)
                permissionChip(title: "语音识别", granted: speechAuthorized, action: requestSpeech)
                permissionChip(title: "日历", granted: calendarGranted, action: requestCalendar)
                permissionChip(title: "定位", granted: locationGranted, action: requestLocation)
                permissionChip(title: "通知", granted: notificationGranted, action: requestNotifications)
                permissionChip(title: "提醒事项", granted: reminderGranted, action: requestReminders)
                permissionChip(title: "Siri", granted: siriGranted, action: requestSiri)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private func permissionChip(title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: granted ? "checkmark.seal.fill" : "plus.circle")
                    .foregroundStyle(granted ? .green : .blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(granted ? "已开启" : "点按授权")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.92))
            )
        }
        .buttonStyle(.plain)
    }

    private var calendarGranted: Bool {
        calendarStatus == .fullAccess || calendarStatus == .writeOnly
    }

    private var locationGranted: Bool {
        locationStatus == .authorizedAlways || locationStatus == .authorizedWhenInUse
    }

    private var reminderGranted: Bool {
        reminderStatus == .fullAccess || reminderStatus == .writeOnly
    }

    private var notificationGranted: Bool {
        notificationStatus == .authorized || notificationStatus == .provisional || notificationStatus == .ephemeral
    }

    private var siriGranted: Bool {
        siriStatus == .authorized
    }

    private var allGranted: Bool {
        microphoneAuthorized && speechAuthorized && calendarGranted && locationGranted && reminderGranted && notificationGranted && siriGranted
    }

    private var statusText: String {
        switch connectionState {
        case .checking:
            return "正在检查本地连接与系统能力"
        case .connected:
            return allGranted ? "所有系统能力已就绪" : "还差几项系统能力待开启"
        case .disconnected:
            return "本地后端未连接"
        }
    }

    private var detailText: String {
        switch connectionState {
        case .checking:
            return "KKPP 正在检查设备时间、定位、天气和系统权限。"
        case .connected:
            return allGranted
                ? "现在可以更准确理解“今天下午”“到场前提醒”“按当前位置判断天气”等表达。"
                : "建议把定位、通知、提醒事项、Siri 一起打开，这样提醒和日程联动才完整。"
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
