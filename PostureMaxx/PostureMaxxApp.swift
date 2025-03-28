//
//  PostureMaxxApp.swift
//  PostureMaxx
//
//  Created by Alan T on 3/27/25.
//

import SwiftUI
import SwiftData

@main
struct PostureMaxxApp: App {
    @StateObject var appState = AppState() // Create single instance

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState) // Inject into environment
        }
    }
}
