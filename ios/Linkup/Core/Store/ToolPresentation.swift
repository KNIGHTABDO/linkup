import Foundation

/// How a tool call reads in the UI ("Viewing file", "Running command" …) for every agent's tool names.
@MainActor
struct ToolPresentation {
    let tool: ToolCall

    private var key: String { tool.name.lowercased() }

    var symbol: String {
        switch key {
        case "read", "view_file", "read_file", "notebookread": "doc.text"
        case "write", "write_to_file", "create_file": "doc.badge.plus"
        case "edit", "multiedit", "replace_file_content", "multi_replace_file_content", "notebookedit": "pencil"
        case "bash", "run_command", "terminal", "shell", "execute_code", "bashoutput": "terminal"
        case "grep", "glob", "search_files", "grep_search", "find_by_name", "list_dir", "ls": "magnifyingglass"
        case "websearch", "search_web", "web_search": "globe"
        case "webfetch", "read_url_content", "fetch", "web_extract": "safari"
        case "task", "agent", "browser_subagent", "delegate_task": "person.2"
        case "todowrite", "update_plan", "todo": "checklist"
        case "generate_image", "image_generate", "create_image": "photo.badge.plus"
        case "skill": "book"
        case "memory", "recall": "brain"
        default: key.hasPrefix("browser") ? "macwindow" : (key.hasPrefix("mcp") ? "puzzlepiece.extension" : "wrench.and.screwdriver")
        }
    }

    private var verb: (active: String, done: String) {
        switch key {
        case "read", "view_file", "read_file", "notebookread": ("Viewing file", "Viewed file")
        case "write", "write_to_file", "create_file": ("Creating file", "Created file")
        case "edit", "multiedit", "replace_file_content", "multi_replace_file_content", "notebookedit": ("Editing file", "Edited file")
        case "bash", "run_command", "terminal", "shell", "execute_code": ("Running command", "Ran command")
        case "grep", "grep_search", "search_files": ("Searching code", "Searched code")
        case "glob", "find_by_name", "list_dir", "ls": ("Looking for files", "Found files")
        case "websearch", "search_web", "web_search": ("Searching the web", "Searched the web")
        case "webfetch", "read_url_content", "fetch", "web_extract": ("Reading page", "Read page")
        case "task", "agent", "browser_subagent", "delegate_task": ("Running agent", "Ran agent")
        case "todowrite", "update_plan", "todo": ("Updating plan", "Updated plan")
        case "generate_image", "image_generate", "create_image": ("Creating image", "Created image")
        case "skill": ("Reading skill", "Read skill")
        case "memory", "recall": ("Recalling memory", "Recalled memory")
        default:
            let words = tool.name.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "mcp  ", with: "")
            return ("Using \(words)", "Used \(words)")
        }
    }

    var activeTitle: String { verb.active }
    var doneTitle: String { tool.isError ? "\(verb.active.replacingOccurrences(of: "ing", with: "")) failed" : verb.done }

    /// The most telling piece of the input: a file name, the command, the query, the URL…
    var detail: String? {
        let input = tool.input
        for k in ["description", "file_path", "path", "AbsolutePath", "TargetFile", "command", "CommandLine", "pattern",
                  "query", "Query", "url", "Url", "prompt", "skill", "preview", "SearchPath"] {
            if let v = input[k]?.string, !v.isEmpty {
                let isPath = k.lowercased().contains("path") || k == "TargetFile"
                return isPath ? URL(fileURLWithPath: v).lastPathComponent : String(v.prefix(160))
            }
        }
        return nil
    }

    /// "Created file · index.html"
    var title: String {
        let base = tool.isRunning ? activeTitle : doneTitle
        return detail.map { "\(base) \u{00B7} \($0)" } ?? base
    }
}
