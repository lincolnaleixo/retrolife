#!/usr/bin/env python3
"""Stage the exact upstream Sparkle SDK outside application Git history."""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath
import shutil
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
VERSION = "2.10.0"
SHA256 = "c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
URL = f"https://github.com/sparkle-project/Sparkle/releases/download/{VERSION}/Sparkle-{VERSION}.tar.xz"
DESTINATION = ROOT / ".cache" / "sparkle" / VERSION
MAX_BYTES = 40 * 1024 * 1024


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def safe_unpack(archive: Path, destination: Path) -> None:
    """Allow internal framework symlinks, never absolute/escaping links or devices."""
    with tarfile.open(archive, "r:xz") as stream:
        members = stream.getmembers()
        if len(members) > 10000 or sum(m.size for m in members) > 512 * 1024 * 1024:
            raise ValueError("Updater SDK exceeds extraction limits")
        root = destination.resolve()
        for member in members:
            name = PurePosixPath(member.name)
            if name.is_absolute() or ".." in name.parts or not (member.isfile() or member.isdir() or member.issym()):
                raise ValueError("Unsafe SDK archive member")
            if member.issym():
                link = PurePosixPath(member.linkname)
                target = (root / name.parent / member.linkname).resolve()
                if link.is_absolute() or not target.is_relative_to(root):
                    raise ValueError("Unsafe SDK symlink")
        # Python's data filter also protects subsequent writes through symlinks.
        if not hasattr(tarfile, "data_filter"):
            raise ValueError("Python with tarfile.data_filter is required (3.12+ or security-patched 3.11)")
        stream.extractall(destination, members=members, filter="data")
    if not (destination / "Sparkle.framework" / "Sparkle").is_file():
        raise ValueError("Sparkle framework is missing")
    for name in ("generate_keys", "sign_update"):
        if not (destination / "bin" / name).is_file():
            raise ValueError("Sparkle signing tools are missing")
    if not (destination / "LICENSE").is_file():
        raise ValueError("Sparkle notices are missing")


def prepare(archive: Path | None = None, offline: bool = False) -> Path:
    cache = ROOT / ".cache" / "sparkle"
    cache.mkdir(parents=True, exist_ok=True)
    source = archive or cache / f"Sparkle-{VERSION}.tar.xz"
    if not source.is_file():
        if offline or archive:
            raise ValueError("Pinned Sparkle archive is missing; provide --archive or allow the initial download")
        fd, temporary = tempfile.mkstemp(prefix="sparkle-download-", dir=cache)
        try:
            with os.fdopen(fd, "wb") as output, urllib.request.urlopen(URL, timeout=60) as response:
                total = 0
                while chunk := response.read(1024 * 1024):
                    total += len(chunk)
                    if total > MAX_BYTES:
                        raise ValueError("Sparkle download exceeds limit")
                    output.write(chunk)
            if digest(Path(temporary)) != SHA256:
                raise ValueError("Sparkle download checksum mismatch")
            Path(temporary).replace(source)
        finally:
            Path(temporary).unlink(missing_ok=True)
    if source.stat().st_size > MAX_BYTES or digest(source) != SHA256:
        raise ValueError("Pinned Sparkle archive checksum mismatch")
    # Re-extract verified bytes, not a stamp that could hide a modified executable.
    with tempfile.TemporaryDirectory(prefix="stage-", dir=cache) as temporary:
        staged = Path(temporary) / "sdk"
        staged.mkdir()
        safe_unpack(source, staged)
        if DESTINATION.exists():
            shutil.rmtree(DESTINATION)
        staged.replace(DESTINATION)
    return DESTINATION


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    try:
        print(prepare(args.archive, args.offline))
    except (OSError, ValueError, tarfile.TarError) as error:
        parser.exit(1, f"Sparkle preparation failed: {error}\n")
