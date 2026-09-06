#!/usr/bin/env python3
"""Opt-in, real BMAD 6.12.0 installations in fresh temporary projects only."""

import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
VERSION = "6.12.0"
HELPER = Path(__file__).with_name("installbmad.py")


def run(argv, target, env, log, timeout):
    with log.open("w", encoding="utf-8") as output:
        process = subprocess.Popen(argv, cwd=target, env=env, stdin=subprocess.DEVNULL,
                                   stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
            # Terminate descendants too, even when the parent already exited.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            raise RuntimeError(f"Timed out after {timeout}s; see {log}") from None
    if code:
        raise RuntimeError(f"Command exited {code}; see {log}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="Authorize package downloads and temporary installs")
    parser.add_argument("--timeout", type=int, default=240, help="Maximum seconds per command (default: 240)")
    args = parser.parse_args()
    if not args.run:
        parser.error("Nothing installed. Pass --run to opt in to the live smoke test.")
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    if os.name != "posix":
        parser.error("This smoke harness supports macOS/Linux process groups only")
    if not os.environ.get("TMPDIR") or not Path(os.environ["TMPDIR"]).is_dir():
        parser.error("TMPDIR must name a writable temporary directory")
    for tool in ("node", "npx", "uv"):
        if not shutil.which(tool):
            parser.error(f"{tool} is required for this live smoke (not for the read-only helper)")

    root = Path(tempfile.mkdtemp(prefix="installbmad-live-", dir=os.environ["TMPDIR"])).resolve()
    print(f"Smoke artifacts: {root}", flush=True)
    env = os.environ.copy()
    directories = {
        "HOME": "home", "TMPDIR": "tmp", "XDG_CACHE_HOME": "cache", "XDG_CONFIG_HOME": "config",
        "XDG_DATA_HOME": "data", "npm_config_cache": "cache/npm", "UV_CACHE_DIR": "cache/uv",
        "UV_PYTHON_INSTALL_DIR": "python", "UV_TOOL_DIR": "tools",
    }
    for key, relative in directories.items():
        directory = root / relative
        directory.mkdir(parents=True, exist_ok=True)
        env[key] = str(directory)
    npmrc = root / "npmrc"
    npmrc.write_text("")
    env.update({"npm_config_userconfig": str(npmrc), "npm_config_update_notifier": "false",
                "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0",
                "UV_NO_CONFIG": "1", "PYTHONDONTWRITEBYTECODE": "1"})
    env.pop("VIRTUAL_ENV", None)
    fresh, existing = root / "fresh", root / "existing"
    fresh.mkdir()
    existing.mkdir()
    try:
        for label, target, modules in (("fresh-bmm", fresh, "bmm"), ("core-only", existing, "core"),
                                       ("add-bmm", existing, "bmm")):
            before = root / f"{label}-before.json"
            run([sys.executable, "-B", str(HELPER), "preflight", "--target", str(target),
                 "--installer-version", VERSION, "--modules", modules, "--tools", "claude-code"],
                target, env, before, args.timeout)
            plan = json.loads(before.read_text())
            run(plan["argv"] + ["--user-name", "smoke-test"], target, env, root / f"{label}-install.log", args.timeout)
            verification = root / f"{label}-verify.json"
            run([sys.executable, "-B", str(HELPER), "verify", "--target", str(target), "--before", str(before)],
                target, env, verification, args.timeout)
            result = json.loads(verification.read_text())
            if result["status"] != "files_verified":
                raise RuntimeError(f"File verification failed: {verification}")
            print(f"PASS: {label} ({target})", flush=True)
        config = root / "resolve-config.json"
        run(["uv", "run", "--no-project", str(existing / "_bmad/scripts/resolve_config.py"),
             "--project-root", str(existing)], existing, env, config, args.timeout)
        # uv may emit setup diagnostics before the resolver's JSON. The exit code
        # is checked above; retain the full output rather than hiding those logs.
        print(f"PASS: configuration resolver ({config})", flush=True)
    except (OSError, ValueError, RuntimeError) as error:
        print(f"FAIL: {error}\nArtifacts retained: {root}", file=sys.stderr)
        return 1
    print("Live smoke passed. External bmb/cis modules and new-session skill loading were not tested.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
