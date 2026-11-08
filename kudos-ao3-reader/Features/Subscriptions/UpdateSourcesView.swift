import SwiftUI

/// Explains the ranked sources Kudos can use to learn what changed in a subscription.
struct UpdateSourcesView: View {
    var onScanAO3: (() -> Void)?
    var mailConnected = false
    var onConnectMail: ((String, String) async throws -> Void)?
    var onDisconnectMail: (() throws -> Void)?

    @State private var showingMailConnection = false
    @State private var showingDisconnectConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Group {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Where updates come from")
                            .font(.title2.bold())
                        Text(sourceSummary)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    UpdateSourceCard(
                        rank: 1,
                        title: "Mail",
                        systemImage: "envelope",
                        benefit: "Exact times, chapter numbers, and word counts.",
                        cost: "No AO3 requests.",
                        detail: "Kudos reads mail only to find AO3's notifications. "
                            + "Nothing is uploaded, and nothing leaves this device.",
                        actionTitle: mailConnected ? "Disconnect Mail" : "Connect Mail",
                        action: mailAction
                    )
                }

                Section {
                    UpdateSourceCard(
                        rank: 2,
                        title: "Scanning AO3",
                        systemImage: "magnifyingglass",
                        benefit: "Checks every follow directly against AO3.",
                        cost: "Slower; uses paged, paced AO3 requests.",
                        actionTitle: "Scan AO3",
                        action: onScanAO3
                    )
                }

                Section {
                    UpdateSourceCard(
                        rank: 3,
                        title: "Restore from a backup",
                        systemImage: "archivebox",
                        benefit: "A Kudos backup already holds what each follow looked like, "
                            + "so restoring one costs no requests at all.",
                        cost: "No AO3 requests.",
                        actionTitle: "Choose a Backup"
                    )
                }
            }
            .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
        .navigationTitle("Updates")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(iOS)
            .sheet(isPresented: $showingMailConnection) {
                if let onConnectMail {
                    MailConnectionView(onConnect: onConnectMail)
                }
            }
        #endif
            .confirmationDialog(
                "Disconnect mail?",
                isPresented: $showingDisconnectConfirmation,
                titleVisibility: .visible
            ) {
                Button("Disconnect Mail", role: .destructive) {
                    do {
                        try onDisconnectMail?()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            } message: {
                Text("This removes the saved address, app password, and Waiting updates from this device.")
            }
            .alert("Mail connection error", isPresented: errorPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Something went wrong.")
            }
    }

    private var sourceSummary: String {
        let mailStatus = mailConnected ? "Mail is connected. " : "Mail is not connected yet. "
        return "AO3's own subscriptions page lists what you follow, "
            + "but never says what changed or when. These are the sources Kudos can use. "
            + mailStatus
            + "AO3 scanning isn't available yet."
    }

    private var mailAction: (() -> Void)? {
        if mailConnected, onDisconnectMail != nil {
            return { showingDisconnectConfirmation = true }
        }
        if !mailConnected, onConnectMail != nil {
            return { showingMailConnection = true }
        }
        return nil
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

private struct UpdateSourceCard: View {
    let rank: Int
    let title: String
    let systemImage: String
    let benefit: String
    let cost: String
    var detail: String?
    let actionTitle: String
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(rank)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(rank). \(title)")

            Text(benefit)
                .fixedSize(horizontal: false, vertical: true)

            Text("Cost: \(cost)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // shortcut: backup setup stays disabled here, enable it when its driver lands
            Button(actionTitle) { action?() }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(action == nil)
        }
        .padding(.vertical, 4)
    }
}

#if os(iOS)
struct MailConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    let onConnect: (String, String) async throws -> Void

    @State private var address = ""
    @State private var appPassword = ""
    @State private var errorMessage: String?
    @State private var isConnecting = false
    @State private var connectTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        TextField("Email address", text: $address)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("App password", text: $appPassword)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Gmail")
                    } footer: {
                        Text("Use an app password created in your Google Account, not your usual password.")
                    }

                    Section {
                        Text("Other providers cannot be verified yet.")
                            .foregroundStyle(.secondary)
                    } footer: {
                        Text("Kudos connects read-only to imap.gmail.com and verifies Gmail's mail signature.")
                    }
                }
                .appThemedRows()
            }
            .formStyle(.grouped)
            .appThemedScroll()
            .navigationTitle("Connect Mail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") { connect() }
                        .disabled(address.isEmpty || appPassword.isEmpty || isConnecting)
                }
            }
            .overlay {
                if isConnecting {
                    ProgressView("Checking Gmail…")
                        .padding()
                        .glassEffect(.regular, in: .capsule)
                }
            }
            .interactiveDismissDisabled(isConnecting)
            .alert("Couldn't connect", isPresented: errorPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Something went wrong.")
            }
            .onDisappear {
                connectTask?.cancel()
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func connect() {
        connectTask?.cancel()
        isConnecting = true
        errorMessage = nil
        connectTask = Task { @MainActor in
            do {
                try await onConnect(address, appPassword)
                appPassword = ""
                dismiss()
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
                isConnecting = false
            }
        }
    }
}
#endif
