import SwiftUI
import AVFoundation
import Vision

// MARK: - Controller
class QRScannerController: NSViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var onRecognize: ((String) -> Bool)?
    
    private var isProcessing = false
    private var currentCameraIndex = 0
    private var availableCameras: [AVCaptureDevice] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view = NSView(frame: .zero)
        self.view.wantsLayer = true
        setupSession()
    }
    
    func setupSession() {
        captureSession = AVCaptureSession()
        
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified)
        availableCameras = discoverySession.devices
        
        guard let device = availableCameras.first else { return }
        switchCamera(to: device)
        
        // Output
        let videoOutput = AVCaptureVideoDataOutput()
        let queue = DispatchQueue(label: "videoQueue", qos: .userInteractive)
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        self.view.layer?.addSublayer(previewLayer)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }
    
    func switchCamera(to device: AVCaptureDevice) {
        captureSession.beginConfiguration()
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
        } catch {
            print("Error switching camera: \(error)")
        }
        captureSession.commitConfiguration()
    }
    
    func toggleCamera() {
        guard availableCameras.count > 1 else { return }
        currentCameraIndex = (currentCameraIndex + 1) % availableCameras.count
        switchCamera(to: availableCameras[currentCameraIndex])
    }
    
    override func viewDidLayout() {
        super.viewDidLayout()
        previewLayer?.frame = self.view.bounds
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isProcessing else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        isProcessing = true
        let request = VNDetectBarcodesRequest { [weak self] request, error in
            var successfulScan = false
            defer { 
                if !successfulScan {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self?.isProcessing = false
                    }
                }
            }
            
            if let results = request.results as? [VNBarcodeObservation], let first = results.first {
                if let payloadString = first.payloadStringValue {
                    DispatchQueue.main.sync {
                        if let success = self?.onRecognize?(payloadString), success {
                            self?.captureSession.stopRunning()
                            successfulScan = true
                        }
                    }
                }
            }
        }
        request.symbologies = [.qr]
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("Vision error: \(error)")
            isProcessing = false
        }
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
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
