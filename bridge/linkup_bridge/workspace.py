"""Linkup bridge: projects, files, git, GitHub Actions and dev-server proxy."""
from __future__ import annotations

import asyncio
from datetime import datetime
import json
import os
import re
import shutil
import subprocess

from aiohttp import ClientConnectorError, ClientSession, WSMsgType, web

PROJECTS = os.path.expanduser(os.environ.get("LINKUP_PROJECTS", "~/Desktop/projects"))
SKIP_NAMES = {".git", "node_modules", ".build", "build", "__pycache__", ".DS_Store"}
MAX_TEXT_SIZE = 2 * 1024 * 1024  # 2 MB
MAX_DIFF_SIZE = 400 * 1024  # 400 KB
MEDIA_URL_EXTS = {
    # Images
    "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "ico", "bmp", "tiff",
    # PDF
    "pdf",
    # HTML
    "html", "htm",
    # Video
    "mp4", "mov", "webm", "mkv", "avi", "m4v",
}
HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
}


def allowed(path: str) -> bool:
    """Only paths inside the user's home directory (or LINKUP_PROJECTS) are reachable from the phone."""
    p = os.path.realpath(os.path.expanduser(path))
    home = os.path.realpath(os.path.expanduser("~"))
    if p == home or p.startswith(home + os.sep):
        return True
    proj = os.path.realpath(os.path.expanduser(os.environ.get("LINKUP_PROJECTS", "~/Desktop/projects")))
    if p == proj or p.startswith(proj + os.sep):
        return True
    return False


def create_project(name: str, git: bool, readme: bool, template: str | None) -> dict:
    """Creates PROJECTS/<name> (+ git init / README / template); returns {"name", "path"}."""
    clean = name.strip()
    clean = clean.replace(" ", "-")
    clean = re.sub(r"[^a-zA-Z0-9_\-]", "", clean)
    clean = re.sub(r"-+", "-", clean)
    clean = clean.lstrip(".")
    clean = clean.strip("-")
    if not clean:
        raise ValueError(f"Invalid project name: {name!r}")

    projects_dir = os.path.expanduser(os.environ.get("LINKUP_PROJECTS", "~/Desktop/projects"))
    dest = os.path.join(projects_dir, clean)
    if os.path.exists(dest):
        raise FileExistsError(f"Project '{clean}' already exists at {dest}")

    os.makedirs(dest, exist_ok=False)

    if git:
        subprocess.run(["git", "init", "-q"], cwd=dest, check=True)
        try:
            author_name = subprocess.run(["git", "config", "user.name"], capture_output=True, text=True).stdout.strip()
            author_email = subprocess.run(["git", "config", "user.email"], capture_output=True, text=True).stdout.strip()
            if not author_name:
                author_name = os.environ.get("GIT_AUTHOR_NAME", "KNIGHTABDO")
            if not author_email:
                author_email = os.environ.get("GIT_AUTHOR_EMAIL", "201469749+KNIGHTABDO@users.noreply.github.com")
            subprocess.run(["git", "config", "user.name", author_name], cwd=dest)
            subprocess.run(["git", "config", "user.email", author_email], cwd=dest)
        except Exception:
            pass

    tmpl = (template or "").lower().strip()
    readme_created = False
    if readme:
        with open(os.path.join(dest, "README.md"), "w", encoding="utf-8") as f:
            f.write(f"# {clean}\n")
        readme_created = True

    if tmpl in ("", "none", "empty"):
        pass
    elif tmpl == "web":
        with open(os.path.join(dest, "index.html"), "w", encoding="utf-8") as f:
            f.write(f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{clean}</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <h1>{clean}</h1>
  <script src="script.js"></script>
</body>
</html>
""")
        with open(os.path.join(dest, "style.css"), "w", encoding="utf-8") as f:
            f.write("""body {
  font-family: system-ui, -apple-system, sans-serif;
  margin: 2rem;
  line-height: 1.5;
}
""")
        with open(os.path.join(dest, "script.js"), "w", encoding="utf-8") as f:
            f.write(f'console.log("{clean} initialized");\n')

    elif tmpl == "python":
        with open(os.path.join(dest, "main.py"), "w", encoding="utf-8") as f:
            f.write(f'''def main():
    print("Hello from {clean}!")


if __name__ == "__main__":
    main()
''')
        with open(os.path.join(dest, ".gitignore"), "w", encoding="utf-8") as f:
            f.write("""__pycache__/
*.py[cod]
*$py.class
*.so
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg
.env
.venv
venv/
ENV/
""")
        if not readme_created:
            with open(os.path.join(dest, "README.md"), "w", encoding="utf-8") as f:
                f.write(f"# {clean}\n")

    elif tmpl == "ios":
        parts = [p.capitalize() for p in re.split(r"[-_]+", clean) if p]
        mod_name = "".join(parts) or "App"

        with open(os.path.join(dest, "README.md"), "w", encoding="utf-8") as f:
            f.write(f"""# {clean}

A SwiftUI iOS app built by GitHub Actions, targeting iOS 26.
""")

        with open(os.path.join(dest, "project.yml"), "w", encoding="utf-8") as f:
            f.write(f"""name: {mod_name}
options:
  bundleIdPrefix: com.example
  deploymentTarget:
    iOS: "26.0"
settings:
  base:
    SWIFT_VERSION: "5.0"
targets:
  {mod_name}:
    type: application
    platform: iOS
    deploymentTarget: "26.0"
    sources:
      - path: {mod_name}
""")

        app_dir = os.path.join(dest, mod_name)
        os.makedirs(app_dir, exist_ok=True)
        with open(os.path.join(app_dir, "App.swift"), "w", encoding="utf-8") as f:
            f.write(f"""import SwiftUI

@main
struct {mod_name}App: App {{
    var body: some Scene {{
        WindowGroup {{
            ContentView()
        }}
    }}
}}

struct ContentView: View {{
    var body: some View {{
        Text("Hello from {clean}!")
            .padding()
    }}
}}
""")

    return {"name": clean, "path": dest}


def list_dir(path: str) -> list[dict]:
    """[{"name", "path", "isDir", "size", "modified"}] — dirs first, hidden files and node_modules/.git skipped."""
    p = os.path.realpath(os.path.expanduser(path))
    if not os.path.isdir(p):
        raise NotADirectoryError(f"Not a directory: {p}")

    try:
        names = os.listdir(p)
    except OSError:
        return []

    entries = []
    for name in names:
        if name in SKIP_NAMES:
            continue
        full_path = os.path.join(p, name)
        try:
            st = os.stat(full_path)
            is_dir = os.path.isdir(full_path)
        except OSError:
            try:
                st = os.lstat(full_path)
                is_dir = False
            except OSError:
                continue

        if name.startswith(".") and is_dir:
            continue

        entries.append({
            "name": name,
            "path": full_path,
            "isDir": is_dir,
            "size": None if is_dir else st.st_size,
            "modified": st.st_mtime,
        })

    entries.sort(key=lambda e: (not e["isDir"], e["name"].lower()))
    return entries[:2000]


def read_file(path: str, media_url) -> dict:
    """{"path", "text" | None, "url" | None, "size", "language", "truncated"}; media_url(path) -> bridge URL."""
    p = os.path.realpath(os.path.expanduser(path))
    if not os.path.isfile(p):
        raise FileNotFoundError(f"File not found: {p}")

    size = os.path.getsize(p)
    base = os.path.basename(p)
    _, ext = os.path.splitext(base)
    ext_clean = ext.lstrip(".").lower()
    if ext_clean:
        language = ext_clean
    else:
        language = base.lstrip(".").lower()

    url = None
    if ext_clean in MEDIA_URL_EXTS:
        try:
            if callable(media_url):
                url = media_url(p)
        except Exception:
            url = None

    text = None
    truncated = False

    try:
        with open(p, "rb") as f:
            raw = f.read(MAX_TEXT_SIZE + 1)

        is_too_large = len(raw) > MAX_TEXT_SIZE
        if is_too_large:
            raw = raw[:MAX_TEXT_SIZE]

        if b"\x00" not in raw:
            try:
                text = raw.decode("utf-8")
                truncated = is_too_large
            except UnicodeDecodeError as exc:
                if is_too_large and exc.end >= len(raw) - 4:
                    try:
                        text = raw[:exc.start].decode("utf-8")
                        truncated = True
                    except UnicodeDecodeError:
                        text = None
                else:
                    text = None
    except Exception:
        text = None

    return {
        "path": p,
        "text": text,
        "url": url,
        "size": size,
        "language": language or None,
        "truncated": bool(truncated),
    }


async def _run_git(path: str, *args: str, timeout: float = 20.0) -> tuple[int, str, str]:
    proc = await asyncio.create_subprocess_exec(
        "git", "-C", path, *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        try:
            proc.kill()
        except OSError:
            pass
        await proc.communicate()
        raise TimeoutError(f"git {' '.join(args)} timed out after {timeout}s")
    return (
        proc.returncode or 0,
        stdout.decode("utf-8", errors="replace"),
        stderr.decode("utf-8", errors="replace"),
    )


async def _ensure_git_identity(path: str) -> list[str]:
    code_n, out_n, _ = await _run_git(path, "config", "user.name")
    code_e, out_e, _ = await _run_git(path, "config", "user.email")
    extra_args = []
    if code_n != 0 or not out_n.strip():
        name = os.environ.get("GIT_AUTHOR_NAME", "KNIGHTABDO")
        extra_args.extend(["-c", f"user.name={name}"])
    if code_e != 0 or not out_e.strip():
        email = os.environ.get("GIT_AUTHOR_EMAIL", "201469749+KNIGHTABDO@users.noreply.github.com")
        extra_args.extend(["-c", f"user.email={email}"])
    return extra_args


async def git_status(path: str) -> dict:
    """{"isRepo", "branch", "ahead", "behind", "remote", "files": [{"path", "status", "staged"}]}"""
    p = os.path.realpath(os.path.expanduser(path))
    try:
        code, stdout, stderr = await _run_git(p, "status", "--porcelain=v1", "-b")
    except Exception:
        return {"isRepo": False, "branch": None, "ahead": None, "behind": None, "remote": None, "files": []}

    if code != 0:
        return {"isRepo": False, "branch": None, "ahead": None, "behind": None, "remote": None, "files": []}

    lines = stdout.splitlines()
    branch = None
    ahead = None
    behind = None
    remote = None
    files = []

    if lines and lines[0].startswith("## "):
        header = lines[0][3:].strip()
        if header.startswith("HEAD (no branch)"):
            branch = "HEAD"
        elif header.startswith("No commits yet on "):
            branch = header[len("No commits yet on "):].split()[0]
        elif header.startswith("Initial commit on "):
            branch = header[len("Initial commit on "):].split()[0]
        else:
            bracket_m = re.search(r"\[(.*?)\]", header)
            if bracket_m:
                bracket_text = bracket_m.group(1)
                ahead_m = re.search(r"ahead (\d+)", bracket_text)
                ahead = int(ahead_m.group(1)) if ahead_m else 0
                behind_m = re.search(r"behind (\d+)", bracket_text)
                behind = int(behind_m.group(1)) if behind_m else 0
                branch_part = header[:bracket_m.start()].strip()
            else:
                branch_part = header.strip()

            if "..." in branch_part:
                b, u = branch_part.split("...", 1)
                branch = b.strip()
                remote = u.strip()
                if ahead is None:
                    ahead = 0
                if behind is None:
                    behind = 0
            else:
                branch = branch_part.strip()
        file_lines = lines[1:]
    else:
        file_lines = lines

    for line in file_lines:
        if not line:
            continue
        if line.startswith("?? "):
            files.append({
                "path": line[3:].strip().strip('"'),
                "status": "??",
                "staged": False,
            })
        elif len(line) >= 3:
            x, y = line[0], line[1]
            path_part = line[3:].strip().strip('"')
            if " -> " in path_part:
                path_part = path_part.split(" -> ")[-1].strip().strip('"')
            if x != " ":
                staged = True
                status = x
            else:
                staged = False
                status = y
            files.append({
                "path": path_part,
                "status": status,
                "staged": staged,
            })

    return {
        "isRepo": True,
        "branch": branch,
        "ahead": ahead,
        "behind": behind,
        "remote": remote,
        "files": files,
    }


async def git_diff(path: str, file: str | None) -> str:
    p = os.path.realpath(os.path.expanduser(path))
    code, _, _ = await _run_git(p, "rev-parse", "--verify", "HEAD")
    has_head = (code == 0)

    diff_parts = []
    if file:
        if has_head:
            code, out, _ = await _run_git(p, "diff", "HEAD", "--", file)
            if out:
                diff_parts.append(out)
        else:
            code, out_staged, _ = await _run_git(p, "diff", "--cached", "--", file)
            code, out_worktree, _ = await _run_git(p, "diff", "--", file)
            combined = (out_staged + "\n" + out_worktree).strip()
            if combined:
                diff_parts.append(combined)

        code, un_out, _ = await _run_git(p, "ls-files", "--others", "--exclude-standard", "--", file)
        untracked = [f.strip() for f in un_out.splitlines() if f.strip()]
        for uf in untracked:
            code, u_diff, _ = await _run_git(p, "diff", "--no-index", "--", "/dev/null", uf)
            if u_diff:
                diff_parts.append(u_diff)
    else:
        if has_head:
            code, out, _ = await _run_git(p, "diff", "HEAD")
            if out:
                diff_parts.append(out)
        else:
            code, out_staged, _ = await _run_git(p, "diff", "--cached")
            code, out_worktree, _ = await _run_git(p, "diff")
            combined = (out_staged + "\n" + out_worktree).strip()
            if combined:
                diff_parts.append(combined)

        code, un_out, _ = await _run_git(p, "ls-files", "--others", "--exclude-standard")
        untracked = [f.strip() for f in un_out.splitlines() if f.strip()]
        for uf in untracked:
            code, u_diff, _ = await _run_git(p, "diff", "--no-index", "--", "/dev/null", uf)
            if u_diff:
                diff_parts.append(u_diff)

    full_diff = "\n".join(diff_parts)
    raw = full_diff.encode("utf-8")
    if len(raw) > MAX_DIFF_SIZE:
        full_diff = raw[:MAX_DIFF_SIZE].decode("utf-8", errors="ignore") + "\n\n[diff truncated at 400 KB]"

    return full_diff


async def git_log(path: str, limit: int = 30) -> list[dict]:
    """[{"hash", "short", "subject", "author", "date"}]"""
    p = os.path.realpath(os.path.expanduser(path))
    code, stdout, _ = await _run_git(
        p, "log", f"-n{limit}", "--pretty=%H%x1f%h%x1f%s%x1f%an%x1f%ct"
    )
    if code != 0 or not stdout.strip():
        return []

    commits = []
    for line in stdout.splitlines():
        if not line.strip():
            continue
        parts = line.split("\x1f")
        if len(parts) >= 5:
            try:
                date_val = float(parts[4])
            except ValueError:
                date_val = None
            commits.append({
                "hash": parts[0],
                "short": parts[1],
                "subject": parts[2],
                "author": parts[3],
                "date": date_val,
            })
    return commits


async def git_commit(path: str, message: str) -> dict | None:
    p = os.path.realpath(os.path.expanduser(path))
    code, _, _ = await _run_git(p, "add", "-A")
    if code != 0:
        return None

    code, _, _ = await _run_git(p, "diff", "--cached", "--quiet")
    if code == 0:
        return None

    extra = await _ensure_git_identity(p)
    code, _, _ = await _run_git(p, *extra, "commit", "-m", message)
    if code != 0:
        return None

    commits = await git_log(p, limit=1)
    return commits[0] if commits else None


async def git_push(path: str) -> str:
    p = os.path.realpath(os.path.expanduser(path))
    try:
        proc = await asyncio.create_subprocess_exec(
            "git", "-C", p, "push",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=60.0)
        except asyncio.TimeoutError:
            try:
                proc.kill()
            except OSError:
                pass
            await proc.communicate()
            return "git push timed out after 60s"
        out = (stdout.decode("utf-8", errors="replace") + "\n" + stderr.decode("utf-8", errors="replace")).strip()
        return out
    except Exception as exc:
        return f"git push failed: {exc}"


async def gh_runs(path: str, limit: int = 15) -> list[dict]:
    """[{"id", "name", "title", "status", "conclusion", "branch", "event", "url", "created", "artifacts"}]"""
    p = os.path.realpath(os.path.expanduser(path))
    if not shutil.which("gh"):
        return []

    code, remote_out, _ = await _run_git(p, "remote", "-v")
    if code != 0 or not remote_out or "github.com" not in remote_out.lower():
        return []

    fields = "databaseId,name,displayTitle,status,conclusion,headBranch,event,url,createdAt"
    try:
        proc = await asyncio.create_subprocess_exec(
            "gh", "run", "list", f"--limit={limit}", f"--json={fields}",
            cwd=p,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=20.0)
        except asyncio.TimeoutError:
            try:
                proc.kill()
            except OSError:
                pass
            await proc.communicate()
            return []

        if proc.returncode != 0:
            return []

        raw_runs = json.loads(stdout.decode("utf-8", errors="replace"))
    except Exception:
        return []

    runs = []
    for r in raw_runs:
        created_ts = None
        created_at = r.get("createdAt")
        if created_at:
            try:
                created_ts = datetime.fromisoformat(created_at.replace("Z", "+00:00")).timestamp()
            except Exception:
                created_ts = None
        runs.append({
            "id": r.get("databaseId"),
            "name": r.get("name"),
            "title": r.get("displayTitle"),
            "status": r.get("status"),
            "conclusion": r.get("conclusion") or None,
            "branch": r.get("headBranch"),
            "event": r.get("event"),
            "url": r.get("url"),
            "created": created_ts,
            "artifacts": [],
        })
    return runs


def _rewrite_location(loc: str, port: int) -> str:
    pattern = rf"^https?://(?:localhost|127\.0\.0\.1):{port}"
    if re.search(pattern, loc):
        return re.sub(pattern, f"/linkup/proxy/{port}", loc)
    if loc.startswith("/") and not loc.startswith("/linkup/proxy/"):
        return f"/linkup/proxy/{port}{loc}"
    return loc


async def proxy(request: web.Request, port: int, tail: str):
    """aiohttp handler body: reverse-proxies http://127.0.0.1:<port>/<tail> (dev servers) incl. websockets."""
    bridge_port = int(os.environ.get("LINKUP_PORT", "8890"))
    if not (1024 <= port <= 65535) or port in (8890, bridge_port):
        return web.Response(status=403, text="Port not allowed")

    clean_tail = tail.lstrip("/")
    target_path = f"/{clean_tail}" if clean_tail else "/"
    query = f"?{request.query_string}" if request.query_string else ""

    upgrade = request.headers.get("Upgrade", "").lower()
    conn = request.headers.get("Connection", "").lower()
    is_ws = (upgrade == "websocket") or ("upgrade" in conn)

    if is_ws:
        ws_server = web.WebSocketResponse()
        await ws_server.prepare(request)

        target_ws = f"ws://127.0.0.1:{port}{target_path}{query}"
        protocols = []
        subp = request.headers.get("Sec-WebSocket-Protocol")
        if subp:
            protocols = [p.strip() for p in subp.split(",") if p.strip()]

        session = ClientSession()
        try:
            ws_client = await session.ws_connect(target_ws, protocols=protocols)
        except Exception as exc:
            await session.close()
            await ws_server.close(code=1011, message=str(exc).encode("utf-8"))
            return ws_server

        async def forward(ws_from, ws_to):
            try:
                async for msg in ws_from:
                    if msg.type == WSMsgType.TEXT:
                        await ws_to.send_str(msg.data)
                    elif msg.type == WSMsgType.BINARY:
                        await ws_to.send_bytes(msg.data)
                    elif msg.type == WSMsgType.PING:
                        await ws_to.ping(msg.data)
                    elif msg.type == WSMsgType.PONG:
                        await ws_to.pong(msg.data)
                    elif msg.type == WSMsgType.CLOSE:
                        await ws_to.close(code=msg.data or 1000)
                        break
                    elif msg.type in (WSMsgType.CLOSED, WSMsgType.ERROR):
                        break
            except Exception:
                pass

        t1 = asyncio.create_task(forward(ws_server, ws_client))
        t2 = asyncio.create_task(forward(ws_client, ws_server))
        try:
            await asyncio.wait([t1, t2], return_when=asyncio.FIRST_COMPLETED)
        finally:
            for t in (t1, t2):
                t.cancel()
            if not ws_client.closed:
                await ws_client.close()
            await session.close()
            if not ws_server.closed:
                await ws_server.close()
        return ws_server

    target_http = f"http://127.0.0.1:{port}{target_path}{query}"
    req_headers = {}
    for k, v in request.headers.items():
        kl = k.lower()
        if kl not in HOP_BY_HOP and kl != "host":
            req_headers[k] = v
    req_headers["Host"] = f"127.0.0.1:{port}"

    body = None
    if request.can_read_body:
        body = await request.read()

    async with ClientSession(auto_decompress=True) as session:
        try:
            async with session.request(
                request.method,
                target_http,
                headers=req_headers,
                data=body,
                allow_redirects=False,
            ) as upstream_resp:
                resp = web.StreamResponse(status=upstream_resp.status)
                exclude = HOP_BY_HOP | {"content-encoding", "content-length"}
                for k, v in upstream_resp.headers.items():
                    kl = k.lower()
                    if kl in exclude:
                        continue
                    if kl == "location":
                        v = _rewrite_location(v, port)
                    resp.headers[k] = v

                await resp.prepare(request)
                if request.method != "HEAD":
                    async for chunk in upstream_resp.content.iter_chunked(65536):
                        await resp.write(chunk)
                await resp.write_eof()
                return resp
        except ClientConnectorError:
            return web.Response(status=502, text=f"Could not connect to 127.0.0.1:{port}")
        except Exception as exc:
            return web.Response(status=502, text=f"Proxy error: {exc}")
