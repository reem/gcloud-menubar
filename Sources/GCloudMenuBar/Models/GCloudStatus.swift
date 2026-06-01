import Foundation

struct GCloudStatus: Equatable {
    var gcloudPath: String?
    var activeAccount: String?
    var activeProject: String?
    var accessTokenExpiry: Date?
    var applicationDefaultCredentials: ADCStatus
    var lastChecked: Date?
    var detail: String

    static let empty = GCloudStatus(
        gcloudPath: nil,
        activeAccount: nil,
        activeProject: nil,
        accessTokenExpiry: nil,
        applicationDefaultCredentials: .missing,
        lastChecked: nil,
        detail: "Checking gcloud..."
    )

    var isAuthenticated: Bool {
        activeAccount?.isEmpty == false
    }
}

enum ADCStatus: Equatable {
    case configured(label: String, quotaProject: String?)
    case missing
    case unreadable(String)

    var title: String {
        switch self {
        case .configured:
            return "Configured"
        case .missing:
            return "Not configured"
        case .unreadable:
            return "Unreadable"
        }
    }

    var detail: String {
        switch self {
        case let .configured(label, quotaProject):
            if let quotaProject, !quotaProject.isEmpty {
                return "\(label) - \(quotaProject)"
            }
            return label
        case .missing:
            return "No application default credentials file"
        case let .unreadable(message):
            return message
        }
    }
}

enum AuthOperation: Equatable {
    case none
    case userLogin
    case applicationDefaultLogin
    case userTokenRefresh
    case applicationDefaultTokenRefresh

    var title: String {
        switch self {
        case .none:
            return ""
        case .userLogin:
            return "Running auth login..."
        case .applicationDefaultLogin:
            return "Running ADC login..."
        case .userTokenRefresh:
            return "Refreshing user token..."
        case .applicationDefaultTokenRefresh:
            return "Refreshing ADC token..."
        }
    }

    var isLoginFlow: Bool {
        self == .userLogin || self == .applicationDefaultLogin
    }
}
