import AppKit
import SwiftUI

struct GitHubConnectView: View {
    private var connection: GitHubConnection { .shared }
    @State private var showsToken = false
    @State private var token = ""
    @State private var showsBot = false
    @State private var botInstallationID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch connection.phase {
            case .awaitingBrowser(let code):
                Text("Enter this code on GitHub")
                Text(verbatim: code.userCode)
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                HStack {
                    Button("Copy code") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code.userCode, forType: .string)
                    }
                    .buttonStyle(.glass)
                    Button("Open GitHub") { NSWorkspace.shared.open(code.verificationURI) }
                        .buttonStyle(.glass)
                }
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for GitHub…").foregroundStyle(Chrome.secondaryText)
                    Spacer()
                    Button("Cancel") { connection.cancelSignIn() }.buttonStyle(.glass)
                }
            case .connecting:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Connecting…")
                }
            default:
                if connection.canSignInWithBrowser {
                    Button("Sign in with GitHub") { connection.signInWithBrowser() }
                        .buttonStyle(.glassProminent)
                }
                if connection.cliIsSignedIn {
                    Button("Use GitHub CLI login") {
                        Task { await connection.useGitHubCLI() }
                    }
                    .buttonStyle(.glass)
                }
                Button("Use a token…") { showsToken.toggle() }.buttonStyle(.glass)
                if connection.botConnected {
                    HStack(spacing: 8) {
                        Text("Ensembyte[bot]")
                        Spacer()
                        Button("Disconnect") { connection.disconnectBot() }.buttonStyle(.glass)
                    }
                } else {
                    Button("Connect as Ensembyte[bot]…") {
                        showsBot = true
                        botInstallationID = String(connection.botInstallationID ?? "")
                        Task {
                            await connection.loadBotInstallations()
                            // Default to the first installation when none is chosen yet.
                            if connection.botInstallationID == nil,
                               let first = connection.botInstallations.first {
                                connection.botInstallationID = first.id
                                botInstallationID = String(first.id)
                            }
                        }
                    }
                    .buttonStyle(.glass)
                }
                if showsBot {
                    HStack(spacing: 8) {
                        if connection.botInstallations.count > 1 {
                            Menu {
                                ForEach(connection.botInstallations) { installation in
                                    Button(installation.owner) {
                                        botInstallationID = String(installation.id)
                                        connection.botInstallationID = installation.id
                                    }
                                }
                            } label: {
                                Text(connection.botInstallations.first { $0.id == connection.botInstallationID }?.owner ?? "Installation…")
                                    .frame(minWidth: 120, alignment: .leading)
                            }
                        } else if connection.botInstallations.count == 0 {
                            TextField("Installation ID", text: $botInstallationID)
                                .textFieldStyle(.plain)
                                .padding(8)
                                .background(Chrome.overlay(0.06), in: RoundedRectangle(cornerRadius: 8))
                        }
                        Button("Connect") {
                            if let id = Int(botInstallationID) {
                                connection.botInstallationID = id
                            }
                            Task {
                                await connection.connectBot()
                                showsBot = false
                            }
                        }
                        .buttonStyle(.glass)
                        .disabled(connection.botInstallations.count == 1 ? false : botInstallationID.isEmpty)
                        Button("Cancel") { showsBot = false }.buttonStyle(.glass)
                    }
                    if connection.botInstallations.count == 1 {
                        Text("Installed as \(connection.botInstallations[0].owner)")
                            .font(.caption)
                            .foregroundStyle(Chrome.secondaryText)
                    }
                }
                if showsToken {
                    HStack(spacing: 8) {
                        SecureField("Personal access token", text: $token)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(Chrome.overlay(0.06), in: RoundedRectangle(cornerRadius: 8))
                        Button("Connect") {
                            let value = token
                            Task {
                                await connection.connect(token: value)
                                token = ""
                            }
                        }
                        .buttonStyle(.glass)
                        .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Button("Create a token on GitHub") {
                        if let url = URL(string: "https://github.com/settings/tokens/new?scopes=repo,read:org,workflow&description=Ensembyte") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Chrome.accent)
                }
            }
            if let error = connection.errorMessage {
                Text(verbatim: error).font(.caption).foregroundStyle(.red)
            }
        }
        .font(.system(.callout))
        .task { await connection.refreshCLIStatus() }
    }
}
