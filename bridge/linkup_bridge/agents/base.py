"""Shared pieces for agent adapters: the normalized event vocabulary and media/artifact detection.

Normalized events (all carry `type`; the store adds `seq`/`ts`):
  user            {text, attachments:[{name, url, mime}]}
  turn.start      {}
  status          {state: requesting|running|idle|error|interrupted, detail?}
  thinking.start  {block}            thinking.delta {block, text}      thinking.end {block}
  text.start      {block}            text.delta     {block, text}      text.end     {block}
  tool.start      {id, name, input, parent?}       tool.input {id, partial}    tool.update {id, input}
  tool.end        {id, output, isError, images:[url], parent?}
  artifact        {id, kind: html|svg|markdown|image|pdf|video|audio|code|file, title, url, path, mime}
  permission.request {id, tool, input}             permission.resolved {id, allow}
  usage           {inputTokens, outputTokens, cacheRead, cacheWrite, costUsd?, contextTokens?}
  ratelimit       {fiveHour:{utilization, resetsAt}, sevenDay:{...}, status}
  notice          {text}
  turn.end        {stopReason, durationMs, costUsd?, isError, text?}
  error           {message}
"""
from __future__ import annotations

import mimetypes
import os
import re

MEDIA_EXT = {
    "png": "image", "jpg": "image", "jpeg": "image", "gif": "image", "webp": "image", "heic": "image",
    "svg": "svg", "html": "html", "htm": "html", "pdf": "pdf", "md": "markdown",
    "mp4": "video", "mov": "video", "webm": "video", "mp3": "audio", "wav": "audio", "m4a": "audio",
}
_PATH_RE = re.compile(r"""(?:file://)?((?:/|~/)[^\s'"`<>()\[\]{}]+\.(?:%s))\b""" % "|".join(MEDIA_EXT), re.IGNORECASE)


def kind_of(path: str) -> str:
    return MEDIA_EXT.get(path.rsplit(".", 1)[-1].lower(), "file")


def mime_of(path: str) -> str:
    return mimetypes.guess_type(path)[0] or "application/octet-stream"


def paths_in(text: str) -> list[str]:
    """Existing media/artifact files mentioned in agent output (absolute or ~ paths)."""
    found = []
    for m in _PATH_RE.finditer(text or ""):
        path = os.path.expanduser(m.group(1).rstrip(".,;:"))
        if os.path.isfile(path) and path not in found and os.path.getsize(path) < 200 << 20:
            found.append(path)
    return found[:12]


class Media:
    """Turns a file on the PC into an event the phone can render, with a URL the bridge serves."""

    def __init__(self, store):
        self.store = store

    def url(self, path: str) -> str:
        fid = self.store.register_file(path, mime_of(path))
        return f"/linkup/files/{fid}/{os.path.basename(path)}"

    def artifact(self, path: str, title: str | None = None) -> dict | None:
        try:
            if not os.path.isfile(path):
                return None
            size = os.path.getsize(path)
        except OSError:
            return None
        return {"type": "artifact", "id": self.url(path).split("/")[3], "kind": kind_of(path),
                "title": title or os.path.basename(path), "url": self.url(path), "path": path,
                "mime": mime_of(path), "size": size}
