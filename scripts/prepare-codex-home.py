#!/usr/bin/env python3
"""Stage a fresh Codex OAuth credential for an isolated campaign."""

import argparse
import os
import shutil
import stat


LOGIN_SOURCE_ALLOW = frozenset((
    "auth.json",
    "auth.json.lock",
    "version.json",
    "installation_id",
    "log",
    "tmp",
))


def fail(message):
    raise SystemExit("prepare-codex-home: " + message)


def prepare_codex_home(source, destination):
    source = os.path.abspath(os.path.expanduser(source))
    destination = os.path.abspath(os.path.expanduser(destination))
    source_real = os.path.realpath(source)
    destination_real = os.path.realpath(destination)
    if source == destination:
        fail("login source and campaign home are the same")
    try:
        nested = os.path.commonpath((source_real, destination_real)) == source_real
    except ValueError:
        nested = False
    if nested:
        fail("campaign home must not be inside login source")

    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    try:
        source_fd = os.open(source, flags)
    except OSError as error:
        fail("cannot open login source safely: %s" % error)

    try:
        source_stat = os.fstat(source_fd)
        if not stat.S_ISDIR(source_stat.st_mode):
            fail("login source must be a real directory")
        if stat.S_IMODE(source_stat.st_mode) != 0o700:
            fail("login source holds credentials and must be mode 0700")
        if hasattr(os, "geteuid") and source_stat.st_uid != os.geteuid():
            fail("login source is not owned by this user")

        try:
            names = set(os.listdir(source_fd))
        except OSError as error:
            fail("cannot read login source: %s" % error)
        unexpected = sorted(names - LOGIN_SOURCE_ALLOW)
        if unexpected:
            fail("login source contains unsanctioned state: %s" %
                 ", ".join(repr(name) for name in unexpected))
        if "auth.json" not in names:
            fail("login source has no auth.json")

        for name in sorted(names):
            try:
                entry_stat = os.stat(name, dir_fd=source_fd,
                                     follow_symlinks=False)
            except OSError as error:
                fail("cannot inspect login source entry: %s" % error)
            if stat.S_ISLNK(entry_stat.st_mode):
                fail("login source entry %r is a symlink" % name)
            expected = stat.S_ISDIR if name in ("log", "tmp") else stat.S_ISREG
            if not expected(entry_stat.st_mode):
                fail("login source entry %r has wrong type" % name)

        auth_flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
        try:
            auth_fd = os.open("auth.json", auth_flags, dir_fd=source_fd)
        except OSError as error:
            fail("cannot open login auth.json safely: %s" % error)
        try:
            auth_stat = os.fstat(auth_fd)
            if not stat.S_ISREG(auth_stat.st_mode) or auth_stat.st_size == 0:
                fail("login auth.json must be a non-empty regular file")
            if stat.S_IMODE(auth_stat.st_mode) != 0o600:
                fail("login auth.json must be mode 0600")
            if hasattr(os, "geteuid") and auth_stat.st_uid != os.geteuid():
                fail("login auth.json is not owned by this user")

            try:
                os.mkdir(destination, 0o700)
            except FileExistsError:
                fail("campaign home already exists; use a new path")
            except OSError as error:
                fail("cannot create campaign home: %s" % error)

            tmp_path = os.path.join(destination,
                                    ".auth.json.tmp-%d" % os.getpid())
            try:
                out_flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
                out_flags |= getattr(os, "O_NOFOLLOW", 0)
                out_fd = os.open(tmp_path, out_flags, 0o600)
                try:
                    while True:
                        chunk = os.read(auth_fd, 1 << 20)
                        if not chunk:
                            break
                        view = memoryview(chunk)
                        while view:
                            written = os.write(out_fd, view)
                            if written <= 0:
                                raise OSError("short write preparing campaign home")
                            view = view[written:]
                    os.fsync(out_fd)
                finally:
                    os.close(out_fd)
                os.replace(tmp_path, os.path.join(destination, "auth.json"))
                os.chmod(destination, 0o700)
                dir_fd = os.open(destination, flags)
                try:
                    os.fsync(dir_fd)
                finally:
                    os.close(dir_fd)
            except BaseException:
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass
                try:
                    shutil.rmtree(destination)
                except OSError:
                    pass
                raise
        finally:
            os.close(auth_fd)
    finally:
        os.close(source_fd)

    return destination


def main():
    parser = argparse.ArgumentParser(
        description="stage fresh OAuth state in a new campaign CODEX_HOME")
    parser.add_argument("login_home")
    parser.add_argument("campaign_home")
    args = parser.parse_args()
    destination = prepare_codex_home(args.login_home, args.campaign_home)
    print("prepared auth-only campaign CODEX_HOME at %s" % destination)


if __name__ == "__main__":
    main()
