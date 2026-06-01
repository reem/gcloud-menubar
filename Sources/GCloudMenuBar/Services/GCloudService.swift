import Foundation

struct CommandResult {
    var exitCode: Int32
    var standardOutput: String
    var standardError: String

    var combinedOutput: String {
        [standardOutput, standardError]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum GCloudServiceError: LocalizedError {
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case let .processFailed(message):
            return message
        }
    }
}

final class GCloudService {
    private let fileManager: FileManager
    private let authProcessLock = NSLock()
    private var activeAuthProcess: Process?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func fetchStatus() async -> GCloudStatus {
        let executable = resolveGCloudExecutable()

        do {
            let accountResult = try await runGCloud(arguments: [
                "auth",
                "list",
                "--filter=status:ACTIVE",
                "--format=value(account)",
                "--quiet"
            ])

            guard accountResult.exitCode == 0 else {
                return GCloudStatus(
                    gcloudPath: executable.displayPath,
                    activeAccount: nil,
                    activeProject: nil,
                    accessTokenExpiry: nil,
                    applicationDefaultCredentials: readADCStatus(),
                    lastChecked: Date(),
                    detail: readableFailure(from: accountResult, fallback: "Could not read auth status")
                )
            }

            let account = firstMeaningfulLine(in: accountResult.standardOutput)
            let project = await readActiveProject()
            let expiry = await readAccessTokenExpiry(for: account)

            return GCloudStatus(
                gcloudPath: executable.displayPath,
                activeAccount: account,
                activeProject: project,
                accessTokenExpiry: expiry,
                applicationDefaultCredentials: readADCStatus(),
                lastChecked: Date(),
                detail: account == nil ? "No active gcloud account" : "gcloud is authenticated"
            )
        } catch {
            return GCloudStatus(
                gcloudPath: executable.displayPath,
                activeAccount: nil,
                activeProject: nil,
                accessTokenExpiry: nil,
                applicationDefaultCredentials: readADCStatus(),
                lastChecked: Date(),
                detail: error.localizedDescription
            )
        }
    }

    func runUserLogin() async throws -> CommandResult {
        try await runGCloud(arguments: ["auth", "login", "--quiet"], tracksAuthProcess: true)
    }

    func runApplicationDefaultLogin() async throws -> CommandResult {
        try await runGCloud(
            arguments: ["auth", "application-default", "login", "--quiet"],
            tracksAuthProcess: true
        )
    }

    func refreshUserAccessToken() async throws -> CommandResult {
        try await runGCloud(arguments: ["auth", "print-access-token", "--quiet"])
    }

    func refreshApplicationDefaultAccessToken() async throws -> CommandResult {
        try await runGCloud(arguments: ["auth", "application-default", "print-access-token", "--quiet"])
    }

    func cancelActiveAuthCommand() {
        authProcessLock.lock()
        let process = activeAuthProcess
        authProcessLock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
    }

    private func readActiveProject() async -> String? {
        do {
            let result = try await runGCloud(arguments: [
                "config",
                "get-value",
                "project",
                "--quiet"
            ])

            guard result.exitCode == 0 else {
                return nil
            }

            let value = firstMeaningfulLine(in: result.standardOutput)
            return value == "(unset)" ? nil : value
        } catch {
            return nil
        }
    }

    private func readAccessTokenExpiry(for account: String?) async -> Date? {
        guard let account, !account.isEmpty else {
            return nil
        }

        let databaseURL = gcloudConfigDirectory().appendingPathComponent("access_tokens.db")
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return nil
        }

        let escapedAccount = account.replacingOccurrences(of: "'", with: "''")
        let sql = "select token_expiry from access_tokens where account_id = '\(escapedAccount)' limit 1;"

        do {
            let result = try await runExecutable(
                launchPath: "/usr/bin/sqlite3",
                arguments: [databaseURL.path, sql],
                environment: nil
            )

            guard result.exitCode == 0, let expiryText = firstMeaningfulLine(in: result.standardOutput) else {
                return nil
            }

            return parseGCloudTimestamp(expiryText)
        } catch {
            return nil
        }
    }

    private func runGCloud(
        arguments: [String],
        tracksAuthProcess: Bool = false
    ) async throws -> CommandResult {
        let executable = resolveGCloudExecutable()
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = shellSearchPath()

        return try await runExecutable(
            launchPath: executable.launchPath,
            arguments: executable.argumentsPrefix + arguments,
            environment: environment,
            tracksAuthProcess: tracksAuthProcess
        )
    }

    private func runExecutable(
        launchPath: String,
        arguments: [String],
        environment: [String: String]?,
        tracksAuthProcess: Bool = false
    ) async throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { terminatedProcess in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""

                continuation.resume(returning: CommandResult(
                    exitCode: terminatedProcess.terminationStatus,
                    standardOutput: output,
                    standardError: error
                ))

                if tracksAuthProcess {
                    self.clearActiveAuthProcess(terminatedProcess)
                }
            }

            do {
                if tracksAuthProcess {
                    self.setActiveAuthProcess(process)
                }
                try process.run()
            } catch {
                if tracksAuthProcess {
                    self.clearActiveAuthProcess(process)
                }
                continuation.resume(throwing: GCloudServiceError.processFailed(error.localizedDescription))
            }
        }
    }

    private func readADCStatus() -> ADCStatus {
        let credentialsURL = gcloudConfigDirectory()
            .appendingPathComponent("application_default_credentials.json")

        guard fileManager.fileExists(atPath: credentialsURL.path) else {
            return .missing
        }

        do {
            let data = try Data(contentsOf: credentialsURL)
            guard
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return .unreadable("Credentials file is not JSON")
            }

            let label = object["client_email"] as? String
                ?? object["client_id"] as? String
                ?? "Application default credentials"
            let quotaProject = object["quota_project_id"] as? String
            return .configured(label: label, quotaProject: quotaProject)
        } catch {
            return .unreadable(error.localizedDescription)
        }
    }

    private func gcloudConfigDirectory() -> URL {
        if let configPath = ProcessInfo.processInfo.environment["CLOUDSDK_CONFIG"], !configPath.isEmpty {
            return URL(fileURLWithPath: configPath, isDirectory: true)
        }

        return homeDirectory()
            .appendingPathComponent(".config")
            .appendingPathComponent("gcloud")
    }

    private func resolveGCloudExecutable() -> GCloudExecutable {
        for path in candidateGCloudPaths() where fileManager.isExecutableFile(atPath: path) {
            return GCloudExecutable(launchPath: path, argumentsPrefix: [], displayPath: path)
        }

        return GCloudExecutable(
            launchPath: "/usr/bin/env",
            argumentsPrefix: ["gcloud"],
            displayPath: nil
        )
    }

    private func candidateGCloudPaths() -> [String] {
        [
            "/opt/homebrew/bin/gcloud",
            "/usr/local/bin/gcloud",
            homeDirectory().appendingPathComponent("google-cloud-sdk/bin/gcloud").path
        ]
    }

    private func shellSearchPath() -> String {
        let home = homeDirectory().path
        return [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "\(home)/google-cloud-sdk/bin"
        ].joined(separator: ":")
    }

    private func homeDirectory() -> URL {
        fileManager.homeDirectoryForCurrentUser
    }

    private func firstMeaningfulLine(in text: String) -> String? {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func readableFailure(from result: CommandResult, fallback: String) -> String {
        let output = result.combinedOutput
        return output.isEmpty ? fallback : output
    }

    private func parseGCloudTimestamp(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized: String

        if let dotIndex = trimmed.firstIndex(of: ".") {
            let prefix = trimmed[..<dotIndex]
            let fractionStart = trimmed.index(after: dotIndex)
            let fraction = trimmed[fractionStart...].prefix(3).padding(
                toLength: 3,
                withPad: "0",
                startingAt: 0
            )
            normalized = "\(prefix).\(fraction)"
        } else {
            normalized = "\(trimmed).000"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.date(from: normalized)
    }

    private func setActiveAuthProcess(_ process: Process) {
        authProcessLock.lock()
        activeAuthProcess = process
        authProcessLock.unlock()
    }

    private func clearActiveAuthProcess(_ process: Process) {
        authProcessLock.lock()
        if activeAuthProcess === process {
            activeAuthProcess = nil
        }
        authProcessLock.unlock()
    }
}

private struct GCloudExecutable {
    var launchPath: String
    var argumentsPrefix: [String]
    var displayPath: String?
}
