import UIKit

/// Generates export files (.md and .pdf) for conversation transcripts.
enum ChatExportHelper {
    /// Generates markdown of the whole transcript: user/agent text and tool titles as `> Used …` lines.
    static func generateMarkdown(transcript: Transcript, title: String?) -> String {
        var lines: [String] = []
        let displayTitle = title?.isEmpty == false ? title! : "Conversation Transcript"
        lines.append("# \(displayTitle)\n")

        for item in transcript.items {
            switch item {
            case .user(let user):
                lines.append("### User\n")
                if !user.text.isEmpty {
                    lines.append(user.text)
                }
                for att in user.attachments {
                    lines.append("- Attachment: [\(att.name)](\(att.url))")
                }
                lines.append("")

            case .assistant(let turn):
                lines.append("### Assistant\n")
                for part in turn.parts {
                    switch part {
                    case .tool(let tool):
                        let toolTitle = tool.presentation.doneTitle.isEmpty ? tool.name : tool.presentation.doneTitle
                        lines.append("> Used \(toolTitle)")
                    case .text(let block):
                        if !block.text.isEmpty {
                            lines.append(block.text)
                        }
                    case .artifact(let ref):
                        lines.append("> Artifact: \(ref.title) (\(ref.kind))")
                    case .error(_, let msg):
                        lines.append("> Error: \(msg)")
                    default:
                        break
                    }
                }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Exports transcript to a temporary .md file and returns its URL.
    static func exportMarkdownFile(transcript: Transcript, title: String?) -> URL {
        let md = generateMarkdown(transcript: transcript, title: title)
        let sanitized = sanitizeFilename(title ?? "Linkup-Chat")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(sanitized).md")
        try? md.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Exports transcript to a temporary .pdf file and returns its URL.
    static func exportPDFFile(transcript: Transcript, title: String?) -> URL {
        let sanitized = sanitizeFilename(title ?? "Linkup-Chat")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(sanitized).pdf")
        ChatPDFRenderer.renderPDF(transcript: transcript, title: title, to: url)
        return url
    }

    private static func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let components = name.components(separatedBy: invalid)
        let filtered = components.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return filtered.isEmpty ? "Linkup-Chat" : filtered
    }
}

/// Renders transcript into a formatted multi-page PDF document using UIGraphicsPDFRenderer.
enum ChatPDFRenderer {
    static func renderPDF(transcript: Transcript, title: String?, to fileURL: URL) {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let margin: CGFloat = 48
        let printableWidth = pageWidth - (margin * 2)

        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let titleFont = UIFont.boldSystemFont(ofSize: 20)
        let subtitleFont = UIFont.systemFont(ofSize: 11)
        let roleFont = UIFont.systemFont(ofSize: 11, weight: .bold)
        let bodyFont = UIFont.systemFont(ofSize: 12)
        let toolFont = UIFont.italicSystemFont(ofSize: 11)
        let footerFont = UIFont.systemFont(ofSize: 9)

        let titleColor = UIColor(red: 0x1F / 255, green: 0x1E / 255, blue: 0x1D / 255, alpha: 1.0)
        let secondaryColor = UIColor(red: 0x73 / 255, green: 0x71 / 255, blue: 0x6B / 255, alpha: 1.0)
        let bodyColor = UIColor(red: 0x26 / 255, green: 0x26 / 255, blue: 0x24 / 255, alpha: 1.0)
        let accentColor = UIColor(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1.0)
        let hairlineColor = UIColor(white: 0.85, alpha: 1.0)

        try? renderer.writePDF(to: fileURL) { context in
            var pageNumber = 1
            var currentY = margin

            func startNewPage() {
                context.beginPage()
                currentY = margin

                // Footer with page number
                let footerText = "Linkup · Page \(pageNumber)"
                let footerAttrs: [NSAttributedString.Key: Any] = [
                    .font: footerFont,
                    .foregroundColor: secondaryColor
                ]
                let footerStr = NSAttributedString(string: footerText, attributes: footerAttrs)
                footerStr.draw(at: CGPoint(x: margin, y: pageHeight - margin + 14))
                pageNumber += 1
            }

            func checkSpace(needed: CGFloat) {
                if currentY + needed > pageHeight - margin - 20 {
                    startNewPage()
                }
            }

            startNewPage()

            // Header title
            let heading = title?.isEmpty == false ? title! : "Linkup Conversation"
            let titleString = NSAttributedString(string: heading, attributes: [
                .font: titleFont,
                .foregroundColor: titleColor
            ])
            let titleRect = titleString.boundingRect(
                with: CGSize(width: printableWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            titleString.draw(in: CGRect(x: margin, y: currentY, width: printableWidth, height: titleRect.height))
            currentY += titleRect.height + 6

            // Date exported
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            let dateStr = NSAttributedString(string: "Exported on \(dateFormatter.string(from: Date()))", attributes: [
                .font: subtitleFont,
                .foregroundColor: secondaryColor
            ])
            dateStr.draw(at: CGPoint(x: margin, y: currentY))
            currentY += 20

            // Hairline divider
            let path = UIBezierPath()
            path.move(to: CGPoint(x: margin, y: currentY))
            path.addLine(to: CGPoint(x: pageWidth - margin, y: currentY))
            hairlineColor.setStroke()
            path.lineWidth = 1
            path.stroke()
            currentY += 16

            // Items
            for item in transcript.items {
                switch item {
                case .user(let user):
                    checkSpace(needed: 36)
                    let userHeader = NSAttributedString(string: "USER", attributes: [
                        .font: roleFont,
                        .foregroundColor: secondaryColor
                    ])
                    userHeader.draw(at: CGPoint(x: margin, y: currentY))
                    currentY += 16

                    if !user.text.isEmpty {
                        drawParagraphs(user.text, font: bodyFont, color: bodyColor, width: printableWidth, checkSpace: checkSpace, currentY: &currentY, margin: margin)
                    }

                    for att in user.attachments {
                        checkSpace(needed: 18)
                        let attStr = NSAttributedString(string: "📎 Attachment: \(att.name)", attributes: [
                            .font: subtitleFont,
                            .foregroundColor: secondaryColor
                        ])
                        attStr.draw(at: CGPoint(x: margin + 8, y: currentY))
                        currentY += 16
                    }
                    currentY += 12

                case .assistant(let turn):
                    checkSpace(needed: 36)
                    let agentHeader = NSAttributedString(string: "ASSISTANT", attributes: [
                        .font: roleFont,
                        .foregroundColor: accentColor
                    ])
                    agentHeader.draw(at: CGPoint(x: margin, y: currentY))
                    currentY += 16

                    for part in turn.parts {
                        switch part {
                        case .tool(let tool):
                            checkSpace(needed: 20)
                            let toolTitle = tool.presentation.doneTitle.isEmpty ? tool.name : tool.presentation.doneTitle
                            let toolStr = NSAttributedString(string: "> Used \(toolTitle)", attributes: [
                                .font: toolFont,
                                .foregroundColor: secondaryColor
                            ])
                            toolStr.draw(at: CGPoint(x: margin + 8, y: currentY))
                            currentY += 18

                        case .text(let block):
                            guard !block.text.isEmpty else { break }
                            drawParagraphs(block.text, font: bodyFont, color: bodyColor, width: printableWidth, checkSpace: checkSpace, currentY: &currentY, margin: margin)

                        case .error(_, let msg):
                            checkSpace(needed: 20)
                            let errStr = NSAttributedString(string: "⚠️ Error: \(msg)", attributes: [
                                .font: bodyFont,
                                .foregroundColor: UIColor(red: 0xE5 / 255, green: 0x5B / 255, blue: 0x4F / 255, alpha: 1)
                            ])
                            errStr.draw(at: CGPoint(x: margin, y: currentY))
                            currentY += 18

                        default:
                            break
                        }
                    }
                    currentY += 14
                }
            }
        }
    }

    private static func drawParagraphs(
        _ text: String,
        font: UIFont,
        color: UIColor,
        width: CGFloat,
        checkSpace: (CGFloat) -> Void,
        currentY: inout CGFloat,
        margin: CGFloat
    ) {
        let paragraphs = text.components(separatedBy: "\n\n")
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = 3

        for para in paragraphs {
            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let attrString = NSAttributedString(string: trimmed, attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paraStyle
            ])

            let rect = attrString.boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )

            if rect.height < 500 {
                checkSpace(rect.height + 8)
                attrString.draw(in: CGRect(x: margin, y: currentY, width: width, height: rect.height))
                currentY += rect.height + 8
            } else {
                let sublines = trimmed.components(separatedBy: "\n")
                for subline in sublines {
                    guard !subline.isEmpty else {
                        currentY += 6
                        continue
                    }
                    let subAttr = NSAttributedString(string: subline, attributes: [
                        .font: font,
                        .foregroundColor: color,
                        .paragraphStyle: paraStyle
                    ])
                    let subRect = subAttr.boundingRect(
                        with: CGSize(width: width, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    )
                    checkSpace(subRect.height + 4)
                    subAttr.draw(in: CGRect(x: margin, y: currentY, width: width, height: subRect.height))
                    currentY += subRect.height + 4
                }
                currentY += 6
            }
        }
    }
}
