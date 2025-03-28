import AVFoundation
import Vision
import UIKit // For device orientation
import Combine
import CoreImage // For CIContext if needed

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    // Optional: Publish recognized points for drawing overlays
    // Near the top of CameraManager class
    @Published var detectedBodyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint]? = nil // Use JointName as key

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.yourapp.sessionQueue", qos: .userInitiated)
    private let visionQueue = DispatchQueue(label: "com.yourapp.visionQueue", qos: .userInitiated)

    private var bodyPoseRequest = VNDetectHumanBodyPoseRequest()

    // Reference back to AppState to update status and get calibration data
    weak var appState: AppState?

    // Calibration Data (Loaded from UserDefaults in init/setup)
    private var calibratedNeckShoulderDistance: CGFloat?
    // Add other baseline metrics as needed

    override init() {
        super.init()
        setupSession()
        loadCalibrationData() // Load baseline when manager is created
    }

    // --- Setup ---
    private func setupSession() {
        sessionQueue.async { [unowned self] in
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .high // Or .medium - balance quality/performance

            // Input
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
                  self.captureSession.canAddInput(videoDeviceInput) else {
                self.handleError("Failed to get camera input")
                self.captureSession.commitConfiguration()
                return
            }
            self.captureSession.addInput(videoDeviceInput)

            // Output
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                // Use BGRA format, common for iOS image processing
                self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
                self.videoOutput.setSampleBufferDelegate(self, queue: self.visionQueue) // Process frames on vision queue
                self.captureSession.addOutput(self.videoOutput)
            } else {
                self.handleError("Failed to add video output")
                self.captureSession.commitConfiguration()
                return
            }

            // Preview Layer (main thread setup needed)
            let layer = AVCaptureVideoPreviewLayer(session: self.captureSession)
            layer.videoGravity = .resizeAspectFill
             DispatchQueue.main.async {
                self.previewLayer = layer
            }

            self.captureSession.commitConfiguration()
        }
    }

    // --- Control ---
    func startSession() {
        sessionQueue.async {
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
                print("Camera Session Started")
                // Ensure calibration status is checked after starting
                self.checkCalibrationStatus()
            }
        }
    }

    func stopSession() {
        sessionQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                print("Camera Session Stopped")
                 DispatchQueue.main.async { // Clear detected points when stopping
                    self.detectedBodyPoints = nil
                }
            }
        }
    }

    // --- Delegate Method (Receives Frames) ---
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Determine correct orientation for Vision request
        let currentOrientation = UIDevice.current.orientation
        let exifOrientation = exifOrientationForDeviceOrientation(currentOrientation)

        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: exifOrientation, options: [:])

        do {
            // Perform the body pose request
            try requestHandler.perform([self.bodyPoseRequest])

            // Process results
            if let results = self.bodyPoseRequest.results, !results.isEmpty {
                self.processVisionResults(results)
            } else {
                 // No bodies detected
                 DispatchQueue.main.async {
                     self.detectedBodyPoints = nil // Clear points if no body found
                }
                if appState?.isMonitoring == true {
                    appState?.updatePostureStatus(.noDetection)
                }
            }

        } catch {
            print("Error performing Vision request: \(error)")
             appState?.updatePostureStatus(.error)
        }
    }

    // --- Vision Processing ---
    private func processVisionResults(_ results: [VNHumanBodyPoseObservation]) {
        guard let observation = results.first else { return } // Assume only one person

        // Get all recognized points
        guard let recognizedPoints = try? observation.recognizedPoints(.all) else {
             DispatchQueue.main.async { self.detectedBodyPoints = nil } // Clear points if error
             return
        }

         // Filter points with low confidence
        let confidentPoints = recognizedPoints.filter { $1.confidence > 0.3 }
        let pointsForUI = Dictionary(uniqueKeysWithValues: confidentPoints.map { ($0.key, $0.value.location) })
        DispatchQueue.main.async {
            self.detectedBodyPoints = pointsForUI // Update published points for UI overlay
        }

        // --- Posture Analysis (Phase 4 Logic - Integrated Here) ---
        guard appState?.isMonitoring == true else { return } // Only analyze if monitoring
        // Use VNHumanBodyPoseObservation.JointName constants
        guard let neckPoint = confidentPoints[VNHumanBodyPoseObservation.JointName.neck],
              let rsPoint = confidentPoints[VNHumanBodyPoseObservation.JointName.rightShoulder],
              let lsPoint = confidentPoints[VNHumanBodyPoseObservation.JointName.leftShoulder] else {
            appState?.updatePostureStatus(.noDetection) // Missing key points
            return
        }

        // Use the actual VNRecognizedPoint objects to access location
        let neck = neckPoint.location
        let rs = rsPoint.location
        let ls = lsPoint.location

        // Example Metric: Vertical distance between neck and shoulder midpoint
        let shoulderMidY = (rs.y + ls.y) / 2.0 // Use .y directly on CGPoint
        let currentNeckShoulderDistance = abs(neck.y - shoulderMidY)

        // Compare to calibrated baseline
        guard let baselineDistance = self.calibratedNeckShoulderDistance else {
             appState?.updatePostureStatus(.needsCalibration) // Should have been checked earlier, but safeguard
             return
        }

        // Define thresholds (relative difference might be better than absolute)
        let deviation = abs(currentNeckShoulderDistance - baselineDistance)
        let deviationPercentage = baselineDistance > 0 ? (deviation / baselineDistance) * 100 : 0

        // --- Update App State ---
        // Example thresholds - TUNE THESE CAREFULLY!
        if deviationPercentage > 20.0 { // e.g., 20% deviation = poor posture
            appState?.updatePostureStatus(.monitoringPoor)
        } else {
            appState?.updatePostureStatus(.monitoringGood)
        }
        // Add more complex metrics (head forward, shoulder angle) here
    }

     // --- Calibration ---
    func triggerCalibrationCapture() {
        // Request a capture and analysis of the current pose for baseline
        // The next call to processVisionResults while appState.postureStatus == .calibrating will handle it
        print("Camera Calibration Triggered - Hold good posture!")
        // Set a brief timer, then capture state from the next valid Vision result
         DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { // Give user a moment
            self.captureCalibrationPose()
        }
    }

    private func captureCalibrationPose() {
        // Access the latest processed points (needs careful handling if async)
        // Or re-run a single Vision request specifically for calibration
        // For simplicity, let's assume we use the next valid result from processVisionResults
        guard let points = self.detectedBodyPoints, // points is now [VNHumanBodyPoseObservation.JointName: CGPoint]?
              // Use VNHumanBodyPoseObservation.JointName constants
              let neck = points[VNHumanBodyPoseObservation.JointName.neck],
              let rs = points[VNHumanBodyPoseObservation.JointName.rightShoulder],
              let ls = points[VNHumanBodyPoseObservation.JointName.leftShoulder] else {
            print("Calibration Failed: Could not detect key points clearly.")
            appState?.updatePostureStatus(.needsCalibration) // Revert status
            return
        }

        // Calculate baseline metric(s) using the CGPoints directly
        let shoulderMidY = (rs.y + ls.y) / 2.0
        self.calibratedNeckShoulderDistance = abs(neck.y - shoulderMidY)
        // Calculate and store other baselines here

        // --- Save to UserDefaults (Phase 3) ---
        saveCalibrationData()
        print("Camera Calibration Complete. Baseline distance: \(self.calibratedNeckShoulderDistance ?? -1)")
         appState?.updatePostureStatus(.paused) // Indicate ready to start monitoring
    }

    private func saveCalibrationData() {
         UserDefaults.standard.set(calibratedNeckShoulderDistance, forKey: "calibratedNeckShoulderDistance_camera")
         // Save other baseline values
    }

    private func loadCalibrationData() {
         self.calibratedNeckShoulderDistance = UserDefaults.standard.object(forKey: "calibratedNeckShoulderDistance_camera") as? CGFloat
         // Load other baseline values
         print("Loaded Camera Calibration: \(self.calibratedNeckShoulderDistance ?? -1)")
         checkCalibrationStatus()
    }

    private func checkCalibrationStatus() {
         // If not monitoring and no calibration data, set status
         if appState?.isMonitoring == false && self.calibratedNeckShoulderDistance == nil {
             appState?.updatePostureStatus(.needsCalibration)
         }
     }

    // --- Error Handling ---
    private func handleError(_ message: String) {
        print("CameraManager Error: \(message)")
        DispatchQueue.main.async {
            self.appState?.updatePostureStatus(.error)
        }
    }
}

// --- Orientation Helper --- outside CameraManager class
func exifOrientationForDeviceOrientation(_ deviceOrientation: UIDeviceOrientation) -> CGImagePropertyOrientation {
    switch deviceOrientation {
    case .portraitUpsideDown: return .left
    case .landscapeLeft: return .up // Home button on right
    case .landscapeRight: return .down // Home button on left
    case .portrait: return .right
    default: return .right // Assume portrait if unknown/faceup/facedown
    }
}
