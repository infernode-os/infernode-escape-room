#!/bin/sh

set -eu

ROOT=${ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}

python3 - "$ROOT" <<'PY'
import importlib.util
import os
import pathlib
import stat
import subprocess
import tempfile

root = pathlib.Path(__import__("sys").argv[1])
spec = importlib.util.spec_from_file_location(
    "prepare_codex_home", root / "scripts" / "prepare-codex-home.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def rejected(message, source, destination):
    try:
        module.prepare_codex_home(source, destination)
    except SystemExit as error:
        assert message in str(error), error
    else:
        raise AssertionError("unsafe home accepted: " + message)


with tempfile.TemporaryDirectory() as temporary:
    login = os.path.join(temporary, "fresh-login")
    campaign = os.path.join(temporary, "campaign")
    os.mkdir(login, 0o700)
    auth = os.path.join(login, "auth.json")
    with open(auth, "w", encoding="utf-8") as output:
        output.write("fresh-oauth-state")
    os.chmod(auth, 0o600)
    os.mkdir(os.path.join(login, "log"), 0o700)
    os.mkdir(os.path.join(login, "tmp"), 0o700)
    with open(os.path.join(login, "version.json"), "w",
              encoding="utf-8") as output:
        output.write("{}")

    assert module.prepare_codex_home(login, campaign) == campaign
    assert sorted(os.listdir(campaign)) == ["auth.json"]
    with open(os.path.join(campaign, "auth.json"), encoding="utf-8") as source:
        assert source.read() == "fresh-oauth-state"
    assert stat.S_IMODE(os.stat(campaign).st_mode) == 0o700
    assert stat.S_IMODE(os.stat(os.path.join(campaign, "auth.json")).st_mode) == 0o600
    assert os.path.isdir(os.path.join(login, "log"))

    rejected("already exists", login, campaign)

    config = os.path.join(login, "config.toml")
    pathlib.Path(config).write_text("untrusted = true", encoding="utf-8")
    rejected("unsanctioned state", login,
             os.path.join(temporary, "with-config"))
    os.unlink(config)

    os.chmod(auth, 0o644)
    rejected("mode 0600", login, os.path.join(temporary, "public-auth"))
    os.chmod(auth, 0o600)

    symlink_login = os.path.join(temporary, "symlink-login")
    os.mkdir(symlink_login, 0o700)
    os.symlink(auth, os.path.join(symlink_login, "auth.json"))
    rejected("symlink", symlink_login,
             os.path.join(temporary, "symlink-auth"))

    rejected("must not be inside", login,
             os.path.join(login, "nested-campaign"))

    os.chmod(login, 0o755)
    rejected("mode 0700", login, os.path.join(temporary, "public-login"))

    os.chmod(login, 0o700)
    cli_campaign = os.path.join(temporary, "cli-campaign")
    result = subprocess.run(
        [str(root / "scripts" / "prepare-codex-home.py"), login,
         cli_campaign], check=True, capture_output=True, text=True)
    assert "prepared auth-only campaign CODEX_HOME" in result.stdout
    assert sorted(os.listdir(cli_campaign)) == ["auth.json"]

print("prepare_codex_home_test: PASS")
PY
