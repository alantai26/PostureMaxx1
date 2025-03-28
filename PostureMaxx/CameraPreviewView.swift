import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraManager // Pass the manager

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        // Ensure previewLayer is accessed on the main thread if needed after async setup
        DispatchQueue.main.async {
            cameraManager.previewLayer?.frame = view.bounds
            cameraManager.previewLayer?.videoGravity = .resizeAspectFill // Ensure gravity is set
             if let layer = cameraManager.previewLayer {
                view.layer.addSublayer(layer)
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Update frame if view layout changes
         DispatchQueue.main.async {
             cameraManager.previewLayer?.frame = uiView.bounds
        }
    }
}
