import SwiftUI
import UIKit

/// Code and file viewer:
/// - Text files: line-numbered, mono, horizontally scrollable with syntax highlighting (first 3000 lines)
/// - Markdown: rendered via `MarkdownView`
/// - Images/PDF/HTML: presented in `ArtifactViewer` via `ui.openArtifact`
/// - Binary: "Can't preview this file"
struct FileViewer: View {
    let path: String

    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss

    @State private var content: FileContent?
    @State private var isLoading = true
    @State private var errorMessage: String?

    // Code lines prepared for fast scrolling
    @State private var codeLines: [PreparedCodeLine] = []

    // Search state
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var matchingLineNumbers: [Int] = []
    @State private var currentMatchIndex = 0

    private struct PreparedCodeLine: Identifiable {
        let number: Int
        let attributed: AttributedString
        let plain: String
        var id: Int { number }
    }

    private var filename: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private var fileExtension: String {
        URL(fileURLWithPath: path).pathExtension.lowercased()
    }

    private var isMarkdown: Bool {
        fileExtension == "md" || fileExtension == "markdown" || content?.language == "markdown"
    }

    private var mediaKind: String? {
        if ["png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "ico"].contains(fileExtension) {
            return "image"
        }
        if fileExtension == "pdf" {
            return "pdf"
        }
        if ["html", "htm"].contains(fileExtension) {
            return "html"
        }
        return nil
    }

    private var gutterWidth: CGFloat {
        let digits = max(2, String(codeLines.count).count)
        return CGFloat(digits * 9 + 10)
    }

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(Theme.accent)
                    .scaleEffect(1.2)
            } else if let error = errorMessage {
                errorView(error)
            } else if let content {
                mainContentView(content)
            }
        }
        .navigationTitle(filename)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            toolbarItems
        }
        .task {
            await loadFile()
        }
    }

    // MARK: - Main Content Switcher

    @ViewBuilder
    private func mainContentView(_ file: FileContent) -> some View {
        VStack(spacing: 0) {
            if isSearching {
                searchBarOverlay
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if file.truncated == true {
                truncatedNotice
            }

            if let url = file.url, let kind = mediaKind {
                mediaArtifactPreview(url: url, kind: kind, size: file.size)
            } else if isMarkdown, let text = file.text {
                markdownContentView(text)
            } else if let text = file.text {
                codeEditorView(text: text)
            } else {
                binaryPlaceholderView(size: file.size)
            }
        }
        .animation(.smooth(duration: 0.2), value: isSearching)
    }

    // MARK: - Code Editor View (Mono, line-numbered, horizontally scrollable)

    private func codeEditorView(text: String) -> some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(codeLines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(line.number)")
                                .font(Theme.mono(12))
                                .foregroundStyle(
                                    isLineHighlighted(line.number) ? Theme.accent : Theme.tertiaryText
                                )
                                .frame(width: gutterWidth, alignment: .trailing)

                            lineTextView(for: line)
                        }
                        .id(line.number)
                        .background(
                            isLineCurrentMatch(line.number) ? Theme.accent.opacity(0.18) : Color.clear
                        )
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
            }
            .onChange(of: currentMatchIndex) { _, newIndex in
                if !matchingLineNumbers.isEmpty && newIndex >= 0 && newIndex < matchingLineNumbers.count {
                    let target = matchingLineNumbers[newIndex]
                    withAnimation(.snappy(duration: 0.2)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func lineTextView(for line: PreparedCodeLine) -> some View {
        if !searchText.isEmpty && line.plain.localizedCaseInsensitiveContains(searchText) {
            highlightedSearchLine(line)
        } else {
            Text(line.attributed)
                .font(Theme.mono(13))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func highlightedSearchLine(_ line: PreparedCodeLine) -> some View {
        let plain = line.plain
        var attributed = AttributedString(plain)
        attributed.font = Theme.mono(13)
        attributed.foregroundColor = Theme.text

        // Apply search background highlight
        var searchRange = plain.startIndex..<plain.endIndex
        while let matchRange = plain.range(of: searchText, options: .caseInsensitive, range: searchRange) {
            if let attrRange = Range(matchRange, in: attributed) {
                attributed[attrRange].backgroundColor = Theme.accent.opacity(0.4)
                attributed[attrRange].foregroundColor = .white
            }
            searchRange = matchRange.upperBound..<plain.endIndex
        }

        return Text(attributed)
            .font(Theme.mono(13))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Markdown Content View

    private func markdownContentView(_ text: String) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                MarkdownView(text: text)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Media Preview (Image, PDF, HTML)

    private func mediaArtifactPreview(url: String, kind: String, size: Int?) -> some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Theme.surface)
                    .frame(width: 96, height: 96)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Theme.hairline, lineWidth: 1)
                    )

                Image(systemName: WorkspaceFormatters.fileIcon(for: filename, isDir: false))
                    .font(.system(size: 42))
                    .foregroundStyle(Theme.accent)
            }

            VStack(spacing: 6) {
                Text(filename)
                    .font(Theme.sans(20, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                HStack(spacing: 8) {
                    Text(kind.uppercased())
                        .font(Theme.sans(12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.accent.opacity(0.14), in: Capsule())

                    if let size {
                        Text(WorkspaceFormatters.fileSize(size))
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }

            Button {
                openInArtifactViewer(url: url, kind: kind, size: size)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 16, weight: .medium))
                    Text("Open in Artifact Viewer")
                        .font(Theme.sans(16, weight: .semibold))
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
            }
            .buttonStyle(.glassProminent)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            openInArtifactViewer(url: url, kind: kind, size: size)
        }
    }

    private func openInArtifactViewer(url: String, kind: String, size: Int?) {
        ui.openArtifact = ArtifactRef(
            id: url,
            kind: kind,
            title: filename,
            url: url,
            path: path,
            mime: nil,
            size: size
        )
    }

    // MARK: - Binary Placeholder View

    private func binaryPlaceholderView(size: Int?) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 52))
                .foregroundStyle(Theme.tertiaryText)

            Text("Can\u{2019}t preview this file")
                .font(Theme.sans(19, weight: .semibold))
                .foregroundStyle(Theme.text)

            VStack(spacing: 4) {
                Text(filename)
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.secondaryText)

                if let size {
                    Text(WorkspaceFormatters.fileSize(size))
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Theme.danger)

            Text(error)
                .font(Theme.sans(15))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                Task { await loadFile() }
            } label: {
                Text("Retry")
                    .font(Theme.sans(15, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Truncated Banner

    private var truncatedNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.accent)

            Text("File is truncated (showing first 2 MB)")
                .font(Theme.sans(12))
                .foregroundStyle(Theme.text)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.surface)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.hairline), alignment: .bottom)
    }

    // MARK: - Search Overlay

    private var searchBarOverlay: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)

            TextField("Search in file…", text: $searchText)
                .font(Theme.sans(15))
                .foregroundStyle(Theme.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: searchText) { _, newQuery in
                    updateSearch(query: newQuery)
                }

            if !searchText.isEmpty {
                Text(matchCountLabel)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.secondaryText)

                Button {
                    goToPreviousMatch()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(matchingLineNumbers.isEmpty ? Theme.tertiaryText : Theme.text)
                }
                .disabled(matchingLineNumbers.isEmpty)

                Button {
                    goToNextMatch()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(matchingLineNumbers.isEmpty ? Theme.tertiaryText : Theme.text)
                }
                .disabled(matchingLineNumbers.isEmpty)
            }

            Button {
                isSearching = false
                searchText = ""
                matchingLineNumbers = []
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Theme.surface)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.hairline), alignment: .bottom)
    }

    private var matchCountLabel: String {
        if matchingLineNumbers.isEmpty {
            return "0 matches"
        }
        return "\(currentMatchIndex + 1)/\(matchingLineNumbers.count)"
    }

    private func updateSearch(query: String) {
        guard !query.isEmpty else {
            matchingLineNumbers = []
            currentMatchIndex = 0
            return
        }
        matchingLineNumbers = codeLines.filter {
            $0.plain.localizedCaseInsensitiveContains(query)
        }.map(\.number)
        currentMatchIndex = 0
    }

    private func goToNextMatch() {
        guard !matchingLineNumbers.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matchingLineNumbers.count
    }

    private func goToPreviousMatch() {
        guard !matchingLineNumbers.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matchingLineNumbers.count) % matchingLineNumbers.count
    }

    private func isLineHighlighted(_ lineNumber: Int) -> Bool {
        matchingLineNumbers.contains(lineNumber)
    }

    private func isLineCurrentMatch(_ lineNumber: Int) -> Bool {
        guard !matchingLineNumbers.isEmpty, currentMatchIndex < matchingLineNumbers.count else { return false }
        return matchingLineNumbers[currentMatchIndex] == lineNumber
    }

    // MARK: - Toolbar Items

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if content?.text != nil && !isMarkdown {
                Button {
                    isSearching.toggle()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(isSearching ? Theme.accent : Theme.text)
                }
                .accessibilityLabel("Search within file")
            }

            if let text = content?.text {
                Button {
                    UIPasteboard.general.string = text
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    ui.toast = "Copied to clipboard"
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.text)
                }
                .accessibilityLabel("Copy file content")

                ShareLink(item: text) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.text)
                }
                .accessibilityLabel("Share file")
            }
        }
    }

    // MARK: - Data Loading

    private func loadFile() async {
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await store.readFile(path)
            content = loaded

            if let text = loaded.text {
                let language = WorkspaceLanguage.detect(path: path, languageHint: loaded.language)
                prepareCodeLines(text: text, language: language)
            }
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    private func prepareCodeLines(text: String, language: WorkspaceLanguage) {
        let rawLines = text.components(separatedBy: "\n")
        var prepared: [PreparedCodeLine] = []
        prepared.reserveCapacity(rawLines.count)

        // Highlight only the first 3000 lines as per requirements
        let highlightLimit = min(3000, rawLines.count)

        for i in 0..<highlightLimit {
            let line = rawLines[i]
            let attributed = WorkspaceSyntaxHighlighter.highlight(line: line, language: language)
            prepared.append(PreparedCodeLine(number: i + 1, attributed: attributed, plain: line))
        }

        // Remaining lines are kept plain for speed
        if rawLines.count > highlightLimit {
            for i in highlightLimit..<rawLines.count {
                let line = rawLines[i]
                var plainAttr = AttributedString(line)
                plainAttr.foregroundColor = Theme.text
                prepared.append(PreparedCodeLine(number: i + 1, attributed: plainAttr, plain: line))
            }
        }

        codeLines = prepared
    }
}
