//
//  ContentView.swift
//  PostureMaxx
//
//  Created by Alan T on 3/27/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState // Access the shared state

    var body: some View {
        VStack {
            // Mode Picker
            Picker("Mode", selection: $appState.currentMode) {
                ForEach(AppMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            .disabled(appState.isMonitoring) // Disable mode change while monitoring

            Text("Status: \(appState.postureStatus.rawValue)")
                .padding()

            // Conditional view for camera/pocket display
            if appState.currentMode == .camera {
                // Placeholder for Camera Preview View
                if appState.currentMode == .camera, let manager = appState.cameraManager {
                     CameraPreviewView(cameraManager: manager)
                         .frame(height: 300) // Or adjust size as needed
                         // Add overlay here later if drawing points
                } // Replace later
            } else {
                // Placeholder for Pocket Mode instructions/display
               // PocketPlaceholderView() // Replace later
            }

            HStack {
                Button(appState.isMonitoring ? "Stop" : "Start") {
                    if appState.isMonitoring {
                        appState.stopMonitoring()
                    } else {
                        appState.startMonitoring()
                    }
                }
                .padding()
                .disabled(appState.postureStatus == .calibrating || appState.postureStatus == .initializing) // Disable if calibrating etc.


                Button("Calibrate") {
                    appState.requestCalibration()
                }
                .padding()
                .disabled(appState.isMonitoring) // Disable while monitoring
            }
            // Add NavigationLink to SettingsView later
        }
        .onAppear {
            // Initialize managers when view appears
            // Check for calibration status on appear
        }
    }
}
