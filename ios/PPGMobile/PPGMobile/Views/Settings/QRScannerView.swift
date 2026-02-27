import SwiftUI
import AVFoundation

/// QR code scanner for pairing with ppg serve.
/// Scans for ppg://connect URLs and creates a ServerConnection.
struct QRScannerView: View {
    let onScan: (ServerConnection) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var scannedCode: String?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var permissionDenied = false

    var body: some View {
        NavigationStack {
            ZStack {
                if permissionDenied {
                    cameraPermissionView
                } else {
                    QRCameraView(onCodeScanned: handleScan)
                        .ignoresSafeArea()

                    scanOverlay
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Invalid QR Code", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .task {
                await checkCameraPermission()
            }
        }
    }

    private var scanOverlay: some View {
        VStack {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)

                Text("Point camera at the QR code shown by `ppg serve`")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding()
        }
    }

    private var cameraPermissionView: some View {
        ContentUnavailableView {
            Label("Camera Access Required", systemImage: "camera.fill")
        } description: {
            Text("PPG Mobile needs camera access to scan QR codes for server pairing.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func checkCameraPermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionDenied = false
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permissionDenied = !granted
        case .denied, .restricted:
            permissionDenied = true
        @unknown default:
            permissionDenied = true
        }
    }

    private func handleScan(_ code: String) {
        guard scannedCode == nil else { return }
        scannedCode = code

        if let connection = ServerConnection.fromQRCode(code) {
            onScan(connection)
        } else {
            errorMessage = "This QR code doesn't contain a valid ppg server connection.\n\nExpected format: ppg://connect?host=...&port=...&token=..."
            showError = true
            scannedCode = nil
        }
    }
}

// MARK: - Camera UIViewRepresentable

/// UIViewRepresentable wrapper for AVCaptureSession QR code scanning.
/// Manages session lifecycle on appear/disappear and handles preview bounds correctly.
struct QRCameraView: UIViewRepresentable {
    let onCodeScanned: (String) -> Void

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        let coordinator = context.coordinator

        let session = AVCaptureSession()
        coordinator.session = session

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return view }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(coordinator, queue: .main)
            output.metadataObjectTypes = [.qr]
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer = previewLayer
        view.layer.addSublayer(previewLayer)

        coordinator.startSession()

        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.previewLayer?.frame = uiView.bounds
    }

    static func dismantleUIView(_ uiView: CameraPreviewView, coordinator: Coordinator) {
        coordinator.stopSession()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned)
    }

    // MARK: - Preview UIView

    /// Custom UIView that keeps the preview layer sized to its bounds.
    class CameraPreviewView: UIView {
        var previewLayer: AVCaptureVideoPreviewLayer?

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onCodeScanned: (String) -> Void
        var session: AVCaptureSession?
        private var hasScanned = false

        init(onCodeScanned: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
        }

        func startSession() {
            guard let session, !session.isRunning else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }

        func stopSession() {
            guard let session, session.isRunning else { return }
            session.stopRunning()
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !hasScanned,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let value = object.stringValue
            else { return }

            hasScanned = true
            session?.stopRunning()
            onCodeScanned(value)
        }
    }
}
