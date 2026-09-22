import SwiftUI
import AVFoundation
import Vision

// MARK: - Frame processor
/// Separate object so the capture pipeline never points back at the view controller.
/// `AVCaptureVideoDataOutput` holds its sample-buffer delegate *strongly*, so making the
/// controller its own delegate creates controller → session → output → controller: the
/// controller and its camera session would then never be deallocated.
///
/// All state here is confined to `queue`, which is also the output's callback queue.
private final class QRFrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let queue = DispatchQueue(label: "com.authmate.qrscanner.video", qos: .userInitiated)

    /// Invoked on the main queue with a decoded payload. Scanning stays paused until the
    /// receiver either tears the session down or calls `resumeAfterThrottle()`.
    var onPayload: ((String) -> Void)?

    private var isPaused = false

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isPaused, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isPaused = true

        var payload: String?
        let request = VNDetectBarcodesRequest { request, _ in
            // Vision runs this completion synchronously inside perform().
            payload = (request.results as? [VNBarcodeObservation])?.first?.payloadStringValue
        }
        request.symbologies = [.qr]

        do {
            try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])
        } catch {
            print("Vision error: \(error)")
        }

        guard let payload else {
            resumeAfterThrottle()
            return
        }

        // Async, never sync: the handler may stop the session, and stopRunning() waits for
        // this queue to drain — a main.sync here would deadlock the two against each other.
        DispatchQueue.main.async { [weak self] in
            self?.onPayload?(payload)
        }
    }

    func resumeAfterThrottle() {
        queue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.isPaused = false
        }
    }
}

// MARK: - Controller
final class QRScannerController: NSViewController {
    var onRecognize: ((String) -> Bool)?

    /// `startRunning()`, `stopRunning()` and `commitConfiguration()` are blocking calls and
    /// must stay off the main thread. A *serial* queue also guarantees that a teardown
    /// queued while the session is still starting up runs after the start, so the camera
    /// can never be left running by a stop/start race.
    private let sessionQueue = DispatchQueue(label: "com.authmate.qrscanner.session")
    private let processor = QRFrameProcessor()

    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private var availableCameras: [AVCaptureDevice] = []
    private var currentCameraIndex = 0
    private var isTornDown = false

    override func loadView() {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSession()
    }

    private func setupSession() {
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified)
        availableCameras = discoverySession.devices
        guard let device = availableCameras.first else { return }

        let session = AVCaptureSession()
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true

        processor.onPayload = { [weak self] payload in
            guard let self else { return }
            if self.onRecognize?(payload) == true {
                self.teardown()
            } else {
                self.processor.resumeAfterThrottle()
            }
        }
        output.setSampleBufferDelegate(processor, queue: processor.queue)

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer?.addSublayer(layer)

        captureSession = session
        videoOutput = output
        previewLayer = layer

        sessionQueue.async {
            session.beginConfiguration()
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) { session.addInput(input) }
            } catch {
                print("Error opening camera: \(error)")
            }
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            session.startRunning()
        }
    }

    func toggleCamera() {
        guard availableCameras.count > 1, let session = captureSession else { return }
        currentCameraIndex = (currentCameraIndex + 1) % availableCameras.count
        let device = availableCameras[currentCameraIndex]

        sessionQueue.async {
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) { session.addInput(input) }
            } catch {
                print("Error switching camera: \(error)")
            }
            session.commitConfiguration()
        }
    }

    /// Releases the camera. Idempotent, and safe to call from any of the teardown paths
    /// (successful scan, view removal, SwiftUI dismantling the representable).
    func teardown() {
        guard !isTornDown else { return }
        isTornDown = true

        processor.onPayload = nil
        videoOutput?.setSampleBufferDelegate(nil, queue: nil)
        previewLayer?.removeFromSuperlayer()

        let session = captureSession
        captureSession = nil
        videoOutput = nil
        previewLayer = nil

        sessionQueue.async { session?.stopRunning() }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        teardown()
    }

    deinit {
        // Last resort if no teardown path fired; the delegate is the processor, not self,
        // so reaching deinit at all is already proof the retain cycle is gone.
        captureSession?.stopRunning()
    }
}

// MARK: - View Representable
struct QRScannerNSView: NSViewControllerRepresentable {
    var onRecognize: (String) -> Bool
    var controllerReference: Binding<QRScannerController?>

    func makeNSViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onRecognize = onRecognize
        DispatchQueue.main.async {
            controllerReference.wrappedValue = controller
        }
        return controller
    }

    func updateNSViewController(_ nsViewController: QRScannerController, context: Context) {}

    static func dismantleNSViewController(_ nsViewController: QRScannerController, coordinator: Coordinator) {
        nsViewController.teardown()
    }
}

// MARK: - Parent SwiftUI View
struct QRScannerView: View {
    var onRecognize: (String) -> Bool

    @State private var hasPermission = false
    @State private var permissionDetermined = false
    @State private var controller: QRScannerController? = nil

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            if permissionDetermined {
                if hasPermission {
                    QRScannerNSView(onRecognize: onRecognize, controllerReference: $controller)

                    // Crosshair overlay
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [10]))
                        .frame(width: 200, height: 200)

                    // Switch camera floating button
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                controller?.toggleCamera()
                            }) {
                                Image(systemName: "camera.rotate")
                                    .font(.title2)
                                    .padding(12)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Circle())
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                            .padding()
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.badge.ellipsis")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("Camera Access Denied")
                            .font(.headline)
                        Text("Please enable AuthMate to use the camera in System Preferences.")
                            .multilineTextAlignment(.center)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            } else {
                ProgressView("Checking access...")
            }
        }
        .onAppear(perform: requestPermission)
        .onDisappear {
            controller?.teardown()
        }
    }

    private func requestPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            hasPermission = true
            permissionDetermined = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    hasPermission = granted
                    permissionDetermined = true
                }
            }
        default:
            hasPermission = false
            permissionDetermined = true
        }
    }
}
