import SwiftUI

/// Connects the app to QuickBooks Online. Matt supplies his own Intuit
/// developer app's Client ID/Secret and the HTTPS redirect page he's hosting
/// (see the README for the full setup walkthrough) — nothing here talks to
/// any server but Intuit's and this device's Keychain.
struct QBOSettingsView: View {
    @Environment(QBOAuthService.self) private var auth
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                if auth.isConnected {
                    Label("Connected (\(auth.environment.label))", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Disconnect", role: .destructive) {
                        auth.disconnect()
                    }
                } else {
                    Label("Not connected", systemImage: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Environment", selection: environmentBinding) {
                    ForEach(QBOEnvironment.allCases) { Text($0.label).tag($0) }
                }
                TextField("Client ID", text: clientIDBinding)
                    .noAutocapitalization()
                    .autocorrectionDisabled()
                SecureField("Client Secret", text: clientSecretBinding)
                TextField("Redirect URL", text: redirectURLBinding)
                    .noAutocapitalization()
                    .autocorrectionDisabled()
                    .urlKeyboard()
            } footer: {
                Text("From your Intuit Developer app. The Redirect URL is the HTTPS page you host (e.g. on GitHub Pages) that forwards back into this app — see the README for setup steps.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section {
                Button {
                    Task { await connect() }
                } label: {
                    if isConnecting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(auth.isConnected ? "Reconnect to QuickBooks" : "Connect to QuickBooks")
                    }
                }
                .disabled(auth.clientID.isEmpty || auth.clientSecret.isEmpty || auth.redirectURLString.isEmpty || isConnecting)
            }
        }
        .navigationTitle("QuickBooks")
        .inlineNavigationTitle()
    }

    private var clientIDBinding: Binding<String> {
        Binding(get: { auth.clientID }, set: { auth.clientID = $0 })
    }
    private var clientSecretBinding: Binding<String> {
        Binding(get: { auth.clientSecret }, set: { auth.clientSecret = $0 })
    }
    private var redirectURLBinding: Binding<String> {
        Binding(get: { auth.redirectURLString }, set: { auth.redirectURLString = $0 })
    }
    private var environmentBinding: Binding<QBOEnvironment> {
        Binding(get: { auth.environment }, set: { auth.environment = $0 })
    }

    private func connect() async {
        errorMessage = nil
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await auth.connect()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
