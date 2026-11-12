import SwiftUI

struct GitHubSettingsSection: View {
    @Environment(AppModel.self) private var model
    private var connection: GitHubConnection { .shared }
    @State private var botKeyDraft = ""

    var body: some View {
        ChromeSection(title: "GitHub") {
            ChromeCard {
                if connection.isConnected {
                    HStack(spacing: 10) {
                        AsyncImage(url: connection.user?.avatarURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image("mcp-github").resizable().scaledToFit()
                        }
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: connection.user.map { $0.name ?? $0.login } ?? "GitHub")
                                .foregroundStyle(Chrome.primaryText)
                            if let detail = accountDetail {
                                Text(verbatim: detail).font(.subheadline).foregroundStyle(Chrome.secondaryText)
                            }
                        }
                        Spacer(minLength: 12)
                        Button("Disconnect") { connection.disconnect() }.buttonStyle(.glass)
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, Chrome.rowControlTrailingPadding)
                    .padding(.vertical, 11)
                    if connection.botConnected {
                        ChromeRowDivider()
                        HStack(spacing: 10) {
                            Image("mcp-github").resizable().scaledToFit()
                                .frame(width: 28, height: 28)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ensembyte[bot]")
                                    .foregroundStyle(Chrome.primaryText)
                                Text("Pushes and pull requests act as the app")
                                    .font(.subheadline).foregroundStyle(Chrome.secondaryText)
                            }
                            Spacer(minLength: 12)
                            Button("Disconnect") { connection.disconnectBot() }.buttonStyle(.glass)
                        }
                        .padding(.leading, 16)
                        .padding(.trailing, Chrome.rowControlTrailingPadding)
                        .padding(.vertical, 11)
                    }
                    ChromeRowDivider()
                    ChromeRow(title: "Clone a repository", detail: "Clone one of your repositories and start a thread in it.") {
                        Button("Clone…") { GitHubClonePanel.shared.present(model: model) }.buttonStyle(.glass)
                    }
                    ChromeRowDivider()
                    ChromeRow(title: "Clone into", detail: (connection.cloneDirectory.path as NSString).abbreviatingWithTildeInPath) {
                        Button("Change…") { GitHubClonePanel.chooseCloneDirectory() }.buttonStyle(.glass)
                    }
                    ChromeRowDivider()
                    ChromeRow(
                        title: "App private key",
                        detail: "The RSA private key from your GitHub App settings; Ensembyte[bot] signs with it. Stored in your Keychain."
                    ) {
                        HStack(spacing: 8) {
                            SecureField("-----BEGIN RSA PRIVATE KEY-----", text: $botKeyDraft)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(1...4)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 280)
                            Button(botKeyDraft.isEmpty ? "Remove" : "Save") {
                                GitHubAppAuth.setKeychainKey(botKeyDraft)
                            }
                            .buttonStyle(.glass)
                        }
                        .onAppear {
                            if botKeyDraft.isEmpty { botKeyDraft = GitHubAppAuth.storedKey() ?? "" }
                        }
                    }
                } else if case .checking = connection.phase {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking GitHub connection…").foregroundStyle(Chrome.secondaryText)
                    }
                    .padding(16)
                } else {
                    ChromeRow(title: "Connect GitHub", detail: "Clone your repositories and let agents push and open pull requests.") {
                        EmptyView()
                    }
                    GitHubConnectView().padding(.horizontal, 16).padding(.bottom, 11)
                }
            }
        }
    }

    private var accountDetail: String? {
        guard let user = connection.user else { return nil }
        switch connection.source {
        case .githubCLI: return "@\(user.login), using the GitHub CLI login"
        case .ensembyte: return "@\(user.login), saved in your Keychain"
        case .bot: return "acting as the Ensembyte app"
        case nil: return "@\(user.login)"
        }
    }
}
