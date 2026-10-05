"""STUB (task bridge-workspace): projects, files, git, GitHub Actions and the dev-server proxy."""
from __future__ import annotations

import os

PROJECTS = os.path.expanduser(os.environ.get("LINKUP_PROJECTS", "~/Desktop/projects"))


def allowed(path: str) -> bool:
    """Only paths inside the user's home directory are reachable from the phone."""
    p = os.path.realpath(os.path.expanduser(path))
    return p == os.path.expanduser("~") or p.startswith(os.path.expanduser("~") + os.sep)


def create_project(name: str, git: bool, readme: bool, template: str | None) -> dict:
    """Creates PROJECTS/<name> (+ git init / README / template); returns {"name", "path"}."""
    raise NotImplementedError


def list_dir(path: str) -> list[dict]:
    """[{"name", "path", "isDir", "size", "modified"}] — dirs first, hidden files and node_modules/.git skipped."""
    raise NotImplementedError


def read_file(path: str, media_url) -> dict:
    """{"path", "text" | None, "url" | None, "size", "language", "truncated"}; media_url(path) -> bridge URL."""
    raise NotImplementedError


async def git_status(path: str) -> dict:
    """{"isRepo", "branch", "ahead", "behind", "remote", "files": [{"path", "status", "staged"}]}"""
    raise NotImplementedError


async def git_diff(path: str, file: str | None) -> str:
    raise NotImplementedError


async def git_log(path: str, limit: int = 30) -> list[dict]:
    """[{"hash", "short", "subject", "author", "date"}]"""
    raise NotImplementedError


async def git_commit(path: str, message: str) -> dict | None:
    raise NotImplementedError


async def git_push(path: str) -> str:
    raise NotImplementedError


async def gh_runs(path: str, limit: int = 15) -> list[dict]:
    """[{"id", "name", "title", "status", "conclusion", "branch", "event", "url", "created", "artifacts"}]"""
    raise NotImplementedError


async def proxy(request, port: int, tail: str):
    """aiohttp handler body: reverse-proxies http://127.0.0.1:<port>/<tail> (dev servers) incl. websockets."""
    raise NotImplementedError
