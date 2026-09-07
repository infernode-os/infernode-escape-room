#!/usr/bin/env python3
"""Emit a content-free, reproducible inventory of an isolated Codex home."""

import argparse
import hashlib
import json
import os
import stat


SENSITIVE_TOP_LEVEL = frozenset((
    "auth.json",
    "auth.json.lock",
    "installation_id",
))


def fail(message):
    raise SystemExit("inventory-codex-home: " + message)


def file_sha256(path):
    digest = hashlib.sha256()
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags)
    try:
        while True:
            chunk = os.read(fd, 1 << 20)
            if not chunk:
                break
            digest.update(chunk)
    finally:
        os.close(fd)
    return digest.hexdigest()


def inventory(home):
    home = os.path.abspath(os.path.expanduser(home))
    try:
        root = os.lstat(home)
    except OSError as error:
        fail("cannot inspect home: %s" % error)
    if not stat.S_ISDIR(root.st_mode) or stat.S_ISLNK(root.st_mode):
        fail("home must be a real directory")
    if stat.S_IMODE(root.st_mode) != 0o700:
        fail("home holds credentials and must be mode 0700")
    if hasattr(os, "geteuid") and root.st_uid != os.geteuid():
        fail("home is not owned by this user")

    entries = []
    total = 0
    credential_files = 0
    for dirpath, dirnames, filenames in os.walk(home, followlinks=False):
        dirnames.sort()
        filenames.sort()
        safe_dirs = []
        for name in dirnames:
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, home)
            try:
                mode = os.lstat(path).st_mode
            except OSError:
                entries.append({"path": rel, "type": "unreadable"})
                continue
            if stat.S_ISLNK(mode):
                entries.append({"path": rel, "type": "symlink"})
                continue
            safe_dirs.append(name)
        dirnames[:] = safe_dirs

        for name in filenames:
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, home)
            top = rel.split(os.sep, 1)[0]
            sensitive = top in SENSITIVE_TOP_LEVEL
            try:
                info = os.lstat(path)
                entry = {
                    "path": rel,
                    "size": info.st_size,
                    "mode": oct(stat.S_IMODE(info.st_mode)),
                }
                if stat.S_ISLNK(info.st_mode):
                    entry["type"] = "symlink"
                elif not stat.S_ISREG(info.st_mode):
                    entry["type"] = "special"
                elif sensitive:
                    entry["type"] = "credential"
                    entry["content"] = "redacted"
                    credential_files += 1
                else:
                    entry["type"] = "file"
                    entry["sha256"] = file_sha256(path)
                entries.append(entry)
                total += info.st_size
            except OSError:
                entries.append({"path": rel, "type": "unreadable"})

    canonical = json.dumps(entries, sort_keys=True, separators=(",", ":"))
    files = sum(1 for entry in entries if entry.get("type") != "symlink")
    return {
        "schema": "infernode-escape-room/codex-home-inventory/v1",
        "files": files,
        "bytes": total,
        "credential_files": credential_files,
        "persistent_cli_state_files": files - credential_files,
        "persistent_cli_state": files > credential_files,
        "sha256": hashlib.sha256(canonical.encode()).hexdigest(),
        "entries": entries,
    }


def main():
    parser = argparse.ArgumentParser(
        description="inventory an isolated Codex home without credential contents")
    parser.add_argument("codex_home")
    args = parser.parse_args()
    print(json.dumps(inventory(args.codex_home), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
