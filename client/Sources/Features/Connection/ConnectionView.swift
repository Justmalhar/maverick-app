// client/Sources/Features/Connection/ConnectionView.swift
import SwiftUI

struct ConnectionView: View {
    @Environment(ConnectionManager.self) var connection
    @State private var host = UserDefaults.standard.string(forKey: "lastHost") ?? ""
    @State private var port = UserDefaults.standard.integer(forKey: "lastPort") == 0
        ? "8765"
        : String(UserDefaults.standard.integer(forKey: "lastPort"))
    @State private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac Address (Tailscale)") {
                    TextField("hostname or IP", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                }
                Section("Auth (optional)") {
                    SecureField("Token", text: $token)
                }
                Section {
                    Button("Connect") {
                        connection.connect(
                            host: host,
                            port: Int(port) ?? 8765,
                            token: token
                        )
                    }
                    .disabled(host.isEmpty || connection.state == .connecting)
                    if connection.state == .connecting {
                        HStack { Spacer(); ProgressView("Connecting…"); Spacer() }
                    }
                    if let err = connection.lastError {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Maverick")
        }
    }
}
