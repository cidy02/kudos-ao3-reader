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

/// Copy helpers for the Devices section (`Settings-Backup-Sync`).
enum TrustedDeviceCopy {
    static let thisDeviceDetail = "Signs deletions with its own key"
    static let emptyState = "No other devices paired yet."
    static let addDevice = "Add a Device…"

    static func showCodeTitle(deviceName: String) -> String {
        "Show a Code on This \(deviceName)"
    }

    static func thisDeviceTitle(deviceName: String) -> String {
        "This \(deviceName)"
    }

    static func thisDeviceStatus(lastSyncAt: Date?, now: Date = Date()) -> String {
        guard let lastSyncAt else { return thisDeviceDetail }
        return "\(thisDeviceDetail) · synced \(SyncFolderDisplayCopy.relativeSyncAge(from: lastSyncAt, to: now))"
    }

    static func thisDeviceSymbol(deviceName: String) -> String {
        switch deviceName {
        case "Mac": "desktopcomputer"
        case "iPad": "ipad"
        default: "iphone"
        }
    }

    static func trustedSince(_ date: Date) -> String {
        "Trusted since \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

struct TombstoneTrustSettingsSection: View {
    let lastSyncAt: Date?

    @Environment(ThemeManager.self) private var themeManager
    @State private var showPairingSheet = false
    @State private var unknownSignerCount = 0
    @State private var trustedDevices: [TrustedDevice] = []
    @State private var revokeTarget: TrustedDevice?
    @State private var statusMessage: String?

    private var thisDeviceRow: some View {
        let deviceName = ThisDevice.name
        let detail = TrustedDeviceCopy.thisDeviceStatus(lastSyncAt: lastSyncAt)
        return HStack(spacing: 10) {
            SystemSyncDeviceIcon(symbol: TrustedDeviceCopy.thisDeviceSymbol(deviceName: deviceName))
            VStack(alignment: .leading, spacing: 2) {
                Text(TrustedDeviceCopy.thisDeviceTitle(deviceName: deviceName))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(TrustedDeviceCopy.thisDeviceTitle(deviceName: deviceName))
        .accessibilityValue(detail)
        .accessibilityAction(named: "Copy Key") {
            copyDeviceKey()
        }
        .contextMenu {
            Button("Copy Key") {
                copyDeviceKey()
            }
        }
    }

    var body: some View {
        Section {
            thisDeviceRow

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
                Text(TrustedDeviceCopy.emptyState)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
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

            Button {
                showPairingSheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.body)
                        .foregroundStyle(.accentInk)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    Text(TrustedDeviceCopy.addDevice)
                        .foregroundStyle(.accentInk)
                }
            }
            .accessibilityLabel(TrustedDeviceCopy.addDevice)

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
            }
        } header: {
            Text("Devices")
        } footer: {
            Text("Kudos checks that deletions came from one of your devices. Devices using the "
                + "same Apple account are trusted automatically; for a different account, scan "
                + "its QR code or share its pairing code. A backup file can never mark a device "
                + "as trusted.")
        }
        .onAppear {
            TombstoneTrustStore.add(TombstoneSigning.publicKeyHex())
            unknownSignerCount = UnknownSignerTracker.count()
            refresh()
        }
        #if DEBUG
        .task {
            if DebugLaunchRoute.takeSheet("pairing") { showPairingSheet = true }
            if DebugLaunchRoute.takeSheet("revokedevice") {
                revokeTarget = DebugLaunchRoute.revokedDevice()
            }
        }
        #endif
        .sheet(isPresented: $showPairingSheet, onDismiss: refresh) {
            PairingSheet()
                .environment(themeManager)
                .accentTint(themeManager.effectiveTint, on: themeManager.appTheme)
        }
        .sheet(item: $revokeTarget) { device in
            RevokeDeviceSheet(device: device) { reason in
                TombstoneTrustStore.remove(device.publicKeyHex, reason: reason)
                refresh()
                statusMessage = "Revoked that device."
            }
            .environment(themeManager)
            .accentTint(themeManager.effectiveTint, on: themeManager.appTheme)
        }
    }

    private func refresh() {
        trustedDevices = TombstoneTrustStore.trustedDevices()
    }

    private func copyDeviceKey() {
        let payload = PairingKeyCodec.encode(TombstoneSigning.publicKeyHex())
        #if os(iOS)
        UIPasteboard.general.string = payload
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        #endif
    }
}

private struct SystemSyncDeviceIcon: View {
    let symbol: String
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        Image(systemName: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.accentInk)
            .frame(width: 26, height: 26)
            .background(themeManager.appTheme.nestedCardSurface, in: RoundedRectangle(cornerRadius: 6))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityHidden(true)
    }
}

private struct TrustedDeviceRow: View {
    let device: TrustedDevice
    let onRename: (String) -> Void
    let onUndo: () -> Void
    let onRevoke: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isRenaming = false
    @State private var nameDraft = ""

    private var withinUndoWindow: Bool {
        Date().timeIntervalSince(device.trustedAt) <= TombstoneTrustStore.undoTrustWindow
    }

    private var displayName: String {
        device.label.isEmpty ? "Unnamed device" : device.label
    }

    private var trustedDetail: String {
        TrustedDeviceCopy.trustedSince(device.trustedAt)
    }

    @ViewBuilder
    private var rowActions: some View {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: 12) {
                    SystemSyncDeviceIcon(symbol: "ipad.and.iphone")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(trustedDetail)
                            .font(.footnote)
                            .foregroundStyle(.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 16) {
                    rowActions
                }
            } else {
                HStack(spacing: 12) {
                    SystemSyncDeviceIcon(symbol: "ipad.and.iphone")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                        Text(trustedDetail)
                            .font(.footnote)
                            .foregroundStyle(.secondaryInk)
                    }
                    Spacer()
                    rowActions
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
        .padding(.vertical, 2)
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
                Text("Revoke \(device.label.isEmpty ? "This Device" : device.label)")
                    .font(.title2.bold())
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .appThemedRows()
                Section("Why are you removing this device?") {
                    // Hidden label: the section already asks, and an inline picker
                    // drew "Reason" as a row of its own inside the card.
                    Picker("Reason", selection: $reason) {
                        Text("Stolen or compromised").tag(TombstoneRevokeReason.stolenOrCompromised)
                        Text("Retired or sold").tag(TombstoneRevokeReason.retiredOrSold)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                .appThemedRows()
            }
            .appThemedScroll()
            .wrappingInlineTitle("Revoke Device", accessibilityHidden: true)
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
            .navigationTitle("Add a Device")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    #if os(iOS)
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                    #else
                    Button("Close") {
                        dismiss()
                    }
                    .accessibilityLabel("Close")
                    #endif
                }
            }
        }
        .presentationDragIndicator(.visible)
        #if os(iOS)
        .sheet(isPresented: $showScanner) {
            QRScannerSheet { scanned in
                showScanner = false
                handle(scanned)
            }
        }
        #endif
    }

    private var pairingExplanation: String {
        #if os(iOS)
        "Scan another device's code to trust its deletions here, or show your code "
            + "so it can trust deletions from this device."
        #else
        "Show your code so another device can trust deletions from this device."
        #endif
    }

    private var pairingForm: some View {
        Form {
            // Group so .appThemedRows() reaches every section (not from the Form itself).
            Group {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sync with another device")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            Text(pairingExplanation)
                                .font(.footnote)
                                .foregroundStyle(.secondaryInk)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.accentInk)
                            .accessibilityHidden(true)
                    }
                }

                Section {
                    Button {
                        showQR.toggle()
                    } label: {
                        Label(
                            showQR ? "Hide My QR Code" : TrustedDeviceCopy.showCodeTitle(deviceName: ThisDevice.name),
                            systemImage: "qrcode"
                        )
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
                                .accessibilityLabel("My QR code")
                            Spacer()
                        }
                    }

                    #if os(iOS)
                    Button {
                        showScanner = true
                    } label: {
                        Label("Scan the Other Device’s Code", systemImage: "qrcode.viewfinder")
                    }
                    #endif

                    Button {
                        copyKey()
                    } label: {
                        Label("Copy My Key", systemImage: "doc.on.doc")
                    }
                }

                Section {
                    DisclosureGroup("Type a Key Instead", isExpanded: $showAdvanced) {
                        TextField("Other device's key", text: $pasteText)
                            .font(.system(.caption, design: .monospaced))
                            #if canImport(UIKit)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                        Toggle(isOn: $confirmedFromOwnDevice) {
                            Text("I got this key from my own device")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accentFill()
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
            .appThemedRows()
        }
        .appThemedScroll()
    }

    private func trustedNameStep(_ hex: String) -> some View {
        Form {
            Group {
                Section {
                    Text("This device is now trusted. Give it a name you will recognize later.")
                        .foregroundStyle(.secondaryInk)
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
            .appThemedRows()
        }
        .appThemedScroll()
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
                        description: Text("Allow camera access for Kudos in Settings, or paste the code instead.")
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
