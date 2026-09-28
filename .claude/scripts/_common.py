"""Shared helpers for the token-saving edit scripts.

Every script preserves each file's line-ending style (CRLF/LF), its final
newline, and writes atomically (temp file + os.replace).
"""
import os
import shutil
import stat
import sys
import tempfile

# temp/ holds throwaway scripts and output; it is never part of the project.
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", ".idea", ".vscode", "temp"}

# Windows consoles default to cp1252; force UTF-8 so non-ASCII never crashes output.
for stream in (sys.stdout, sys.stderr):
    try:
        stream.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass


def die(msg, code=1):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def read(path):
    """Return (text_with_LF, eol) where eol is the file's dominant line ending."""
    try:
        with open(path, "r", encoding="utf-8", newline="") as f:
            raw = f.read()
    except UnicodeDecodeError:
        die(f"{path}: not valid UTF-8")
    crlf = raw.count("\r\n")
    lf = raw.count("\n") - crlf
    eol = "\r\n" if crlf > lf else "\n"
    return raw.replace("\r\n", "\n"), eol


def write(path, text_lf, eol):
    """Atomically write LF text back using the given line ending."""
    data = text_lf.replace("\n", eol) if eol != "\n" else text_lf
    folder = os.path.dirname(os.path.abspath(path))
    fd, tmp = tempfile.mkstemp(dir=folder, prefix=".edit-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(data)
        if os.path.exists(path):
            shutil.copymode(path, tmp)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise


def read_stdin():
    return sys.stdin.buffer.read().decode("utf-8").replace("\r\n", "\n")


def is_binary(path):
    try:
        with open(path, "rb") as f:
            return b"\0" in f.read(8192)
    except OSError:
        return True


def is_link(path):
    """True for symlinks and Windows junctions (os.path.islink misses those)."""
    if os.path.islink(path):
        return True
    try:
        attrs = getattr(os.lstat(path), "st_file_attributes", 0)
    except OSError:
        return False
    return bool(attrs & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0))


def walk(roots, exts=None):
    """Yield files under roots (files or dirs), skipping VCS/tooling dirs.

    A root that is a link (e.g. the tutorial/ junction) is followed; links met
    inside the walk are not, so the default "." stays within this repo.
    """
    for root in roots or ["."]:
        if os.path.isfile(root):
            yield os.path.normpath(root)
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = sorted(d for d in dirnames
                                 if d not in SKIP_DIRS and not is_link(os.path.join(dirpath, d)))
            for name in sorted(filenames):
                if exts and not name.lower().endswith(tuple(exts)):
                    continue
                yield os.path.normpath(os.path.join(dirpath, name))


def rel(path):
    return os.path.relpath(path).replace("\\", "/")
