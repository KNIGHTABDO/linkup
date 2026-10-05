"""Slash commands and skills discovery for Antigravity (agy) and Hermes.

Provides agy_commands() and hermes_commands() returning:
[{"name": "<name without slash>", "description": "...", "kind": "command"|"skill"|"agent"|"plugin"}]
deduplicated by name, sorted (commands, then skills, agents, plugins; then by name), max 300.
Results are cached for 10 minutes.
"""
from __future__ import annotations

import ast
import asyncio
import glob
import logging
import os
import re
import select
import time

log = logging.getLogger("linkup.commands")

CACHE_TTL = 600.0  # 10 minutes
KIND_ORDER = {"command": 0, "skill": 1, "agent": 2, "plugin": 3}

_AGY_CACHE: list[dict] | None = None
_AGY_CACHE_AT: float = 0.0

_HERMES_CACHE: list[dict] | None = None
_HERMES_CACHE_AT: float = 0.0

# Real built-in slash commands discovered from agy Go binary (google3/third_party/jetski/cli/commands)
# and live TUI slash popup. Verified and non-invented.
REAL_AGY_TUI_COMMANDS: dict[str, str] = {
    "add-dir": "Add a directory to the workspace",
    "agents": "List available custom agents",
    "artifact": "View and review artifacts",
    "boost": "Invoke the Boost multi-agent orchestrator for complex tasks.",
    "browser": "Invoke a browser agent for web tasks.",
    "btw": "Ask a side question without interrupting the current task",
    "changelog": "Show release notes and changes",
    "clear": "Clear conversation and start a new one",
    "codesearch": "Search code in the workspace (usage: /codesearch <query>)",
    "config": "Open settings panel",
    "context": "Visualize current context usage",
    "copy": "Copy the last planner response to the clipboard, the n-th with '/copy n', or the /btw answer with '/copy btw'",
    "diff": "View uncommitted changes and per-turn diffs",
    "effort": "Set the reasoning effort",
    "exit": "Exit the CLI",
    "feedback": "Submit qualitative feedback to improve the agent",
    "fork": "Create a branch of the current conversation at this point, optionally specifying a project ID to fork into",
    "goal": "Run until the specified goal is completely finished.",
    "grill-me": "Interview me to align on a plan.",
    "help": "Show available commands and keybindings",
    "hooks": "Manage hook configurations for tool events",
    "install": "Configure environment paths and shell settings",
    "keybindings": "Set custom keybindings",
    "learn": "Reflect on recent successes or corrections to capture reusable skills or rules.",
    "logout": "Log out",
    "mcp": "Manage MCP servers",
    "mic-serve": "Serve this machine's microphone to a CLI on another host",
    "model": "Set a model, or run a single prompt on another model",
    "models": "List available models",
    "open": "Open a file or view opened/edited files",
    "permissions": "Manage tool permissions",
    "plan": "Plan carefully before executing a task.",
    "plugin": "Manage plugins (install, uninstall, list, enable, disable)",
    "remote-control": "Turn on remote control for this session (off to disable)",
    "rename": "Rename the current conversation",
    "resume": "Browse and resume past conversations",
    "rewind": "Rewind conversation to a previous message",
    "schedule": "Run an instruction on a recurring schedule or as a one-time timer.",
    "skills": "List available skills",
    "statusline": "Toggle the statusline",
    "tasks": "View background tasks",
    "teamwork-preview": "Invoke a team of agents to autonomously tackle large projects.",
    "title": "Toggle custom terminal window title",
    "update": "Update CLI",
    "usage": "View model quota usage",
    "voice": "Dictate a prompt using your microphone",
}


def _parse_frontmatter(content: str) -> tuple[str | None, str | None]:
    """Extract name and description from YAML frontmatter in SKILL.md.

    Supports single-line quoted/unquoted strings and multiline block scalars (>- / > / |- / |).
    """
    if not content.startswith("---"):
        return None, None
    parts = content.split("---", 2)
    if len(parts) < 3:
        return None, None
    fm_lines = parts[1].splitlines()
    name: str | None = None
    desc: str | None = None
    i = 0
    while i < len(fm_lines):
        line = fm_lines[i]
        sline = line.strip()
        if sline.startswith("name:"):
            val = line.split("name:", 1)[1].strip()
            name = val.strip("'\"")
            i += 1
            continue
        if sline.startswith("description:"):
            val = line.split("description:", 1)[1].strip()
            if val in (">-", ">", "|-", "|"):
                i += 1
                desc_lines: list[str] = []
                while i < len(fm_lines):
                    curr = fm_lines[i]
                    if curr.startswith(" ") or curr.startswith("\t"):
                        desc_lines.append(curr.strip())
                        i += 1
                    elif not curr.strip():
                        i += 1
                    else:
                        break
                desc = " ".join(desc_lines).strip()
                continue
            else:
                desc = val.strip("'\"")
                i += 1
                continue
        i += 1
    return name, desc


def _dedup_and_sort(items: list[dict], max_items: int = 300) -> list[dict]:
    """Deduplicate by name without slash and sort (commands, skills, agents, plugins; then by name)."""
    best_by_name: dict[str, dict] = {}
    for item in items:
        raw_name = item.get("name") or ""
        name = raw_name.lstrip("/")
        if not name:
            continue
        desc = (item.get("description") or "").strip()
        kind = item.get("kind", "command")
        if kind not in KIND_ORDER:
            kind = "command"
        normalized = {"name": name, "description": desc, "kind": kind}

        if name not in best_by_name:
            best_by_name[name] = normalized
        else:
            existing = best_by_name[name]
            curr_order = KIND_ORDER.get(kind, 99)
            exist_order = KIND_ORDER.get(existing["kind"], 99)
            if curr_order < exist_order:
                best_by_name[name] = normalized
            elif curr_order == exist_order and len(desc) > len(existing.get("description") or ""):
                best_by_name[name] = normalized

    sorted_items = sorted(
        best_by_name.values(),
        key=lambda x: (KIND_ORDER.get(x["kind"], 99), x["name"].lower()),
    )
    return sorted_items[:max_items]


def _read_skills_from_dirs(directories: list[str]) -> list[dict]:
    """Scan directories for SKILL.md files and parse frontmatter."""
    skills: list[dict] = []
    seen_paths: set[str] = set()
    for root in directories:
        pattern = os.path.join(os.path.expanduser(root), "**", "SKILL.md")
        for path in glob.glob(pattern, recursive=True):
            canon = os.path.realpath(path)
            if canon in seen_paths or not os.path.isfile(canon):
                continue
            seen_paths.add(canon)
            try:
                with open(canon, encoding="utf-8", errors="replace") as f:
                    content = f.read()
                name, desc = _parse_frontmatter(content)
                if not name:
                    name = os.path.basename(os.path.dirname(canon))
                skills.append({"name": name, "description": desc or "", "kind": "skill"})
            except OSError as exc:
                log.debug("failed reading skill %s: %s", canon, exc)
    return skills


def _probe_agy_tui_pty(timeout_sec: float = 3.0) -> dict[str, str]:
    """Attempt a fast pty probe of agy to discover live slash menu commands."""
    try:
        import fcntl
        import pty
        import struct
        import termios

        agy_bin = os.environ.get("LINKUP_AGY", "agy")
        master, slave = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.close(master)
            os.setsid()
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            try:
                fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 140, 0, 0))
            except OSError:
                pass
            os.environ["TERM"] = "xterm-256color"
            os.execvp(agy_bin, [agy_bin])
        else:
            os.close(slave)
            found: dict[str, str] = {}
            start = time.time()
            try:
                time.sleep(1.2)
                os.write(master, b"\r")  # confirm workspace trust if prompted
                time.sleep(1.0)
                os.write(master, b"/")   # trigger slash menu
                time.sleep(0.3)
                while time.time() - start < timeout_sec:
                    r, _, _ = select.select([master], [], [], 0.2)
                    if not r:
                        break
                    raw = os.read(master, 16384)
                    if not raw:
                        break
                    clean = re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", " ", raw.decode("utf-8", errors="ignore"))
                    for line in clean.splitlines():
                        m = re.search(r"(/[-a-zA-Z0-9]+)\s{2,}(.+)", line.strip())
                        if m:
                            name = m.group(1).lstrip("/")
                            desc = m.group(2).strip()
                            if not desc.startswith("more") and not name.startswith("/"):
                                found[name] = desc
            finally:
                try:
                    os.kill(pid, 9)
                    os.waitpid(pid, 0)
                except OSError:
                    pass
                try:
                    os.close(master)
                except OSError:
                    pass
            return found
    except Exception as exc:
        log.debug("agy pty probe failed or skipped: %s", exc)
        return {}


async def _run_cmd_capture(args: list[str], timeout: float = 6.0) -> str:
    """Execute a CLI command safely and return stdout."""
    try:
        proc = await asyncio.create_subprocess_exec(
            *args,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout)
        return stdout.decode(errors="replace")
    except Exception as exc:
        log.debug("command %s failed: %s", args, exc)
        return ""


async def agy_commands() -> list[dict]:
    """[{"name", "description", "kind": "command" | "skill" | "agent" | "plugin"}]"""
    global _AGY_CACHE, _AGY_CACHE_AT

    now = time.time()
    if _AGY_CACHE is not None and (now - _AGY_CACHE_AT) < CACHE_TTL:
        return list(_AGY_CACHE)

    items: list[dict] = []
    agy_bin = os.environ.get("LINKUP_AGY", "agy")

    # 1. Base verified built-in TUI commands
    for name, desc in REAL_AGY_TUI_COMMANDS.items():
        items.append({"name": name, "description": desc, "kind": "command"})

    # 2. Probe live TUI in pty (fast off-thread execution with 3.5s timeout)
    try:
        live_tui = await asyncio.wait_for(
            asyncio.to_thread(_probe_agy_tui_pty, 3.5),
            timeout=5.0,
        )
        for name, desc in live_tui.items():
            items.append({"name": name, "description": desc, "kind": "command"})
    except Exception as exc:
        log.debug("agy live pty discovery skipped: %s", exc)

    # 3. Skills from ~/.gemini directories and SKILL.md files
    gemini_skill_dirs = [
        "~/.gemini/antigravity-cli/builtin/skills",
        "~/.gemini/antigravity/builtin/skills",
        "~/.gemini/skills",
        "~/.gemini/customizations/skills",
    ]
    try:
        skills = await asyncio.to_thread(_read_skills_from_dirs, gemini_skill_dirs)
        items.extend(skills)
    except Exception as exc:
        log.warning("failed scanning gemini skills: %s", exc)

    # 4. Explore CLI: agy --help, agy agents, agy plugin list, agy mcp list
    try:
        help_out, agents_out, plugin_out, mcp_out = await asyncio.gather(
            _run_cmd_capture([agy_bin, "--help"], timeout=5.0),
            _run_cmd_capture([agy_bin, "agents"], timeout=5.0),
            _run_cmd_capture([agy_bin, "plugin", "list"], timeout=5.0),
            _run_cmd_capture([agy_bin, "mcp", "list"], timeout=5.0),
            return_exceptions=True,
        )

        # Parse subcommands from agy --help
        if isinstance(help_out, str):
            in_subcommands = False
            for line in help_out.splitlines():
                if "Available subcommands:" in line:
                    in_subcommands = True
                    continue
                if in_subcommands:
                    m = re.match(r"^\s+([a-zA-Z0-9_-]+)\s{2,}(.+)", line)
                    if m:
                        subcmd, sdesc = m.group(1).strip(), m.group(2).strip()
                        items.append({"name": subcmd, "description": sdesc, "kind": "command"})

        # Parse agents from agy agents
        if isinstance(agents_out, str):
            for line in agents_out.splitlines():
                line = line.strip()
                if line and not line.lower().startswith(("fetching", "available", "usage")):
                    items.append({"name": line, "description": "Custom agent", "kind": "agent"})

        # Parse plugins from agy plugin list
        if isinstance(plugin_out, str):
            for line in plugin_out.splitlines():
                line = line.strip()
                if line and not line.lower().startswith(("no imported", "fetching", "usage", "available")):
                    p_name = line.split()[0]
                    items.append({"name": p_name, "description": "Imported plugin", "kind": "plugin"})

        # Parse mcp servers from agy mcp list
        if isinstance(mcp_out, str):
            for line in mcp_out.splitlines():
                line = line.strip()
                if line and not line.lower().startswith(("no mcp", "configured", "fetching", "usage")):
                    mcp_name = line.split()[0]
                    items.append({"name": mcp_name, "description": "Configured MCP server", "kind": "plugin"})
    except Exception as exc:
        log.warning("agy CLI discovery failed: %s", exc)

    # 5. Check plugin directories under ~/.gemini/config/plugins
    plugins_dir = os.path.expanduser("~/.gemini/config/plugins")
    if os.path.isdir(plugins_dir):
        try:
            for entry in os.listdir(plugins_dir):
                if not entry.startswith("."):
                    items.append({"name": entry, "description": "Configured plugin", "kind": "plugin"})
        except OSError:
            pass

    out = _dedup_and_sort(items, max_items=300)
    _AGY_CACHE = out
    _AGY_CACHE_AT = time.time()
    return list(out)


def _read_hermes_skills() -> list[dict]:
    """Scan ~/.hermes/skills/**/SKILL.md and parse frontmatter."""
    skills: list[dict] = []
    pattern = os.path.expanduser("~/.hermes/skills/**/SKILL.md")
    for path in glob.glob(pattern, recursive=True):
        if not os.path.isfile(path):
            continue
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                content = f.read()
            name, desc = _parse_frontmatter(content)
            if not name:
                name = os.path.basename(os.path.dirname(path))
            skills.append({"name": name, "description": desc or "", "kind": "skill"})
        except OSError as exc:
            log.debug("failed reading hermes skill %s: %s", path, exc)
    return skills


def _read_hermes_gateway_commands() -> list[dict]:
    """Extract gateway slash commands from ~/.hermes/hermes-agent/hermes_cli/commands.py."""
    commands_py = os.path.expanduser("~/.hermes/hermes-agent/hermes_cli/commands.py")
    results: list[dict] = []

    if os.path.isfile(commands_py):
        try:
            with open(commands_py, encoding="utf-8", errors="replace") as f:
                tree = ast.parse(f.read(), filename=commands_py)

            for node in tree.body:
                if isinstance(node, (ast.Assign, ast.AnnAssign)):
                    target = node.target if isinstance(node, ast.AnnAssign) else (node.targets[0] if node.targets else None)
                    if isinstance(target, ast.Name) and target.id == "COMMAND_REGISTRY":
                        val = node.value
                        if isinstance(val, ast.List):
                            for elt in val.elts:
                                if not isinstance(elt, ast.Call):
                                    continue
                                name = elt.args[0].value if len(elt.args) > 0 and isinstance(elt.args[0], ast.Constant) else None
                                desc = elt.args[1].value if len(elt.args) > 1 and isinstance(elt.args[1], ast.Constant) else ""
                                kw = {k.arg: k.value.value if isinstance(k.value, ast.Constant) else None for k in elt.keywords}
                                cli_only = bool(kw.get("cli_only"))
                                gate = kw.get("gateway_config_gate")
                                # In Hermes, commands dispatched by the gateway are those not cli_only or with gateway_config_gate
                                if name and (not cli_only or gate):
                                    results.append({"name": str(name), "description": str(desc or ""), "kind": "command"})
        except Exception as exc:
            log.warning("failed parsing hermes COMMAND_REGISTRY: %s", exc)

    # Fallback to desktop slash registry if commands.py was empty or failed
    if not results:
        desktop_reg = os.path.expanduser("~/.hermes/hermes-agent/apps/desktop/src/lib/desktop-slash-registry.json")
        if os.path.isfile(desktop_reg):
            try:
                import json
                with open(desktop_reg, encoding="utf-8") as f:
                    reg = json.load(f)
                for cmd_name, disp in reg.items():
                    if disp != "terminal":
                        clean_name = cmd_name.lstrip("/")
                        results.append({"name": clean_name, "description": f"Hermes command /{clean_name}", "kind": "command"})
            except Exception as exc:
                log.debug("failed reading desktop registry: %s", exc)

    return results


def hermes_commands() -> list[dict]:
    """[{"name", "description", "kind": "command" | "skill" | "agent" | "plugin"}]"""
    global _HERMES_CACHE, _HERMES_CACHE_AT

    now = time.time()
    if _HERMES_CACHE is not None and (now - _HERMES_CACHE_AT) < CACHE_TTL:
        return list(_HERMES_CACHE)

    items: list[dict] = []

    # 1. Gateway slash commands from hermes-agent source
    gw_cmds = _read_hermes_gateway_commands()
    items.extend(gw_cmds)

    # 2. Skills under ~/.hermes/skills/**/SKILL.md
    skills = _read_hermes_skills()
    items.extend(skills)

    out = _dedup_and_sort(items, max_items=300)
    _HERMES_CACHE = out
    _HERMES_CACHE_AT = time.time()
    return list(out)
