// client/Sources/Features/Pairing/QRScannerView.swift
import SwiftUI
import AVFoundation
import AudioToolbox

/// Camera authorization state surfaced to the pairing UI.
///
/// `notDetermined` means we haven't asked yet; `denied`/`restricted` mean the
/// user (or policy) blocked the camera and we must fall back to manual entry.
enum CameraPermission: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable  // no capture device (e.g. simulator)

    init(status: AVAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorized:    self = .authorized
        case .denied:        self = .denied
        case .restricted:    self = .restricted
        @unknown default:    self = .denied
        }
    }
}

/// SwiftUI wrapper around an `AVCaptureSession` + `AVCaptureMetadataOutput`
/// configured for `.qr` codes. Decoded strings are delivered (once, then the
/// session pauses to avoid duplicate callbacks) via `onScan`.
///
/// The SIMULATOR HAS NO CAMERA, so `PairingView` also offers a manual-entry
/// path that feeds the SAME `onScan` callback; this view is only mounted when
/// a capture device is available.
struct QRScannerView: UIViewControllerRepresentable {
    /// Called with the raw decoded QR string (e.g. `maverick://pair/v1?...`).
    let onScan: (String) -> Void
    /// Called if the camera could not be configured / permission denied.
    let onError: (CameraPermission) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onScan = onScan
        vc.onError = onError
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

/// UIKit controller owning the capture session lifecycle. Kept separate from the
/// SwiftUI struct so the session can be started/stopped on view lifecycle and
/// the metadata delegate has a stable object identity.
final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    var onError: ((CameraPermission) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let sessionQueue = DispatchQueue(label: "com.malhar.MaverickRemote.scanner")
    private var didDeliver = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestAccessAndConfigure()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startRunningIfReady()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    // MARK: - Permission + configuration

    private func requestAccessAndConfigure() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureSession()
                    } else {
                        self?.onError?(.denied)
                    }
                }
            }
        case .denied:
            onError?(.denied)
        case .restricted:
            onError?(.restricted)
        @unknown default:
            onError?(.denied)
        }
    }

    private func configureSession() {
        // No capture device on the simulator → fall back to manual entry.
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            onError?(.unavailable)
            return
        }

        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            onError?(.unavailable)
            return
        }
        session.addInput(input)

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else {
            session.commitConfiguration()
            onError?(.unavailable)
            return
        }
        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
        metadataOutput.metadataObjectTypes = [.qr]
        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview

        startRunningIfReady()
    }

    private func startRunningIfReady() {
        guard !session.inputs.isEmpty else { return }
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !didDeliver,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue else { return }

        // Deliver exactly once, then stop the session so we don't flood the
        // controller with duplicate frames of the same code.
        didDeliver = true
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        sessionQueue.async { [weak self] in self?.session.stopRunning() }
        onScan?(value)
    }
}
