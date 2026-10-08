import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Plain, Sendable copy of a transcript. Taken on the main actor in one pass; everything after that
/// (markdown, PDF layout, file writes) runs on a background task.
struct ChatExportSnapshot: Sendable {
    enum Part: Sendable {
        case text(String)
        case tool(String)
        case artifact(String)
        case error(String)
    }

    enum Item: Sendable {
        case user(text: String, attachments: [String])
        case assistant([Part])
    }

    var title: String?
    var items: [Item]

    @MainActor
    init(transcript: Transcript, title: String?) {
        self.title = title
        var out: [Item] = []
        for item in transcript.items {
            switch item {
            case .user(let user):
                out.append(.user(text: user.text, attachments: user.attachments.map(\.name)))
            case .assistant(let turn):
                var parts: [Part] = []
                for part in turn.parts {
                    switch part {
                    case .tool(let tool):
                        let name = tool.presentation.doneTitle.isEmpty ? tool.name : tool.presentation.doneTitle
                        parts.append(.tool(name))
                    case .text(let block):
                        if !block.text.isEmpty { parts.append(.text(block.text)) }
                    case .artifact(let ref):
                        parts.append(.artifact("\(ref.title) (\(ref.kind))"))
                    case .error(_, let msg):
                        parts.append(.error(msg))
                    default:
                        break
                    }
                }
                out.append(.assistant(parts))
            }
        }
        items = out
    }
}

enum ChatExportError: LocalizedError {
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let what): "Could not create the \(what) export."
        }
    }
}

/// Generates export files (.md and .pdf) for conversation transcripts. Pure functions of a snapshot.
enum ChatExportHelper {
    /// Markdown of the whole transcript: user/agent text, tool titles as `> Used …` lines.
    /// Every part is separated by a blank line so paragraphs and quote lines never merge.
    static func generateMarkdown(_ snapshot: ChatExportSnapshot) -> String {
        var blocks: [String] = []
        let displayTitle = snapshot.title?.isEmpty == false ? snapshot.title! : "Conversation Transcript"
        blocks.append("# \(displayTitle)")

        for item in snapshot.items {
            switch item {
            case .user(let text, let attachments):
                blocks.append("### User")
                if !text.isEmpty { blocks.append(text) }
                if !attachments.isEmpty {
                    // Attachment links are bridge-relative and mean nothing outside the app: names only.
                    blocks.append(attachments.map { "- Attachment: \($0)" }.joined(separator: "\n"))
                }
            case .assistant(let parts):
                blocks.append("### Assistant")
                var quoteRun: [String] = []
                func flushQuotes() {
                    if !quoteRun.isEmpty {
                        blocks.append(quoteRun.joined(separator: "\n>\n"))
                        quoteRun.removeAll()
                    }
                }
                for part in parts {
                    switch part {
                    case .tool(let title): quoteRun.append("> Used \(title)")
                    case .artifact(let title): quoteRun.append("> Artifact: \(title)")
                    case .error(let msg): quoteRun.append("> Error: \(msg)")
                    case .text(let text):
                        flushQuotes()
                        blocks.append(text)
                    }
                }
                flushQuotes()
            }
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    static func exportMarkdownFile(_ snapshot: ChatExportSnapshot) throws -> URL {
        let md = generateMarkdown(snapshot)
        let url = tempURL(title: snapshot.title, ext: "md")
        do {
            try md.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ChatExportError.writeFailed("Markdown")
        }
        return url
    }

    static func exportPDFFile(_ snapshot: ChatExportSnapshot) throws -> URL {
        let url = tempURL(title: snapshot.title, ext: "pdf")
        try ChatPDFRenderer.renderPDF(snapshot, to: url)
        return url
    }

    private static func tempURL(title: String?, ext: String) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("linkup-export-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(sanitizeFilename(title ?? "Linkup-Chat")).\(ext)")
    }

    private static func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let components = name.components(separatedBy: invalid)
        let filtered = components.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return filtered.isEmpty ? "Linkup-Chat" : String(filtered.prefix(80))
    }
}

/// Renders a snapshot into a formatted multi-page PDF using UIGraphicsPDFRenderer. Markdown in agent text is
/// parsed and drawn as styled runs (headings, lists, quotes, code, tables) instead of showing raw markers.
enum ChatPDFRenderer {
    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 48

    private static let titleColor = UIColor(red: 0x1F / 255, green: 0x1E / 255, blue: 0x1D / 255, alpha: 1.0)
    private static let secondaryColor = UIColor(red: 0x73 / 255, green: 0x71 / 255, blue: 0x6B / 255, alpha: 1.0)
    private static let bodyColor = UIColor(red: 0x26 / 255, green: 0x26 / 255, blue: 0x24 / 255, alpha: 1.0)
    private static let accentColor = UIColor(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1.0)
    private static let errorColor = UIColor(red: 0xE5 / 255, green: 0x5B / 255, blue: 0x4F / 255, alpha: 1)
    private static let hairlineColor = UIColor(white: 0.85, alpha: 1.0)
    private static let codeBackground = UIColor(white: 0.95, alpha: 1.0)

    static func renderPDF(_ snapshot: ChatExportSnapshot, to fileURL: URL) throws {
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let printableWidth = pageWidth - margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: UIGraphicsPDFRendererFormat())

        let titleFont = UIFont.boldSystemFont(ofSize: 20)
        let subtitleFont = UIFont.systemFont(ofSize: 11)
        let roleFont = UIFont.systemFont(ofSize: 11, weight: .bold)
        let footerFont = UIFont.systemFont(ofSize: 9)

        do {
            try renderer.writePDF(to: fileURL) { context in
                var pageNumber = 1
                let cursor = PDFCursor(y: margin)

                func startNewPage() {
                    context.beginPage()
                    cursor.y = margin
                    NSAttributedString(string: "Linkup \u{00B7} Page \(pageNumber)", attributes: [
                        .font: footerFont, .foregroundColor: secondaryColor
                    ]).draw(at: CGPoint(x: margin, y: pageHeight - margin + 14))
                    pageNumber += 1
                }

                func checkSpace(_ needed: CGFloat) {
                    if cursor.y + needed > pageHeight - margin - 20 { startNewPage() }
                }

                func drawLine(_ text: String, font: UIFont, color: UIColor, x: CGFloat = margin, after: CGFloat = 4) {
                    drawAttributed(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]),
                                   x: x, width: pageWidth - margin - x, cursor: cursor, checkSpace: checkSpace, after: after)
                }

                startNewPage()

                let heading = snapshot.title?.isEmpty == false ? snapshot.title! : "Linkup Conversation"
                drawLine(heading, font: titleFont, color: titleColor, after: 6)

                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                dateFormatter.timeStyle = .short
                drawLine("Exported on \(dateFormatter.string(from: Date()))", font: subtitleFont, color: secondaryColor, after: 10)

                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: cursor.y))
                path.addLine(to: CGPoint(x: pageWidth - margin, y: cursor.y))
                hairlineColor.setStroke()
                path.lineWidth = 1
                path.stroke()
                cursor.y += 16

                for item in snapshot.items {
                    switch item {
                    case .user(let text, let attachments):
                        checkSpace(40)
                        drawLine("USER", font: roleFont, color: secondaryColor, after: 4)
                        if !text.isEmpty {
                            drawPlain(text, font: .systemFont(ofSize: 12), color: bodyColor, width: printableWidth,
                                      cursor: cursor, checkSpace: checkSpace)
                        }
                        for name in attachments {
                            drawLine("Attachment: \(name)", font: subtitleFont, color: secondaryColor, x: margin + 8, after: 4)
                        }
                        cursor.y += 12

                    case .assistant(let parts):
                        checkSpace(40)
                        drawLine("ASSISTANT", font: roleFont, color: accentColor, after: 4)
                        for part in parts {
                            switch part {
                            case .tool(let title):
                                drawLine("Used \(title)", font: .italicSystemFont(ofSize: 11), color: secondaryColor, x: margin + 8, after: 4)
                            case .artifact(let title):
                                drawLine("Artifact: \(title)", font: .italicSystemFont(ofSize: 11), color: secondaryColor, x: margin + 8, after: 4)
                            case .error(let msg):
                                drawLine("Error: \(msg)", font: .systemFont(ofSize: 12), color: errorColor, after: 6)
                            case .text(let text):
                                drawMarkdown(text, width: printableWidth, cursor: cursor, checkSpace: checkSpace)
                            }
                        }
                        cursor.y += 14
                    }
                }
            }
        } catch {
            throw ChatExportError.writeFailed("PDF")
        }
    }

    // MARK: Drawing

    private static func paragraphStyle(spacing: CGFloat = 3) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = spacing
        return style
    }

    /// Draws an attributed string, splitting it by lines across pages when it is taller than a page.
    private static func drawAttributed(
        _ text: NSAttributedString,
        x: CGFloat,
        width: CGFloat,
        cursor: PDFCursor,
        checkSpace: (CGFloat) -> Void,
        after: CGFloat,
        background: UIColor? = nil
    ) {
        guard text.length > 0 else { return }
        let bounds = text.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
        )
        let height = ceil(bounds.height)
        if height < 600 {
            checkSpace(height + after)
            if let background {
                background.setFill()
                UIBezierPath(roundedRect: CGRect(x: x - 4, y: cursor.y - 3, width: width + 8, height: height + 6), cornerRadius: 4).fill()
            }
            text.draw(in: CGRect(x: x, y: cursor.y, width: width, height: height))
            cursor.y += height + after
            return
        }
        // Taller than most of a page: draw line by line so page breaks fall between lines.
        let ns = text.string as NSString
        var location = 0
        while location < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(lineRange)
            let line = text.attributedSubstring(from: lineRange)
            let lineHeight = ceil(line.boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
            ).height)
            checkSpace(max(lineHeight, 12) + 2)
            line.draw(in: CGRect(x: x, y: cursor.y, width: width, height: max(lineHeight, 12)))
            cursor.y += max(lineHeight, 12) + 2
        }
        cursor.y += after
    }

    /// Plain paragraphs (user text): split at blank lines.
    private static func drawPlain(
        _ text: String, font: UIFont, color: UIColor, width: CGFloat,
        cursor: PDFCursor, checkSpace: (CGFloat) -> Void
    ) {
        for para in text.components(separatedBy: "\n\n") {
            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let attr = NSAttributedString(string: trimmed, attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraphStyle()
            ])
            drawAttributed(attr, x: margin, width: width, cursor: cursor, checkSpace: checkSpace, after: 8)
        }
    }

    /// Agent text: parsed markdown drawn as styled blocks.
    private static func drawMarkdown(
        _ text: String, width: CGFloat, cursor: PDFCursor, checkSpace: (CGFloat) -> Void
    ) {
        let bodyFont = UIFont.systemFont(ofSize: 12)
        let blocks = ChatMarkdownParser.parse(text)

        func inline(_ source: String, font: UIFont, color: UIColor = bodyColor) -> NSAttributedString {
            NSAttributedString(string: ChatMarkdownParser.plainInline(source), attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraphStyle()
            ])
        }

        for block in blocks {
            switch block {
            case .heading(let level, let source, _):
                let size: CGFloat = level == 1 ? 18 : level == 2 ? 15 : 13
                cursor.y += 4
                drawAttributed(inline(source, font: .boldSystemFont(ofSize: size), color: titleColor),
                               x: margin, width: width, cursor: cursor, checkSpace: checkSpace, after: 6)

            case .paragraph(let source, _):
                drawAttributed(inline(source, font: bodyFont), x: margin, width: width,
                               cursor: cursor, checkSpace: checkSpace, after: 8)

            case .code(_, let code, _):
                let attr = NSAttributedString(string: code, attributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: bodyColor,
                    .paragraphStyle: paragraphStyle(spacing: 2)
                ])
                drawAttributed(attr, x: margin + 8, width: width - 16, cursor: cursor, checkSpace: checkSpace,
                               after: 10, background: codeBackground)

            case .blockquote(let lines, _):
                let joined = lines.joined(separator: "\n")
                let start = cursor.y
                drawAttributed(inline(joined, font: .italicSystemFont(ofSize: 12), color: secondaryColor),
                               x: margin + 14, width: width - 14, cursor: cursor, checkSpace: checkSpace, after: 8)
                if cursor.y > start {
                    accentColor.setFill()
                    UIBezierPath(rect: CGRect(x: margin + 2, y: start, width: 2, height: cursor.y - start - 8)).fill()
                }

            case .list(let items, _):
                for item in items {
                    let marker: String
                    switch item.kind {
                    case .bullet: marker = item.level == 0 ? "\u{2022}" : "\u{25E6}"
                    case .number(let n): marker = "\(n)."
                    case .task(let done): marker = done ? "\u{2611}" : "\u{2610}"
                    }
                    let indent = margin + CGFloat(item.level) * 16
                    let startY = cursor.y
                    checkSpace(18)
                    let markerY = cursor.y
                    NSAttributedString(string: marker, attributes: [.font: bodyFont, .foregroundColor: secondaryColor])
                        .draw(at: CGPoint(x: indent, y: markerY))
                    _ = startY
                    drawAttributed(inline(item.text, font: bodyFont), x: indent + 18, width: width - (indent - margin) - 18,
                                   cursor: cursor, checkSpace: checkSpace, after: 3)
                }
                cursor.y += 5

            case .table(let headers, let rows, _):
                // Plain-text grid: one line per row, cells separated by " | " (PDF has no column layout here).
                var lines = [headers.map { ChatMarkdownParser.plainInline($0) }.joined(separator: "  |  ")]
                for row in rows { lines.append(row.map { ChatMarkdownParser.plainInline($0) }.joined(separator: "  |  ")) }
                let attr = NSAttributedString(string: lines.joined(separator: "\n"), attributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: bodyColor,
                    .paragraphStyle: paragraphStyle(spacing: 3)
                ])
                drawAttributed(attr, x: margin + 8, width: width - 16, cursor: cursor, checkSpace: checkSpace,
                               after: 10, background: codeBackground)

            case .horizontalRule:
                checkSpace(14)
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: cursor.y + 4))
                path.addLine(to: CGPoint(x: margin + width, y: cursor.y + 4))
                hairlineColor.setStroke()
                path.lineWidth = 1
                path.stroke()
                cursor.y += 12

            case .image(let alt, _, _):
                drawAttributed(inline(alt.isEmpty ? "[image]" : "[image: \(alt)]", font: .italicSystemFont(ofSize: 11), color: secondaryColor),
                               x: margin, width: width, cursor: cursor, checkSpace: checkSpace, after: 8)
            }
        }
    }
}

/// Vertical write position shared by the page-break closure and the drawing helpers (a class, so no inout aliasing).
final class PDFCursor {
    var y: CGFloat
    init(y: CGFloat) { self.y = y }
}

/// Builds the export file only when the share sheet asks for it (menus evaluate their content eagerly).
/// The transcript is snapshotted on the main actor in one pass; layout and file writing run detached.
struct ChatExportFile: Transferable {
    enum Kind: Sendable { case markdown, pdf }
    let transcript: Transcript
    let title: String?
    let kind: Kind

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { file in
            SentTransferredFile(try await file.makeFile())
        }
        .exportingCondition { $0.kind == .pdf }
        FileRepresentation(exportedContentType: .plainText) { file in
            SentTransferredFile(try await file.makeFile())
        }
        .exportingCondition { $0.kind == .markdown }
    }

    func makeFile() async throws -> URL {
        let title = self.title
        let kind = self.kind
        let snapshot = await MainActor.run { [transcript] in
            ChatExportSnapshot(transcript: transcript, title: title)
        }
        return try await Task.detached(priority: .userInitiated) {
            switch kind {
            case .markdown: return try ChatExportHelper.exportMarkdownFile(snapshot)
            case .pdf: return try ChatExportHelper.exportPDFFile(snapshot)
            }
        }.value
    }
}
