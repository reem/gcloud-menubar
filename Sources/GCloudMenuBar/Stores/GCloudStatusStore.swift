import Foundation

@MainActor
final class GCloudStatusStore: ObservableObject {
    @Published private(set) var status: GCloudStatus = .empty
    @Published private(set) var authOperation: AuthOperation = .none
    @Published private(set) var isRefreshingStatus = false
    @Published private(set) var lastCommandOutput: String?

    private let service: GCloudService
    private var authCommandWasCancelled = false

    init(service: GCloudService) {
        self.service = service
    }

    var menuTitle: String {
        guard let account = status.activeAccount, !account.isEmpty else {
            return "gcloud"
        }

        let shortAccount = account.split(separator: "@").first.map(String.init) ?? account
        if shortAccount.count <= 18 {
            return shortAccount
        }

        return String(shortAccount.prefix(15)) + "..."
    }

    var menuSystemImage: String {
        status.isAuthenticated ? "cloud.fill" : "exclamationmark.triangle"
    }

    var canStartAuthCommand: Bool {
        authOperation == .none
    }

    var canRefreshStatus: Bool {
        !isRefreshingStatus
    }

    func refresh() async {
        guard !isRefreshingStatus else {
            return
        }

        isRefreshingStatus = true
        status = await service.fetchStatus()
        isRefreshingStatus = false
    }

    func runUserLogin() async {
        await runAuthOperation(.userLogin, successMessage: "gcloud auth login finished.") {
            try await service.runUserLogin()
        }
    }

    func runApplicationDefaultLogin() async {
        await runAuthOperation(.applicationDefaultLogin, successMessage: "ADC login finished.") {
            try await service.runApplicationDefaultLogin()
        }
    }

    func refreshUserAccessToken() async {
        await runAuthOperation(.userTokenRefresh, successMessage: "User access token refreshed.") {
            try await service.refreshUserAccessToken()
        }
    }

    func refreshApplicationDefaultAccessToken() async {
        await runAuthOperation(
            .applicationDefaultTokenRefresh,
            successMessage: "ADC access token refreshed."
        ) {
            try await service.refreshApplicationDefaultAccessToken()
        }
    }

    func cancelAuthOperation() {
        guard authOperation.isLoginFlow else {
            return
        }

        authCommandWasCancelled = true
        service.cancelActiveAuthCommand()
        lastCommandOutput = "Login flow cancelled."
    }

    private func runAuthOperation(
        _ operation: AuthOperation,
        successMessage: String,
        command: () async throws -> CommandResult
    ) async {
        guard authOperation == .none else {
            return
        }

        authOperation = operation
        authCommandWasCancelled = false
        lastCommandOutput = nil

        do {
            let result = try await command()
            if authCommandWasCancelled {
                lastCommandOutput = "Login flow cancelled."
            } else {
                lastCommandOutput = summarize(result: result, successMessage: successMessage)
            }
        } catch {
            lastCommandOutput = authCommandWasCancelled ? "Login flow cancelled." : error.localizedDescription
        }

        authOperation = .none
        authCommandWasCancelled = false
        await refresh()
    }

    private func summarize(result: CommandResult, successMessage: String) -> String {
        if result.exitCode == 0 {
            return successMessage
        }

        let output = result.combinedOutput
        if !output.isEmpty {
            return output
        }

        return "Command exited with status \(result.exitCode)."
    }
}
