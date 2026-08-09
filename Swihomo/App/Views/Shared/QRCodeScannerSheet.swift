#if os(iOS)
import SwiftUI
import AVFoundation
import UIKit
import VisionKit

struct QRCodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scannerState: ScannerState = .preparing
    @State private var scannerRestartID = UUID()
    @State private var didAcceptPayload = false

    let onCodeScanned: (String) -> Bool

    private enum ScannerState: Equatable {
        case preparing
        case scanning
        case invalidPayload
        case cameraDenied
        case cameraRestricted
        case unavailable
        case failed
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if scannerState == .scanning {
                    ZStack(alignment: .bottom) {
                        QRCodeScannerView(
                            onCodeScanned: handlePayload,
                            onStartFailure: { scannerState = .failed }
                        )
                        .id(scannerRestartID)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .accessibilityLabel(Text("profiles.qr.cameraView"))

                        Label("profiles.qr.scanning", systemImage: "qrcode.viewfinder")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.58), in: Capsule())
                            .padding(16)
                    }
                    .frame(maxWidth: 620, minHeight: 320, maxHeight: 520)
                } else if scannerState == .preparing {
                    statusPanel(
                        icon: "camera.aperture",
                        title: "profiles.qr.preparing",
                        message: "profiles.qr.preparing.description",
                        tint: .indigo,
                        showsProgress: true
                    )
                } else {
                    statusPanel(
                        icon: statusIcon,
                        title: statusTitle,
                        message: statusMessage,
                        tint: statusTint
                    )

                    if scannerState == .cameraDenied {
                        Button {
                            openCameraSettings()
                        } label: {
                            Label("profiles.qr.openSettings", systemImage: "gear")
                        }
                        .liquidGlassButton()
                    } else if scannerState == .invalidPayload || scannerState == .failed {
                        Button {
                            restartScanner()
                        } label: {
                            Label("profiles.qr.tryAgain", systemImage: "arrow.clockwise")
                        }
                        .liquidGlassButton(prominent: true)
                    }
                }

                Text("profiles.qr.description")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 540)
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(Text("profiles.qr.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
            }
        }
        .task {
            await prepareScanner()
        }
    }

    private var statusIcon: String {
        switch scannerState {
        case .invalidPayload: "qrcode"
        case .cameraDenied, .cameraRestricted: "camera.fill"
        case .unavailable: "iphone.slash"
        case .failed: "exclamationmark.triangle.fill"
        case .preparing, .scanning: "qrcode.viewfinder"
        }
    }

    private var statusTitle: LocalizedStringKey {
        switch scannerState {
        case .invalidPayload: "profiles.qr.invalid.title"
        case .cameraDenied: "profiles.qr.cameraDenied"
        case .cameraRestricted: "profiles.qr.cameraRestricted"
        case .unavailable: "profiles.qr.unavailable"
        case .failed: "profiles.qr.failed"
        case .preparing, .scanning: "profiles.qr.title"
        }
    }

    private var statusMessage: LocalizedStringKey {
        switch scannerState {
        case .invalidPayload: "profiles.qr.invalid.description"
        case .cameraDenied, .cameraRestricted, .unavailable, .failed: "profiles.qr.help"
        case .preparing, .scanning: "profiles.qr.description"
        }
    }

    private var statusTint: Color {
        switch scannerState {
        case .invalidPayload: .orange
        case .cameraDenied, .cameraRestricted, .unavailable, .failed: .red
        case .preparing, .scanning: .indigo
        }
    }

    @ViewBuilder
    private func statusPanel(
        icon: String,
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        tint: Color,
        showsProgress: Bool = false
    ) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 82, height: 82)
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(spacing: 7) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(tint)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 34)
        .frame(maxWidth: 540, minHeight: 260)
        .frame(maxWidth: .infinity)
        .liquidGlassCard(cornerRadius: 28)
        .accessibilityElement(children: .combine)
    }

    private func handlePayload(_ payload: String) {
        guard !didAcceptPayload else { return }
        if onCodeScanned(payload) {
            didAcceptPayload = true
            dismiss()
        } else {
            scannerState = .invalidPayload
        }
    }

    private func restartScanner() {
        scannerRestartID = UUID()
        scannerState = .scanning
    }

    private func prepareScanner() async {
        guard DataScannerViewController.isSupported else {
            scannerState = .unavailable
            return
        }

        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch authorizationStatus {
        case .authorized:
            break
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
            guard granted else {
                scannerState = .cameraDenied
                return
            }
        case .denied:
            scannerState = .cameraDenied
            return
        case .restricted:
            scannerState = .cameraRestricted
            return
        @unknown default:
            scannerState = .cameraDenied
            return
        }

        guard DataScannerViewController.isAvailable else {
            scannerState = .unavailable
            return
        }

        scannerState = .scanning
    }

    private func openCameraSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }
}

private struct QRCodeScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void
    let onStartFailure: () -> Void

    func makeUIViewController(context: Context) -> QRCodeScannerHostViewController {
        QRCodeScannerHostViewController(
            onCodeScanned: onCodeScanned,
            onStartFailure: onStartFailure
        )
    }

    func updateUIViewController(_ uiViewController: QRCodeScannerHostViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: QRCodeScannerHostViewController, coordinator: ()) {
        uiViewController.stopScanning()
    }
}

private final class QRCodeScannerHostViewController: UIViewController, DataScannerViewControllerDelegate {
    private let scanner: DataScannerViewController
    private let onCodeScanned: (String) -> Void
    private let onStartFailure: () -> Void
    private var hasStarted = false
    private var didComplete = false
    private var didReportStartFailure = false

    init(onCodeScanned: @escaping (String) -> Void, onStartFailure: @escaping () -> Void) {
        self.onCodeScanned = onCodeScanned
        self.onStartFailure = onStartFailure
        scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        super.init(nibName: nil, bundle: nil)
        scanner.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addChild(scanner)
        scanner.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scanner.view)
        NSLayoutConstraint.activate([
            scanner.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scanner.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scanner.view.topAnchor.constraint(equalTo: view.topAnchor),
            scanner.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        scanner.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startScanning()
    }

    override func viewWillDisappear(_ animated: Bool) {
        stopScanning()
        super.viewWillDisappear(animated)
    }

    func startScanning() {
        guard !hasStarted, !didComplete, !didReportStartFailure else { return }
        do {
            try scanner.startScanning()
            hasStarted = true
        } catch {
            didReportStartFailure = true
            onStartFailure()
        }
    }

    func stopScanning() {
        guard hasStarted else { return }
        scanner.stopScanning()
        hasStarted = false
    }

    func dataScanner(
        _ dataScanner: DataScannerViewController,
        didAdd addedItems: [RecognizedItem],
        allItems: [RecognizedItem]
    ) {
        for item in addedItems {
            guard case let .barcode(barcode) = item,
                  let payload = barcode.payloadStringValue else { continue }
            complete(with: payload)
            return
        }
    }

    private func complete(with payload: String) {
        let trimmedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPayload.isEmpty, !didComplete else { return }
        didComplete = true
        stopScanning()
        onCodeScanned(trimmedPayload)
    }
}
#endif
