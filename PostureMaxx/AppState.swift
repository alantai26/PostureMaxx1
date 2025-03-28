//
//  AppState.swift
//  PostureMaxx
//
//  Created by Joshua  Chan  on 3/28/25.
//

import SwiftUI
import Combine // Needed for ObservableObject

// Define possible posture statuses
enum PostureStatus: String, Equatable {
    case initializing = "Initializing"
    case needsCalibration = "Needs Calibration"
    case calibrating = "Calibrating..."
    case monitoringGood = "Good Posture"
    case monitoringPoor = "Adjust Posture"
    case noDetection = "Detection Lost" // e.g., User out of frame, poor lighting
    case pocketNoSignal = "Pocket Mode: No Signal" // e.g., Phone flat on table
    case paused = "Paused"
    case error = "Error Occurred"
}

// Define app modes
enum AppMode: String, CaseIterable {
    case camera = "Camera Mode"
    case pocket = "Pocket Mode"
}

// Main state manager
class AppState: ObservableObject {
    @Published var currentMode: AppMode = .camera // Default mode
    @Published var postureStatus: PostureStatus = .initializing
    @Published var isMonitoring: Bool = false // Is the session active?

    // Add other shared states later (e.g., sensitivity settings)

    // References to managers (initialized later)
    var cameraManager: CameraManager?

    //var pocketMotionManager: PocketMotionManager?
    
    init() {
        // 1. Create instance of CameraManager
        let camManager = CameraManager()
        // 2. Assign instance to AppState's property
        self.cameraManager = camManager

        // 3. Pass 'self' (the AppState instance) to the manager's weak var
        camManager.appState = self // This sets the back-reference
    }

    // ... methods to start/stop monitoring, trigger calibration etc.
    func startMonitoring() {
        guard postureStatus != .needsCalibration else {
            print("Cannot start monitoring: Calibration needed for \(currentMode.rawValue)")
            // Maybe update status to show calibration needed
            return
        }

        isMonitoring = true
        postureStatus = .monitoringGood // Assume good initially after start
        if currentMode == .camera {
            cameraManager?.startSession()
        } else {
           // pocketMotionManager?.startMonitoring()
        }
        print("Monitoring Started in \(currentMode.rawValue)")
    }

    func stopMonitoring() {
        isMonitoring = false
        postureStatus = .paused
        if currentMode == .camera {
            cameraManager?.stopSession()
        } else {
           // pocketMotionManager?.stopMonitoring()
        }
        print("Monitoring Stopped")
    }

    func requestCalibration() {
         guard !isMonitoring else {
             print("Stop monitoring before calibrating.")
             return
         }
         postureStatus = .calibrating
         // Managers will handle actual calibration logic
         if currentMode == .camera {
             cameraManager?.triggerCalibrationCapture()
         } else {
            // pocketMotionManager?.triggerCalibrationCapture()
         }
    }

    func updatePostureStatus(_ newStatus: PostureStatus) {
        // Only update if monitoring or in specific states
         guard isMonitoring ||
               newStatus == .noDetection ||
               newStatus == .pocketNoSignal ||
               newStatus == .error ||
               newStatus == .needsCalibration else { return }

        // Avoid redundant updates
        if self.postureStatus != newStatus {
             DispatchQueue.main.async { // Ensure UI updates on main thread
                self.postureStatus = newStatus
                print("Posture Status Updated: \(newStatus.rawValue)")
                // Trigger alerts based on newStatus here (Phase 5)
            }
        }
    }
}
