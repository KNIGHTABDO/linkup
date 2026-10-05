import SwiftUI
import UIKit

/// An item attached in the composer (image thumbnail or file capsule).
struct ComposerAttachment: Identifiable {
    let id: UUID
    let name: String
    let mime: String
    let data: Data
    let thumbnail: UIImage?
    var isUploading: Bool = false
    var uploadedRecord: [String: JSONValue]?
    var uploadFailed: Bool = false

    var isImage: Bool { mime.hasPrefix("image/") }
}

/// Camera sheet wrapping UIImagePickerController.
struct ComposerCameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onImageCaptured: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ComposerCameraPicker
        init(_ parent: ComposerCameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage {
                parent.onImageCaptured(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
