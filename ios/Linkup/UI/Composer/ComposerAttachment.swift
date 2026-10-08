import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

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

/// Result of preparing an image off the main thread: bridge-safe bytes (JPEG/PNG/GIF/WebP only) + a small thumbnail.
struct PreparedImage: @unchecked Sendable {
    let data: Data
    let mime: String
    let name: String
    let thumbnail: UIImage?
}

enum ComposerImagePipeline {
    /// Longest edge sent to the agent (the Claude API downsamples anything bigger anyway).
    static let maxPixel: CGFloat = 2048
    /// Hard cap on what we upload for an image (the API rejects > 5 MB).
    static let maxBytes = 4_500_000

    /// Decodes with ImageIO (handles HEIC, orientation, huge photos without full-size bitmaps), downsizes to
    /// `maxPixel` and encodes JPEG 0.8. GIF/WebP pass through untouched when small enough. Call off the main thread.
    nonisolated static func prepare(data: Data, suggestedName: String, mime: String) -> PreparedImage? {
        let lowerMime = mime.lowercased()
        let base = (suggestedName as NSString).deletingPathExtension
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let thumb = thumbnail(from: source, maxPixel: 200)

        if (lowerMime == "image/gif" || lowerMime == "image/webp"), data.count <= maxBytes {
            let ext = lowerMime == "image/gif" ? "gif" : "webp"
            return PreparedImage(data: data, mime: lowerMime, name: "\(base).\(ext)", thumbnail: thumb)
        }
        var edge = maxPixel
        for quality in [0.8, 0.6, 0.45] {
            guard let cg = thumbnailCG(from: source, maxPixel: edge),
                  let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: quality) else { return nil }
            if jpeg.count <= maxBytes || quality == 0.45 {
                return PreparedImage(data: jpeg, mime: "image/jpeg", name: "\(base).jpg", thumbnail: thumb)
            }
            edge = edge * 0.75
        }
        return nil
    }

    nonisolated static func prepare(image: UIImage, name: String) -> PreparedImage? {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        return prepare(data: data, suggestedName: name, mime: "image/jpeg")
    }

    nonisolated private static func thumbnailCG(from source: CGImageSource, maxPixel: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    nonisolated private static func thumbnail(from source: CGImageSource, maxPixel: CGFloat) -> UIImage? {
        thumbnailCG(from: source, maxPixel: maxPixel).map { UIImage(cgImage: $0) }
    }
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
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    // The sheet hosting this picker is full-bleed so the camera preview isn't letterboxed.
    static func dismantleUIViewController(_ uiViewController: UIImagePickerController, coordinator: Coordinator) {
        uiViewController.delegate = nil
    }

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
