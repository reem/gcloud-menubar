import AppKit
import SwiftUI

struct GCloudMenuView: View {
    @ObservedObject var store: GCloudStatusStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

            statusRows

            if store.isRefreshingStatus || store.authOperation != .none {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(activityTitle)
                        .font(.callout)

                    Spacer()

                    if store.authOperation.isLoginFlow {
                        Button("Cancel") {
                            store.cancelAuthOperation()
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            if let output = store.lastCommandOutput, !output.isEmpty {
                Text(output)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            actionButtons
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: store.status.isAuthenticated ? "cloud.fill" : "cloud")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(store.status.isAuthenticated ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Google Cloud")
                    .font(.headline)
                Text(store.status.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                Task {
                    await store.refresh()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(!store.canRefreshStatus)
            .help("Refresh")
        }
    }

    private var statusRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusRow(
                title: "Account",
                value: store.status.activeAccount ?? "Not signed in",
                systemImage: store.status.isAuthenticated ? "person.crop.circle.fill" : "person.crop.circle"
            )

            StatusRow(
                title: "Project",
                value: store.status.activeProject ?? "No active project",
                systemImage: "folder"
            )

            StatusRow(
                title: "Access Token",
                value: accessTokenExpiryText,
                systemImage: "timer"
            )

            StatusRow(
                title: "Application Default",
                value: store.status.applicationDefaultCredentials.detail,
                systemImage: "key"
            )

            if let gcloudPath = store.status.gcloudPath {
                StatusRow(title: "gcloud", value: gcloudPath, systemImage: "terminal")
            } else {
                StatusRow(title: "gcloud", value: "Resolving with PATH", systemImage: "terminal")
            }

            if let checkedAt = store.status.lastChecked {
                StatusRow(
                    title: "Checked",
                    value: checkedAt.formatted(date: .omitted, time: .standard),
                    systemImage: "clock"
                )
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    await store.runUserLogin()
                }
            } label: {
                Label("gcloud auth login", systemImage: "person.badge.key")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!store.canStartAuthCommand)

            Button {
                Task {
                    await store.runApplicationDefaultLogin()
                }
            } label: {
                Label("ADC login", systemImage: "key.horizontal")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!store.canStartAuthCommand)

            HStack(spacing: 8) {
                Button {
                    Task {
                        await store.refreshUserAccessToken()
                    }
                } label: {
                    Label("Refresh user token", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!store.canStartAuthCommand || !store.status.isAuthenticated)

                Button {
                    Task {
                        await store.refreshApplicationDefaultAccessToken()
                    }
                } label: {
                    Label("Refresh ADC token", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!store.canStartAuthCommand)
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
    }

    private var activityTitle: String {
        if store.authOperation != .none {
            return store.authOperation.title
        }

        return "Refreshing..."
    }

    private var accessTokenExpiryText: String {
        guard let expiry = store.status.accessTokenExpiry else {
            return store.status.isAuthenticated ? "No cached token expiry" : "Not signed in"
        }

        let absolute = expiry.formatted(date: .omitted, time: .shortened)
        let relative = expiry.formatted(.relative(presentation: .numeric))
        return "\(absolute) (\(relative))"
    }
}

private struct StatusRow: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
    }
}
