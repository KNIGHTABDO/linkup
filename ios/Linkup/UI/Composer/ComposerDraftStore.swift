import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// One composer draft: text, attachments, chosen slash command and the in-flight flags. Lives outside the view
/// because ChatView keeps a single ComposerView alive while its `sessionId` changes; uploads write here, so a
/// photo picked in chat A finishes in chat A's draft even if the user has moved on.
@MainActor @Observable
final class ComposerDraft {
    var text = ""
    var attachments: [ComposerAttachment] = []
    var selectedCommand: String?
    /// First message of a new chat: `create` is running, the composer is locked.
    var isCreating = false
    /// A send was issued and the bridge hasn't reported the turn running yet (keeps Stop showing, no flash).
    var isSending = false
    /// Stop was tapped; waiting for the turn to end.
    var isStopping = false

    @ObservationIgnored private var sendingReset: Task<Void, Never>?
    @ObservationIgnored private var stoppingReset: Task<Void, Never>?

    var isUploading: Bool { attachments.contains { $0.isUploading } }
    var hasFailedUpload: Bool { attachments.contains { $0.uploadFailed } }
    var isEmpty: Bool {
        selectedCommand == nil && attachments.isEmpty
            && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func clear() {
        text = ""
        attachments = []
        selectedCommand = nil
    }

    /// Marks a send in flight; falls back after `timeout` seconds so a dropped send can't pin the Stop button.
    func markSending(timeout: Double = 8) {
        isSending = true
        sendingReset?.cancel()
        sendingReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self?.isSending = false
        }
    }

    func clearSending() {
        isSending = false
        sendingReset?.cancel()
    }

    func markStopping(timeout: Double = 10) {
        isStopping = true
        stoppingReset?.cancel()
        stoppingReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self?.isStopping = false
        }
    }

    func clearStopping() {
        isStopping = false
        stoppingReset?.cancel()
    }

    // MARK: Attachments

    func remove(_ id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    /// Adds already-prepared bytes and uploads them in the background. `onError` surfaces failures (toast).
    func add(name: String, mime: String, data: Data, thumbnail: UIImage?,
             client: LinkupClient, onError: @escaping (String) -> Void) {
        let att = ComposerAttachment(id: UUID(), name: name, mime: mime, data: data,
                                     thumbnail: thumbnail, isUploading: true)
        attachments.append(att)
        upload(att.id, client: client, onError: onError)
    }

    func retry(_ id: UUID, client: LinkupClient, onError: @escaping (String) -> Void) {
        guard let idx = attachments.firstIndex(where: { $0.id == id }) else { return }
        attachments[idx].uploadFailed = false
        attachments[idx].isUploading = true
        upload(id, client: client, onError: onError)
    }

    private func upload(_ id: UUID, client: LinkupClient, onError: @escaping (String) -> Void) {
        guard let att = attachments.first(where: { $0.id == id }) else { return }
        let (data, name, mime) = (att.data, att.name, att.mime)
        Task { [weak self] in
            do {
                let record = try await client.upload(data: data, name: name, mime: mime)
                guard let self, let idx = self.attachments.firstIndex(where: { $0.id == id }) else { return }
                self.attachments[idx].uploadedRecord = record
                self.attachments[idx].isUploading = false
            } catch {
                if let self, let idx = self.attachments.firstIndex(where: { $0.id == id }) {
                    self.attachments[idx].isUploading = false
                    self.attachments[idx].uploadFailed = true
                }
                onError("Couldn't upload \(name): \(error.localizedDescription)")
            }
        }
    }

    /// Decodes + downsizes an image off the main thread, then attaches it.
    func addImage(data: Data, name: String, mime: String,
                  client: LinkupClient, onError: @escaping (String) -> Void) {
        Task { [weak self] in
            let prepared = await Task.detached(priority: .userInitiated) {
                ComposerImagePipeline.prepare(data: data, suggestedName: name, mime: mime)
            }.value
            guard let self else { return }
            guard let prepared else {
                onError("Couldn't read \(name) as an image")
                return
            }
            self.add(name: prepared.name, mime: prepared.mime, data: prepared.data,
                     thumbnail: prepared.thumbnail, client: client, onError: onError)
        }
    }

    func addCameraImage(_ image: UIImage, client: LinkupClient, onError: @escaping (String) -> Void) {
        let name = "camera-\(Int(Date().timeIntervalSince1970)).jpg"
        Task { [weak self] in
            let prepared = await Task.detached(priority: .userInitiated) {
                ComposerImagePipeline.prepare(image: image, name: name)
            }.value
            guard let self else { return }
            guard let prepared else { onError("Couldn't process the photo"); return }
            self.add(name: prepared.name, mime: prepared.mime, data: prepared.data,
                     thumbnail: prepared.thumbnail, client: client, onError: onError)
        }
    }

    /// Reads picked files off the main thread (security-scoped), toasting any that can't be read.
    func addFiles(_ urls: [URL], client: LinkupClient, onError: @escaping (String) -> Void) {
        for url in urls {
            Task { [weak self] in
                let loaded = await Task.detached(priority: .userInitiated) { () -> (Data, String)? in
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                        ?? "application/octet-stream"
                    return (data, mime)
                }.value
                guard let self else { return }
                guard let (data, mime) = loaded else {
                    onError("Couldn't read \(url.lastPathComponent)")
                    return
                }
                if mime.hasPrefix("image/") {
                    self.addImage(data: data, name: url.lastPathComponent, mime: mime, client: client, onError: onError)
                } else {
                    self.add(name: url.lastPathComponent, mime: mime, data: data, thumbnail: nil,
                             client: client, onError: onError)
                }
            }
        }
    }
}

/// Drafts keyed by session id (`nil` = the new-chat screen).
@MainActor @Observable
final class ComposerDraftStore {
    static let shared = ComposerDraftStore()
    static let newChatKey = "__new__"

    @ObservationIgnored private var drafts: [String: ComposerDraft] = [:]

    func draft(for sessionId: String?) -> ComposerDraft {
        let key = sessionId ?? Self.newChatKey
        if let d = drafts[key] { return d }
        let d = ComposerDraft()
        drafts[key] = d
        return d
    }
}
