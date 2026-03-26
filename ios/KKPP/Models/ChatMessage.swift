import Foundation

struct ChatMessage: Identifiable, Equatable {
    enum Role {
        case user
        case assistant
        case system
    }

    enum OperationKind: String, Equatable {
        case execute
        case delete
        case query

        var title: String {
            switch self {
            case .execute: "执行"
            case .delete: "删除"
            case .query: "查询"
            }
        }
    }

    enum OperationCardStyle: Equatable {
        case proposal
        case completed
    }

    struct SchedulePreview: Equatable {
        let eventID: String?
        let title: String
        let subtitle: String
        let location: String
        let reminderText: String
        let startDate: Date
        let endDate: Date
    }

    struct OperationItem: Identifiable, Equatable {
        let id: UUID
        let title: String
        let detail: String
        let timeText: String
        let kind: OperationKind
        let eventID: String?

        init(
            id: UUID = UUID(),
            title: String,
            detail: String,
            timeText: String,
            kind: OperationKind,
            eventID: String? = nil
        ) {
            self.id = id
            self.title = title
            self.detail = detail
            self.timeText = timeText
            self.kind = kind
            self.eventID = eventID
        }
    }

    struct OperationCard: Equatable {
        let id: UUID
        let style: OperationCardStyle
        let headline: String
        let subtitle: String
        let items: [OperationItem]
        let needsConfirmation: Bool
        let confirmationTitle: String
        var selectedItemID: UUID?

        init(
            id: UUID = UUID(),
            style: OperationCardStyle,
            headline: String,
            subtitle: String,
            items: [OperationItem],
            needsConfirmation: Bool = false,
            confirmationTitle: String = "确认",
            selectedItemID: UUID? = nil
        ) {
            self.id = id
            self.style = style
            self.headline = headline
            self.subtitle = subtitle
            self.items = items
            self.needsConfirmation = needsConfirmation
            self.confirmationTitle = confirmationTitle
            self.selectedItemID = selectedItemID
        }
    }

    let id: UUID
    let role: Role
    var content: String
    let createdAt: Date
    let schedulePreview: SchedulePreview?
    var statusLines: [String]
    var operationCard: OperationCard?

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        createdAt: Date = Date(),
        schedulePreview: SchedulePreview? = nil,
        statusLines: [String] = [],
        operationCard: OperationCard? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.schedulePreview = schedulePreview
        self.statusLines = statusLines
        self.operationCard = operationCard
    }
}
