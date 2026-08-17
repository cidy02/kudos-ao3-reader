import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
#if os(iOS)
import Vision
import VisionKit
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Wire format for the QR / Copy Key / manual-paste pairing text: the
/// device's full 64-hex Ed25519 public key, prefixed so a scanner can
/// recognize a Kudos pairing code among other QR content. Matches Android's
/// `PairingKeyCodec` exactly — a code generated on one platform must decode
/// on the other.
enum PairingKeyCodec {
    private static let prefix = "kudos-pub-v1:"

    static func encode(_ publicKeyHex: String) -> String { prefix + publicKeyHex }

    /// Accepts the prefixed form (QR / Copy Key output) or bare 64-hex (a
    /// typed-fingerprint fallback). Returns `nil` for anything that doesn't
    /// normalize to a valid key — callers must not trust a partial match.
    static func decode(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = trimmed.lowercased().hasPrefix(prefix) ? String(trimmed.dropFirst(prefix.count)) : trimmed
        return TombstoneTrustStore.normalizedPublicKey(hex)
    }
}

/// Pure gating logic for the "Advanced" manual-paste trust flow, kept
/// outside the view so it's unit-testable without a SwiftUI harness. The
/// Trust button must stay disabled until the user has both pasted a
/// recognizable key AND explicitly confirmed they got it from their other
/// device — a file/wire source must never satisfy this on its own.
enum PairingTrustGate {
    static func canTrust(pastedText: String, confirmedFromOwnDevice: Bool) -> Bool {
        confirmedFromOwnDevice && PairingKeyCodec.decode(pastedText) != nil
    }
}

enum QRCodeGenerator {
    static func image(for text: String) -> Image? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        #if canImport(UIKit)
        return Image(uiImage: UIImage(cgImage: cgImage))
        #else
        let size = NSSize(width: scaled.extent.width, height: scaled.extent.height)
        return Image(nsImage: NSImage(cgImage: cgImage, size: size))
        #endif
    }
}

struct TombstoneTrustSettingsSection: View {
    @Environment(ThemeManager.self) private var themeManager
    @State private var showPairingSheet = false
    @State private var unknownSignerCount = 0
    @State private var trustedDevices: [TrustedDevice] = []
    @State private var revokeTarget: TrustedDevice?
    @State private var statusMessage: String?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("This device")
                Text(TombstoneSigning.publicKeyHex())
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            if unknownSignerCount > 0 {
                Button {
                    // Marks the prompt as acted on — see `UnknownSignerTracker`.
                    UnknownSignerTracker.reset()
                    unknownSignerCount = 0
                    showPairingSheet = true
                } label: {
                    Label(
                        unknownSignerCount == 1
                            ? "1 deletion skipped from an unpaired device"
                            : "\(unknownSignerCount) deletions skipped from an unpaired device",
                        systemImage: "exclamationmark.triangle"
                    )
                }
            }

            if trustedDevices.isEmpty {
                Text("No other devices paired yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(trustedDevices) { device in
                    TrustedDeviceRow(
                        device: device,
                        onRename: { newLabel in
                            TombstoneTrustStore.rename(device.publicKeyHex, label: newLabel)
                            refresh()
                        },
                        onUndo: {
                            if TombstoneTrustStore.undoTrust(device.publicKeyHex) {
                                refresh()
                                statusMessage = "Undid trust for that device."
                            }
                        },
                        onRevoke: { revokeTarget = device }
                    )
                }
            }

            Button("Pair a Device") { showPairingSheet = true }

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Deletion signing")
        } footer: {
            Text("Deletes are signed on this device. Other devices signed into the same Apple "
                + "ID pick up this device's key automatically. To trust a device on a different "
                + "account, pair it — scan its QR code or share its key. A backup file can "
                + "never add a trusted device.")
        }
        .onAppear {
            TombstoneTrustStore.add(TombstoneSigning.publicKeyHex())
            unknownSignerCount = UnknownSignerTracker.count()
            refresh()
        }
        .sheet(isPresented: $showPairingSheet, onDismiss: refresh) {
            PairingSheet()
                .environment(themeManager)
                .tint(themeManager.effectiveTint)
        }
        .sheet(item: $revokeTarget) { device in
            RevokeDeviceSheet(device: device) { reason in
                TombstoneTrustStore.remove(device.publicKeyHex, reason: reason)
                refresh()
                statusMessage = "Revoked that device."
            }
            .environment(themeManager)
            .tint(themeManager.effectiveTint)
        }
    }

    private func refresh() {
        trustedDevices = TombstoneTrustStore.trustedDevices()
    }
}

private struct TrustedDeviceRow: View {
    let device: TrustedDevice
    let onRename: (String) -> Void
    let onUndo: () -> Void
    let onRevoke: () -> Void

    @State private var isRenaming = false
    @State private var nameDraft = ""

    private var withinUndoWindow: Bool {
        Date().timeIntervalSince(device.trustedAt) <= TombstoneTrustStore.undoTrustWindow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.label.isEmpty ? "Unnamed device" : device.label)
                    Text(String(device.publicKeyHex.prefix(8)) + "…")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Rename") {
                    nameDraft = device.label
                    isRenaming = true
                }
                .font(.footnote)
                .buttonStyle(.borderless)
                if withinUndoWindow {
                    Button("Undo Trust", action: onUndo)
                        .font(.footnote)
                        .buttonStyle(.borderless)
                } else {
                    Button("Revoke", role: .destructive, action: onRevoke)
                        .font(.footnote)
                        .buttonStyle(.borderless)
                }
            }
            if isRenaming {
                HStack {
                    TextField("Name this device", text: $nameDraft)
                    Button("Save") {
                        onRename(nameDraft)
                        isRenaming = false
                    }
                }
            }
        }
    }
}

private struct RevokeDeviceSheet: View {
    let device: TrustedDevice
    let onConfirm: (TombstoneRevokeReason) -> Void
    @Environment(\.dismiss) private var dismiss
    // Stolen/compromised is the default-selected, safe-lazy option.
    @State private var reason: TombstoneRevokeReason = .stolenOrCompromised

    var body: some View {
        NavigationStack {
            Form {
                Section("Why are you removing this device?") {
                    Picker("Reason", selection: $reason) {
                        Text("Stolen or compromised").tag(TombstoneRevokeReason.stolenOrCompromised)
                        Text("Retired or sold").tag(TombstoneRevokeReason.retiredOrSold)
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle("Revoke \(device.label.isEmpty ? "This Device" : device.label)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Revoke", role: .destructive) {
                        onConfirm(reason)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct PairingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var deviceHex = TombstoneSigning.publicKeyHex()
    @State private var showQR = false
    #if os(iOS)
    @State private var showScanner = false
    #endif
    @State private var showAdvanced = false
    @State private var pasteText = ""
    @State private var confirmedFromOwnDevice = false
    @State private var trustLabel = ""
    @State private var justTrustedHex: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let justTrustedHex {
                    trustedNameStep(justTrustedHex)
                } else {
                    pairingForm
                }
            }
            .navigationTitle("Pair a Device")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showScanner) {
            QRScannerSheet { scanned in
                showScanner = false
                handle(scanned)
            }
        }
        #endif
    }

    private var pairingForm: some View {
        Form {
            Section {
                Text("Scan another device's code, or share yours, to trust its deletions.")
                    .foregroundStyle(.secondary)
            }

            Section {
                #if os(iOS)
                Button {
                    showScanner = true
                } label: {
                    Label("Scan a QR Code", systemImage: "qrcode.viewfinder")
                }
                #endif

                Button {
                    showQR.toggle()
                } label: {
                    Label(showQR ? "Hide My QR Code" : "Show My QR Code", systemImage: "qrcode")
                }

                if showQR, let image = QRCodeGenerator.image(for: PairingKeyCodec.encode(deviceHex)) {
                    HStack {
                        Spacer()
                        image
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 220, maxHeight: 220)
                            .padding(.vertical, 4)
                        Spacer()
                    }
                }

                Button {
                    copyKey()
                } label: {
                    Label("Copy My Key", systemImage: "doc.on.doc")
                }
            }

            Section {
                DisclosureGroup("Advanced: paste a key manually", isExpanded: $showAdvanced) {
                    TextField("Other device's key", text: $pasteText)
                        .font(.system(.caption, design: .monospaced))
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    Toggle("I got this key from my other device", isOn: $confirmedFromOwnDevice)
                    Button("Trust") {
                        trustPasted()
                    }
                    .disabled(!PairingTrustGate.canTrust(
                        pastedText: pasteText,
                        confirmedFromOwnDevice: confirmedFromOwnDevice
                    ))
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func trustedNameStep(_ hex: String) -> some View {
        Form {
            Section {
                Text("Trusted. Name this device so you recognize it later.")
                    .foregroundStyle(.secondary)
            }
            Section {
                TextField("e.g. Sam's iPhone", text: $trustLabel)
                Button("Done") {
                    if !trustLabel.isEmpty {
                        TombstoneTrustStore.rename(hex, label: trustLabel)
                    }
                    dismiss()
                }
            }
        }
    }

    private func copyKey() {
        let payload = PairingKeyCodec.encode(deviceHex)
        #if os(iOS)
        UIPasteboard.general.string = payload
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        #endif
    }

    private func handle(_ scannedText: String) {
        guard let hex = PairingKeyCodec.decode(scannedText) else {
            errorMessage = "Not a recognizable Kudos device key."
            return
        }
        trust(hex)
    }

    private func trustPasted() {
        guard let hex = PairingKeyCodec.decode(pasteText) else {
            errorMessage = "Not a recognizable Kudos device key."
            return
        }
        trust(hex)
    }

    private func trust(_ hex: String) {
        if TombstoneTrustStore.add(hex) {
            justTrustedHex = hex
            errorMessage = nil
        } else {
            errorMessage = "That key can't be trusted (it may be revoked)."
        }
    }
}

#if os(iOS)
private struct QRScannerSheet: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    private let isAvailable = DataScannerViewController.isSupported && DataScannerViewController.isAvailable

    var body: some View {
        NavigationStack {
            Group {
                if isAvailable {
                    QRScannerView(onScan: onScan)
                } else {
                    ContentUnavailableView(
                        "Camera Unavailable",
                        systemImage: "camera.fill",
                        description: Text("Allow camera access in Settings, or paste the key manually instead.")
                    )
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: false
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        try? uiViewController.startScanning()
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    onScan(payload)
                    return
                }
            }
        }
    }
}
#endif
